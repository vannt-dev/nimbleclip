[CmdletBinding()]
param(
    [string]$InstagramImageUrl,
    [string]$InstagramVideoUrl
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot

$arguments = @(
    'test',
    'test/live_extractor_smoke_test.dart',
    '--dart-define=RUN_LIVE_EXTRACTOR_TESTS=true'
)
if (-not [string]::IsNullOrWhiteSpace($InstagramImageUrl)) {
    $arguments += "--dart-define=INSTAGRAM_IMAGE_URL=$InstagramImageUrl"
}
if (-not [string]::IsNullOrWhiteSpace($InstagramVideoUrl)) {
    $arguments += "--dart-define=INSTAGRAM_VIDEO_URL=$InstagramVideoUrl"
}

& flutter @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Live extractor smoke tests failed ($LASTEXITCODE)."
}
