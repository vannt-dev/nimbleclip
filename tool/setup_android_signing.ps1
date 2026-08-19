param(
    [string]$Repository = "vannt-dev/nimbleclip",
    [string]$KeytoolPath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function New-SecureToken {
    param([int]$Length = 48)

    $alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    $bytes = New-Object byte[] ($Length * 2)
    $builder = [System.Text.StringBuilder]::new($Length)
    $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    try {
        while ($builder.Length -lt $Length) {
            $generator.GetBytes($bytes)
            foreach ($value in $bytes) {
                if ($value -lt 248) {
                    [void]$builder.Append($alphabet[$value % $alphabet.Length])
                    if ($builder.Length -eq $Length) {
                        break
                    }
                }
            }
        }
    } finally {
        $generator.Dispose()
    }

    return $builder.ToString()
}

function Find-Keytool {
    if ($KeytoolPath) {
        return (Resolve-Path -LiteralPath $KeytoolPath).Path
    }

    $command = Get-Command keytool -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidates = @()
    if ($env:JAVA_HOME) {
        $candidates += Join-Path $env:JAVA_HOME "bin\keytool.exe"
    }
    $candidates += "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe"
    $candidates += Get-ChildItem "C:\Program Files\Java" -Filter keytool.exe -Recurse -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -ExpandProperty FullName

    $match = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $match) {
        throw "keytool was not found. Install a JDK or pass -KeytoolPath."
    }
    return $match
}

function Set-RepositorySecret {
    param(
        [string]$Name,
        [string]$Value
    )

    $Value | & gh secret set $Name --repo $Repository
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set GitHub Actions secret $Name."
    }
}

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$releaseDirectory = Join-Path $repositoryRoot "dist\release"
$keystoreFile = Join-Path $releaseDirectory "nimbleclip-upload.jks"
$credentialsFile = Join-Path $releaseDirectory "android-signing.env"
$alias = "nimbleclip-upload"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

New-Item -ItemType Directory -Path $releaseDirectory -Force | Out-Null

if ((Test-Path -LiteralPath $keystoreFile) -xor (Test-Path -LiteralPath $credentialsFile)) {
    throw "Signing files are incomplete. Restore both files or remove the partial file before retrying."
}

if (-not (Test-Path -LiteralPath $keystoreFile)) {
    $password = New-SecureToken
    $resolvedKeytool = Find-Keytool

    & $resolvedKeytool `
        -genkeypair `
        -v `
        -keystore $keystoreFile `
        -storetype JKS `
        -storepass $password `
        -keypass $password `
        -alias $alias `
        -keyalg RSA `
        -keysize 4096 `
        -validity 10000 `
        -dname "CN=NimbleClip, OU=Mobile, O=vannt-dev"
    if ($LASTEXITCODE -ne 0) {
        throw "keytool failed to generate the Android upload keystore."
    }

    [System.IO.File]::WriteAllLines(
        $credentialsFile,
        @(
            "ANDROID_KEYSTORE_PASSWORD=$password",
            "ANDROID_KEY_PASSWORD=$password",
            "ANDROID_KEY_ALIAS=$alias"
        ),
        $utf8NoBom
    )
}

$credentials = @{}
foreach ($line in [System.IO.File]::ReadAllLines($credentialsFile)) {
    if ($line -and -not $line.StartsWith("#")) {
        $name, $value = $line.Split("=", 2)
        $credentials[$name] = $value
    }
}

foreach ($requiredName in @(
    "ANDROID_KEYSTORE_PASSWORD",
    "ANDROID_KEY_PASSWORD",
    "ANDROID_KEY_ALIAS"
)) {
    if (-not $credentials.ContainsKey($requiredName) -or -not $credentials[$requiredName]) {
        throw "$credentialsFile does not contain $requiredName."
    }
}

$keystoreBase64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($keystoreFile))
Set-RepositorySecret "ANDROID_KEYSTORE_BASE64" $keystoreBase64
Set-RepositorySecret "ANDROID_KEYSTORE_PASSWORD" $credentials["ANDROID_KEYSTORE_PASSWORD"]
Set-RepositorySecret "ANDROID_KEY_PASSWORD" $credentials["ANDROID_KEY_PASSWORD"]
Set-RepositorySecret "ANDROID_KEY_ALIAS" $credentials["ANDROID_KEY_ALIAS"]

Write-Output "Android signing is configured for $Repository."
Write-Output "Keystore: $keystoreFile"
Write-Output "Recovery credentials: $credentialsFile"
Write-Output "Back up both ignored files securely. Never commit or share them."
