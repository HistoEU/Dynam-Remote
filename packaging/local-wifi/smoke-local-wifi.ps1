param(
  [string]$ZipPath = "",
  [string]$WorkDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "output\package-smoke"),
  [int]$Port = 4597
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $ZipPath) {
  $ZipPath = Join-Path $Root "dist\DynamRemote-Brother-Test.zip"
}

if (-not (Test-Path -LiteralPath $ZipPath)) {
  throw "Zip not found: $ZipPath"
}

if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
Expand-Archive -LiteralPath $ZipPath -DestinationPath $WorkDir -Force

$packageRoot = Get-ChildItem -LiteralPath $WorkDir -Directory | Select-Object -First 1
if (-not $packageRoot) { throw "Extracted package folder was not found." }

$startScript = Join-Path $packageRoot.FullName "start-local-wifi.ps1"
$stopScript = Join-Path $packageRoot.FullName "stop-local-wifi.ps1"
if (-not (Test-Path -LiteralPath $startScript)) { throw "Missing start-local-wifi.ps1." }
if (-not (Test-Path -LiteralPath $stopScript)) { throw "Missing stop-local-wifi.ps1." }

$started = $null
try {
  $raw = powershell -NoProfile -ExecutionPolicy Bypass -File $startScript -Port $Port -NoOpen -StartOnly
  $jsonText = ($raw | Where-Object { "$_".Trim().StartsWith("{") -or "$_".Trim().StartsWith('"') -or "$_".Trim().StartsWith("}") -or "$_".Trim().Contains(":") }) -join "`n"
  $started = $raw -join "`n"
  $hostKey = (Get-Content -Raw -LiteralPath (Join-Path $packageRoot.FullName "data\host-key.txt")).Trim()
  $health = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/api/health" -TimeoutSec 5
  $hostState = $null
  $verifiedDisplays = 0
  $monitorCount = 0
  $deadline = (Get-Date).AddSeconds(45)
  while ((Get-Date) -lt $deadline) {
    $hostState = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/api/host?key=$hostKey" -TimeoutSec 5
    $monitorCount = @($hostState.monitors).Count
    $verifiedDisplays = @($hostState.capturePool.slots | Where-Object { $_.status -eq "verified" -and $_.usable }).Count
    if ($monitorCount -gt 0 -and $verifiedDisplays -ge $monitorCount) { break }
    Start-Sleep -Seconds 1
  }
  $phone = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -UseBasicParsing -TimeoutSec 5

  $result = [pscustomobject]@{
    ok = $true
    zipPath = $ZipPath
    packageRoot = $packageRoot.FullName
    port = $Port
    healthOk = [bool]$health.ok
    phonePageOk = ($phone.StatusCode -eq 200)
    hostMode = $hostState.app.mode
    phoneAppVersion = $hostState.app.phoneAppVersion
    monitorCount = $monitorCount
    verifiedDisplays = $verifiedDisplays
    captureReady = ($monitorCount -gt 0 -and $verifiedDisplays -ge $monitorCount)
    startOutput = $started
  }
  if (-not $result.captureReady) {
    throw "Package launched, but high-quality capture did not verify all displays in time. verified=$verifiedDisplays monitors=$monitorCount"
  }
  $result | ConvertTo-Json -Depth 6
} finally {
  powershell -NoProfile -ExecutionPolicy Bypass -File $stopScript -Port $Port | Out-Null
}
