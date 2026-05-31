param(
  [string]$ZipPath = "",
  [string]$WorkDir = "output\acceptance",
  [int]$Port = 4397
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($ZipPath)) {
  $ZipPath = Join-Path (Join-Path $Root "dist") "RemoteController-LocalWiFi.zip"
}
if (-not [System.IO.Path]::IsPathRooted($ZipPath)) {
  $ZipPath = Join-Path $Root $ZipPath
}
if (-not [System.IO.Path]::IsPathRooted($WorkDir)) {
  $WorkDir = Join-Path $Root $WorkDir
}

function Test-PortOpen {
  param([int]$PortToCheck)
  $client = [System.Net.Sockets.TcpClient]::new()
  try {
    $task = $client.ConnectAsync("127.0.0.1", $PortToCheck)
    if (-not $task.Wait(500)) { return $false }
    return $client.Connected
  } catch {
    return $false
  } finally {
    $client.Dispose()
  }
}

function Invoke-SmokeRequest {
  param([string]$Url)
  Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 2
}

if (-not (Test-Path -LiteralPath $ZipPath)) {
  throw "Package zip not found: $ZipPath. Run npm run package:local-wifi first."
}

$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$RunDir = Join-Path $WorkDir "package-smoke-$Stamp"
$ExtractDir = Join-Path $RunDir "extract"
$StdOut = Join-Path $RunDir "host.out.log"
$StdErr = Join-Path $RunDir "host.err.log"
$Report = Join-Path $RunDir "package-smoke-$Stamp.json"
$LatestReport = Join-Path $WorkDir "package-smoke-latest.json"
New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null

$process = $null
$packageRoot = $null
try {
  Expand-Archive -LiteralPath $ZipPath -DestinationPath $ExtractDir -Force
  $packageRoot = Join-Path $ExtractDir "RemoteController-LocalWiFi"
  if (-not (Test-Path -LiteralPath $packageRoot)) {
    $packageRoot = @(Get-ChildItem -LiteralPath $ExtractDir -Directory | Select-Object -First 1).FullName
  }
  if (-not $packageRoot -or -not (Test-Path -LiteralPath (Join-Path $packageRoot "start-local-wifi.ps1"))) {
    throw "Extracted package does not contain start-local-wifi.ps1."
  }

  $args = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    (Join-Path $packageRoot "start-local-wifi.ps1"),
    "-Port",
    "$Port",
    "-CaptureMode",
    "fake",
    "-NoOpen"
  )

  $process = Start-Process -FilePath "powershell" -ArgumentList $args -WorkingDirectory $packageRoot -RedirectStandardOutput $StdOut -RedirectStandardError $StdErr -WindowStyle Hidden -PassThru

  $health = $null
  $deadline = (Get-Date).AddSeconds(20)
  while ((Get-Date) -lt $deadline) {
    try {
      $response = Invoke-SmokeRequest "http://127.0.0.1:$Port/api/health"
      $health = $response.Content | ConvertFrom-Json
      if ($health.ok -eq $true) { break }
    } catch {
      Start-Sleep -Milliseconds 400
    }
  }
  if (-not $health -or $health.ok -ne $true) {
    throw "Packaged host did not become healthy on 127.0.0.1:$Port."
  }

  $phonePage = Invoke-SmokeRequest "http://127.0.0.1:$Port/"
  if ($phonePage.StatusCode -ne 200 -or $phonePage.Content -notmatch "Remote Controller") {
    throw "Packaged phone page did not render expected content."
  }

  $serviceWorker = Invoke-SmokeRequest "http://127.0.0.1:$Port/sw.js"
  if ($serviceWorker.StatusCode -ne 200 -or $serviceWorker.Content -notmatch "remote-controller") {
    throw "Packaged service worker did not render expected content."
  }

  & (Join-Path $packageRoot "stop-local-wifi.ps1") -Port $Port | Out-Null
  if ($process -and -not $process.HasExited) {
    Wait-Process -Id $process.Id -Timeout 8 -ErrorAction SilentlyContinue
  }
  if (Test-PortOpen $Port) {
    throw "Packaged host port $Port is still listening after stop."
  }

  $result = [pscustomobject]@{
    ok = $true
    zipPath = $ZipPath
    packageRoot = $packageRoot
    report = $Report
    latestReport = $LatestReport
    port = $Port
    healthMode = $health.state.app.mode
    phonePageBytes = $phonePage.RawContentLength
    serviceWorkerBytes = $serviceWorker.RawContentLength
    stdout = $StdOut
    stderr = $StdErr
  }
  $json = $result | ConvertTo-Json -Depth 4
  $json | Set-Content -LiteralPath $Report -Encoding UTF8
  $json | Set-Content -LiteralPath $LatestReport -Encoding UTF8
  Write-Output $json
} finally {
  if ($packageRoot -and (Test-Path -LiteralPath (Join-Path $packageRoot "stop-local-wifi.ps1"))) {
    & (Join-Path $packageRoot "stop-local-wifi.ps1") -Port $Port | Out-Null
  }
  if ($process -and -not $process.HasExited) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
  }
}
