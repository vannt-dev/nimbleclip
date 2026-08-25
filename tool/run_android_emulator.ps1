[CmdletBinding()]
param(
    [string]$EmulatorId = 'Aegis_API_34',
    [string]$DeviceId,
    [string]$PackageId = 'com.vannt.nimbleclip',
    [ValidateRange(15, 300)]
    [int]$BootTimeoutSeconds = 90,
    [switch]$Release,
    [switch]$KeepRunningApp,
    [switch]$PrepareOnly
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

function Get-AndroidSdkPath {
    $propertiesPath = Join-Path $projectRoot 'android\local.properties'
    if (-not (Test-Path -LiteralPath $propertiesPath)) { return $null }
    $sdkLine = Get-Content -LiteralPath $propertiesPath |
        Where-Object { $_ -match '^sdk\.dir=' } |
        Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($sdkLine)) { return $null }
    return (($sdkLine -replace '^sdk\.dir=', '') -replace '\\:', ':') -replace '\\\\', '\'
}

function Get-AvdProcess {
    $escapedId = [Regex]::Escape($EmulatorId)
    return Get-CimInstance Win32_Process -Filter "Name = 'qemu-system-x86_64.exe'" `
        -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match "-avd\s+`"?$escapedId(?:`"|\s|$)" } |
        Select-Object -First 1
}

function Stop-SelectedAvd {
    $avdProcess = Get-AvdProcess
    if ($null -eq $avdProcess) { return }
    Write-Host "Stopping unresponsive AVD '$EmulatorId' (PID $($avdProcess.ProcessId))..." `
        -ForegroundColor DarkGray
    Stop-Process -Id $avdProcess.ProcessId -Force -ErrorAction SilentlyContinue
    $deadline = (Get-Date).AddSeconds(10)
    while ($null -ne (Get-AvdProcess) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 250
    }
}

function Wait-ForAndroidEmulator {
    param([int]$TimeoutSeconds, [System.Diagnostics.Process]$Process)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Seconds 2
        $connected = Get-ConnectedAndroidEmulator
        if ($null -ne $connected) { return $connected }
        # emulator.exe can hand off to qemu-system and exit successfully, so
        # its lifetime alone does not mean the AVD failed to start.
        if ($null -ne $Process -and $Process.HasExited -and $null -eq (Get-AvdProcess)) {
            return $null
        }
    } while ((Get-Date) -lt $deadline)
    return $null
}

function Start-AndroidEmulatorProcess {
    param([switch]$ColdBoot)
    $sdkPath = Get-AndroidSdkPath
    $emulatorPath = if ($null -eq $sdkPath) { $null } else { Join-Path $sdkPath 'emulator\emulator.exe' }
    if ($null -eq $emulatorPath -or -not (Test-Path -LiteralPath $emulatorPath)) {
        & flutter emulators --launch $EmulatorId
        if ($LASTEXITCODE -ne 0) { throw "Unable to launch emulator '$EmulatorId'." }
        return $null
    }

    $arguments = @('-avd', $EmulatorId)
    if ($ColdBoot) { $arguments += '-no-snapshot-load' }
    $stderrPath = Join-Path ([System.IO.Path]::GetTempPath()) "nimbleclip-emulator-$PID.err"
    $process = Start-Process -FilePath $emulatorPath -ArgumentList $arguments `
        -PassThru -WindowStyle Hidden -RedirectStandardError $stderrPath
    $process | Add-Member -NotePropertyName NimbleClipStderr -NotePropertyValue $stderrPath
    return $process
}

function Write-EmulatorFailure {
    param([System.Diagnostics.Process]$Process)
    if ($null -eq $Process) { return }
    if ($Process.HasExited) {
        Write-Warning "Android emulator exited early with code $($Process.ExitCode)."
    }
    $stderrPath = $Process.NimbleClipStderr
    if ($null -ne $stderrPath -and (Test-Path -LiteralPath $stderrPath)) {
        $details = Get-Content -LiteralPath $stderrPath -Raw
        if (-not [string]::IsNullOrWhiteSpace($details)) {
            Write-Warning "Android emulator stderr:`n$details"
        }
    }
}

$device = Get-ConnectedAndroidEmulator
if ($null -eq $device) {
    $existingAvd = Get-AvdProcess
    if ($null -ne $existingAvd) {
        Write-Host "Waiting for the existing '$EmulatorId' process..." -ForegroundColor Cyan
        $device = Wait-ForAndroidEmulator `
            -TimeoutSeconds $BootTimeoutSeconds `
            -Process $null
        if ($null -eq $device) { Stop-SelectedAvd }
    }
}

if ($null -eq $device) {
    Write-Host "Starting Android emulator '$EmulatorId'..." -ForegroundColor Cyan
    $emulatorProcess = Start-AndroidEmulatorProcess
    $device = Wait-ForAndroidEmulator -TimeoutSeconds $BootTimeoutSeconds -Process $emulatorProcess

    if ($null -eq $device) {
        Write-EmulatorFailure -Process $emulatorProcess
        Stop-SelectedAvd
        Write-Host 'Retrying once with a cold boot...' -ForegroundColor Yellow
        $emulatorProcess = Start-AndroidEmulatorProcess -ColdBoot
        $device = Wait-ForAndroidEmulator -TimeoutSeconds $BootTimeoutSeconds -Process $emulatorProcess
        if ($null -eq $device) {
            Write-EmulatorFailure -Process $emulatorProcess
            throw "The emulator did not connect after normal and cold-boot attempts."
        }
    }
}

Write-Host "Using $($device.name) [$($device.id)]." -ForegroundColor Green

if ($PrepareOnly) {
    Write-Output $device.id
    return
}

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
