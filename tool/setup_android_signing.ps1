param(
    [string]$Repository = "vannt-dev/nimbleclip",
    [string]$KeytoolPath,
    [switch]$VerifyBuild
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

if ($VerifyBuild) {
    $keyPropertiesFile = Join-Path $repositoryRoot "android\key.properties"
    if (Test-Path -LiteralPath $keyPropertiesFile) {
        throw "$keyPropertiesFile already exists. Refusing to overwrite it for verification."
    }

    try {
        [System.IO.File]::WriteAllLines(
            $keyPropertiesFile,
            @(
                "storePassword=$($credentials['ANDROID_KEYSTORE_PASSWORD'])",
                "keyPassword=$($credentials['ANDROID_KEY_PASSWORD'])",
                "keyAlias=$($credentials['ANDROID_KEY_ALIAS'])",
                "storeFile=$($keystoreFile.Replace('\', '/'))"
            ),
            $utf8NoBom
        )

        Push-Location $repositoryRoot
        try {
            & flutter.bat build apk --release
            if ($LASTEXITCODE -ne 0) {
                throw "Flutter failed to build the signed release APK."
            }
        } finally {
            Pop-Location
        }

        $apkFile = Join-Path $repositoryRoot "build\app\outputs\flutter-apk\app-release.apk"
        $androidSdk = if ($env:ANDROID_HOME) {
            $env:ANDROID_HOME
        } elseif ($env:ANDROID_SDK_ROOT) {
            $env:ANDROID_SDK_ROOT
        } else {
            Join-Path $env:LOCALAPPDATA "Android\Sdk"
        }
        $apkSigner = Get-ChildItem (Join-Path $androidSdk "build-tools") -Filter apksigner.bat -Recurse |
            Sort-Object FullName -Descending |
            Select-Object -First 1 -ExpandProperty FullName
        if (-not $apkSigner) {
            throw "apksigner was not found under $androidSdk."
        }

        $certificate = & $apkSigner verify --print-certs $apkFile
        if ($LASTEXITCODE -ne 0 -or -not $certificate) {
            throw "The release APK signature could not be verified."
        }
        if ($certificate -match "CN=Android Debug") {
            throw "The release APK was signed with the Android debug key."
        }
        Write-Output "Signed release APK verification passed."
    } finally {
        if (Test-Path -LiteralPath $keyPropertiesFile) {
            Remove-Item -LiteralPath $keyPropertiesFile -Force
        }
    }
}

Write-Output "Android signing is configured for $Repository."
Write-Output "Keystore: $keystoreFile"
Write-Output "Recovery credentials: $credentialsFile"
Write-Output "Back up both ignored files securely. Never commit or share them."
