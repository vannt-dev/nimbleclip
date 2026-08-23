[CmdletBinding()]
param(
    [string]$EmulatorId = 'Aegis_API_34',
    [string]$DeviceId,
    [ValidateRange(15, 300)]
    [int]$BootTimeoutSeconds = 90,
    [switch]$SkipAndroid,
    [switch]$SkipWebBuild
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

        if (-not (Test-LocalPort -Port 8097)) {
            Write-Host 'Starting the Android fixture server...' -ForegroundColor DarkGray
            $fixtureProcess = Start-Process `
                -FilePath 'node' `
                -ArgumentList 'tool/fixture_server.js' `
                -WorkingDirectory $projectRoot `
                -WindowStyle Hidden `
                -PassThru

            $fixtureDeadline = (Get-Date).AddSeconds(30)
            while (-not (Test-LocalPort -Port 8097)) {
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
            Write-Host 'Reusing the fixture server already listening on port 8097.' `
                -ForegroundColor DarkGray
        }

        Write-Host "Running Android integration tests on $resolvedDeviceId..." `
            -ForegroundColor Cyan
        Invoke-CheckedCommand 'flutter' @(
            'test',
            'integration_test/android_storage_test.dart',
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
