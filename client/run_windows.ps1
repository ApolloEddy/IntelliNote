param(
    [string]$Device = "windows",
    [switch]$SkipPubGet
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

# Network/proxy settings for Flutter & Dart pub in Gsou Cloud environments.
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
$env:HTTP_PROXY = "http://127.0.0.1:26001"
$env:HTTPS_PROXY = "http://127.0.0.1:26001"
$env:ALL_PROXY = "http://127.0.0.1:26001"
$env:NO_PROXY = "localhost,127.0.0.1"

Write-Host "[run_windows] Working dir: $scriptDir"
Write-Host "[run_windows] Device: $Device"
Write-Host "[run_windows] PUB_HOSTED_URL: $env:PUB_HOSTED_URL"

if (-not $SkipPubGet) {
    Write-Host "[run_windows] Running flutter pub get..."
    flutter pub get
}

Write-Host "[run_windows] Running flutter run -d $Device ..."
flutter run -d $Device
