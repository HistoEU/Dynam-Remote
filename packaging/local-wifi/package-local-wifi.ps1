param(
  [string]$OutputDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "dist"),
  [string]$PackageName = "RemoteController-LocalWiFi"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Staging = Join-Path $OutputDir $PackageName
$ZipPath = Join-Path $OutputDir "$PackageName.zip"

if (Test-Path -LiteralPath $Staging) { Remove-Item -LiteralPath $Staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Staging | Out-Null
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$copyDirs = @("public", "src")
foreach ($dir in $copyDirs) {
  Copy-Item -LiteralPath (Join-Path $Root $dir) -Destination (Join-Path $Staging $dir) -Recurse -Force
}

Copy-Item -LiteralPath (Join-Path $Root "package-lock.json") -Destination (Join-Path $Staging "package-lock.json") -Force
$packageFiles = @(
  "Start Remote Controller.bat",
  "Stop Remote Controller.bat",
  "OpenHostLink.bat",
  "README-FIRST.txt",
  "QUICK-START-DAD.txt",
  "START-HERE-FRESH-INSTALL.txt",
  "start-local-wifi.ps1",
  "stop-local-wifi.ps1",
  "smoke-local-wifi.ps1"
)

foreach ($file in $packageFiles) {
  $source = Join-Path $PSScriptRoot $file
  if (-not (Test-Path -LiteralPath $source)) {
    throw "Packaging file missing: $source"
  }
  Copy-Item -LiteralPath $source -Destination $Staging -Force
}

$rootPackage = Get-Content -Raw -LiteralPath (Join-Path $Root "package.json") | ConvertFrom-Json
$packageManifest = [ordered]@{
  name = "remote-controller-local-wifi"
  version = "$($rootPackage.version)"
  private = $true
  description = "Local Wi-Fi phone-to-laptop remote desktop controller package."
  type = "commonjs"
  scripts = [ordered]@{
    start = "powershell -NoProfile -ExecutionPolicy Bypass -File ./start-local-wifi.ps1"
    stop = "powershell -NoProfile -ExecutionPolicy Bypass -File ./stop-local-wifi.ps1"
    smoke = "powershell -NoProfile -ExecutionPolicy Bypass -File ./smoke-local-wifi.ps1"
  }
  engines = [ordered]@{
    node = ">=20"
  }
  dependencies = $rootPackage.dependencies
}
$packageManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Staging "package.json") -Encoding UTF8

Push-Location $Staging
try {
  $npm = Get-Command "npm.cmd" -ErrorAction SilentlyContinue
  if (-not $npm) { $npm = Get-Command "npm" -ErrorAction Stop }
  & $npm.Source ci --omit=dev
} finally {
  Pop-Location
}

if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
Compress-Archive -LiteralPath $Staging -DestinationPath $ZipPath -Force

$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $ZipPath
[pscustomobject]@{
  ok = $true
  zipPath = $ZipPath
  stagingPath = $Staging
  sha256 = $hash.Hash
  sizeMB = [math]::Round((Get-Item -LiteralPath $ZipPath).Length / 1MB, 2)
} | ConvertTo-Json -Depth 4
