[CmdletBinding()]
param(
    [string]$EmulatorId = 'Aegis_API_34',
    [string]$DeviceId,
    [string]$PackageId = 'com.vannt.nimbleclip',
    [ValidateRange(15, 300)]
    [int]$BootTimeoutSeconds = 90,
    [switch]$Release,
    [switch]$KeepRunningApp
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot

function Get-ConnectedAndroidEmulator {
    $rawDevices = & flutter devices --machine 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to query Flutter devices.'
    }

    $devicesJson = $rawDevices -join [Environment]::NewLine
    # On Windows PowerShell 5, wrapping ConvertFrom-Json in @() creates a
    # nested Object[]; property access then combines every device into one.
    $devices = ConvertFrom-Json -InputObject $devicesJson
    $androidEmulator = $devices |
        Where-Object {
            $_.emulator -eq $true -and
            $_.targetPlatform -like 'android-*' -and
            ([string]::IsNullOrWhiteSpace($DeviceId) -or $_.id -eq $DeviceId)
        } |
        Select-Object -First 1
    return $androidEmulator
}

function Get-AdbPath {
    $adbCommand = Get-Command adb -ErrorAction SilentlyContinue
    if ($null -ne $adbCommand) {
        return $adbCommand.Source
    }

    $propertiesPath = Join-Path $projectRoot 'android\local.properties'
    if (-not (Test-Path -LiteralPath $propertiesPath)) {
        return $null
    }

    $sdkLine = Get-Content -LiteralPath $propertiesPath |
        Where-Object { $_ -match '^sdk\.dir=' } |
        Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($sdkLine)) {
        return $null
    }

    $sdkPath = ($sdkLine -replace '^sdk\.dir=', '') -replace '\\:', ':'
    $sdkPath = $sdkPath -replace '\\\\', '\'
    $candidate = Join-Path $sdkPath 'platform-tools\adb.exe'
    if (Test-Path -LiteralPath $candidate) {
        return $candidate
    }
    return $null
}

$device = Get-ConnectedAndroidEmulator
if ($null -eq $device) {
    Write-Host "Starting Android emulator '$EmulatorId'..." -ForegroundColor Cyan
    & flutter emulators --launch $EmulatorId
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to launch emulator '$EmulatorId'."
    }

    $deadline = (Get-Date).AddSeconds($BootTimeoutSeconds)
    do {
        Start-Sleep -Seconds 2
        $device = Get-ConnectedAndroidEmulator
    } while ($null -eq $device -and (Get-Date) -lt $deadline)

    if ($null -eq $device) {
        throw "The emulator did not connect within $BootTimeoutSeconds seconds."
    }
}

Write-Host "Using $($device.name) [$($device.id)]." -ForegroundColor Green

if (-not $KeepRunningApp) {
    $adbPath = Get-AdbPath
    if ($null -ne $adbPath) {
        Write-Host 'Closing the previous NimbleClip instance...' -ForegroundColor DarkGray
        & $adbPath -s $device.id shell am force-stop $PackageId | Out-Null
    } else {
        Write-Warning 'ADB was not found; Flutter will still reinstall and launch the app.'
    }
}

$runArguments = @('run', '--no-pub', '-d', $device.id, '--device-timeout', '15')
if ($Release) {
    $runArguments += '--release'
}

Write-Host 'Launching NimbleClip. Press Ctrl+C to stop Flutter run.' -ForegroundColor Cyan
& flutter @runArguments
exit $LASTEXITCODE
