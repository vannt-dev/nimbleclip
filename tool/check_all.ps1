[CmdletBinding()]
param(
    [string]$EmulatorId = 'Aegis_API_34',
    [string]$DeviceId,
    [ValidateRange(15, 300)]
    [int]$BootTimeoutSeconds = 90,
    [switch]$SkipAndroid,
    [switch]$SkipWebBuild,
    [switch]$RunLiveExtractors,
    [string]$InstagramImageUrl,
    [string]$InstagramVideoUrl
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed ($LASTEXITCODE): $Command $($Arguments -join ' ')"
    }
}

function Test-LocalPort {
    param([int]$Port)

    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $connection = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        if (-not $connection.AsyncWaitHandle.WaitOne(250)) {
            return $false
        }
        $client.EndConnect($connection)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Dispose()
    }
}

function Test-FixtureServer {
    try {
        $response = Invoke-WebRequest `
            -Uri 'http://127.0.0.1:8097/health' `
            -UseBasicParsing `
            -TimeoutSec 2
        if ($response.StatusCode -ne 200) {
            return $false
        }
        $health = $response.Content | ConvertFrom-Json
        return $health.service -eq 'nimbleclip-fixture' -and $health.status -eq 'ok'
    }
    catch {
        return $false
    }
}

foreach ($requiredCommand in @('dart', 'flutter', 'node')) {
    if ($null -eq (Get-Command $requiredCommand -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $requiredCommand"
    }
}

$startedAt = Get-Date
$fixtureProcess = $null

try {
    Write-Host '1/7 Checking Dart formatting...' -ForegroundColor Cyan
    Invoke-CheckedCommand 'dart' @(
        'format',
        '--output=none',
        '--set-exit-if-changed',
        'lib',
        'test',
        'integration_test'
    )

    Write-Host '2/7 Running Flutter static analysis...' -ForegroundColor Cyan
    Invoke-CheckedCommand 'flutter' @('analyze')

    Write-Host '3/7 Checking Node.js syntax...' -ForegroundColor Cyan
    Invoke-CheckedCommand 'node' @('--check', 'server.js')
    Invoke-CheckedCommand 'node' @('--check', 'tool/fixture_server.js')

    Write-Host '4/7 Running Flutter tests...' -ForegroundColor Cyan
    Invoke-CheckedCommand 'flutter' @('test')
    if ($RunLiveExtractors) {
        Write-Host 'Running opt-in live extractor smoke tests...' -ForegroundColor Cyan
        $liveArguments = @(
            'test',
            'test/live_extractor_smoke_test.dart',
            '--dart-define=RUN_LIVE_EXTRACTOR_TESTS=true'
        )
        if (-not [string]::IsNullOrWhiteSpace($InstagramImageUrl)) {
            $liveArguments += "--dart-define=INSTAGRAM_IMAGE_URL=$InstagramImageUrl"
        }
        if (-not [string]::IsNullOrWhiteSpace($InstagramVideoUrl)) {
            $liveArguments += "--dart-define=INSTAGRAM_VIDEO_URL=$InstagramVideoUrl"
        }
        Invoke-CheckedCommand 'flutter' $liveArguments
    }

    Write-Host '5/7 Running Node.js tests...' -ForegroundColor Cyan
    Invoke-CheckedCommand 'node' @('--test', 'test/server_test.js')

    if ($SkipWebBuild) {
        Write-Host '6/7 Skipping the release Web build.' -ForegroundColor DarkGray
    }
    else {
        Write-Host '6/7 Building the release Web bundle...' -ForegroundColor Cyan
        Invoke-CheckedCommand 'flutter' @(
            'build',
            'web',
            '--release',
            '--no-wasm-dry-run'
        )
    }

    if ($SkipAndroid) {
        Write-Host '7/7 Skipping Android integration tests.' -ForegroundColor DarkGray
    }
    else {
        Write-Host '7/7 Preparing Android emulator...' -ForegroundColor Cyan
        $launcherParameters = @{
            PrepareOnly = $true
            EmulatorId = $EmulatorId
            BootTimeoutSeconds = $BootTimeoutSeconds
        }
        if (-not [string]::IsNullOrWhiteSpace($DeviceId)) {
            $launcherParameters.DeviceId = $DeviceId
        }
        $launcherOutput = @(
            & "$PSScriptRoot\run_android_emulator.ps1" @launcherParameters
        )
        $resolvedDeviceId = $launcherOutput |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Last 1
        if ([string]::IsNullOrWhiteSpace($resolvedDeviceId)) {
            throw 'Android launcher did not return a device id.'
        }

        $portInUse = Test-LocalPort -Port 8097
        if ($portInUse -and -not (Test-FixtureServer)) {
            throw 'Port 8097 is occupied by a process that is not the NimbleClip fixture server.'
        }

        if (-not $portInUse) {
            Write-Host 'Starting the Android fixture server...' -ForegroundColor DarkGray
            $fixtureProcess = Start-Process `
                -FilePath 'node' `
                -ArgumentList 'tool/fixture_server.js' `
                -WorkingDirectory $projectRoot `
                -WindowStyle Hidden `
                -PassThru

            $fixtureDeadline = (Get-Date).AddSeconds(30)
            while (-not (Test-FixtureServer)) {
                if ($fixtureProcess.HasExited) {
                    throw "Fixture server exited with code $($fixtureProcess.ExitCode)."
                }
                if ((Get-Date) -ge $fixtureDeadline) {
                    throw 'Fixture server did not listen on port 8097 within 30 seconds.'
                }
                Start-Sleep -Milliseconds 250
            }
        }
        else {
            Write-Host 'Reusing the verified fixture server on port 8097.' `
                -ForegroundColor DarkGray
        }

        Write-Host "Running Android integration tests on $resolvedDeviceId..." `
            -ForegroundColor Cyan
        Invoke-CheckedCommand 'flutter' @(
            'test',
            'integration_test/android_storage_test.dart',
            'integration_test/slideshow_render_test.dart',
            '-d',
            $resolvedDeviceId
        )
    }
}
finally {
    if ($null -ne $fixtureProcess -and -not $fixtureProcess.HasExited) {
        Write-Host 'Stopping the Android fixture server...' -ForegroundColor DarkGray
        Stop-Process -Id $fixtureProcess.Id -ErrorAction SilentlyContinue
    }
}

$elapsed = (Get-Date) - $startedAt
Write-Host (
    'All checks passed in {0:mm\:ss}.' -f $elapsed
) -ForegroundColor Green
