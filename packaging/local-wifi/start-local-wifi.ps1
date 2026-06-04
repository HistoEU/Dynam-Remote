param(
  [int]$Port = 4317,
  [switch]$NoOpen,
  [switch]$StartOnly
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$DataDir = Join-Path $Root "data"
$OutputDir = Join-Path $Root "output"
$PidPath = Join-Path $DataDir "remote-controller.pid"
$PortPath = Join-Path $DataDir "remote-controller.port"
$HostKeyPath = Join-Path $DataDir "host-key.txt"

New-Item -ItemType Directory -Force -Path $DataDir, $OutputDir | Out-Null

function Write-Step($Message) {
  Write-Host ""
  Write-Host $Message -ForegroundColor Cyan
}

function Get-NodePath {
  $bundled = Join-Path $Root "runtime\node\node.exe"
  if (Test-Path -LiteralPath $bundled) { return $bundled }
  $cmd = Get-Command node -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  throw "Node was not found. This package should include runtime\node\node.exe. Rebuild the zip or install Node.js 20+."
}

function Get-HostKey {
  if (Test-Path -LiteralPath $HostKeyPath) {
    $existing = (Get-Content -Raw -LiteralPath $HostKeyPath).Trim()
    if ($existing) { return $existing }
  }
  $created = [guid]::NewGuid().ToString("N")
  Set-Content -LiteralPath $HostKeyPath -Value $created -Encoding ASCII
  return $created
}

function Invoke-Json($Uri, $Headers = @{}, $Method = "GET") {
  return Invoke-RestMethod -Uri $Uri -Method $Method -Headers $Headers -TimeoutSec 3
}

function Test-Health($CandidatePort) {
  try {
    $health = Invoke-Json "http://127.0.0.1:$CandidatePort/api/health"
    return [bool]$health.ok
  } catch {
    return $false
  }
}

function Test-PortBusy($CandidatePort) {
  $client = New-Object System.Net.Sockets.TcpClient
  try {
    $async = $client.BeginConnect("127.0.0.1", $CandidatePort, $null, $null)
    $busy = $async.AsyncWaitHandle.WaitOne(250, $false)
    if ($busy) { $client.EndConnect($async) | Out-Null }
    return $busy
  } catch {
    return $false
  } finally {
    $client.Close()
  }
}

function Get-LaunchPort($PreferredPort) {
  $candidates = New-Object System.Collections.Generic.List[int]
  foreach ($item in @($PreferredPort, 4317, 4334, 4501, 4502, 4503, 4504, 4505, 4506, 4507, 4508, 4509, 4510)) {
    if (-not $candidates.Contains([int]$item)) { $candidates.Add([int]$item) }
  }
  foreach ($candidate in $candidates) {
    if (Test-Health $candidate) { return $candidate }
    if (-not (Test-PortBusy $candidate)) { return $candidate }
  }
  throw "Could not find a free local port. Close another copy of the controller and try again."
}

function Wait-ForServer($SelectedPort) {
  $deadline = (Get-Date).AddSeconds(35)
  while ((Get-Date) -lt $deadline) {
    if (Test-Health $SelectedPort) { return $true }
    Start-Sleep -Milliseconds 350
  }
  return $false
}

function Get-ServerProcessFromPid {
  if (-not (Test-Path -LiteralPath $PidPath)) { return $null }
  $serverPidText = (Get-Content -Raw -LiteralPath $PidPath).Trim()
  if (-not $serverPidText) { return $null }
  return Get-Process -Id ([int]$serverPidText) -ErrorAction SilentlyContinue
}

function Show-Ready($SelectedPort, $HostKey) {
  $headers = @{ "x-host-key" = $HostKey }
  $pin = Invoke-Json "http://127.0.0.1:$SelectedPort/api/refresh-pin" $headers "POST"
  $state = Invoke-Json "http://127.0.0.1:$SelectedPort/api/host?key=$HostKey"
  $phoneUrl = ""
  foreach ($address in @($state.addresses)) {
    if ($address.kind -eq "lan") {
      $phoneUrl = $address.url
      break
    }
  }
  if (-not $phoneUrl) { $phoneUrl = "http://127.0.0.1:$SelectedPort" }
  $hostUrl = "http://127.0.0.1:$SelectedPort/host?key=$HostKey"

  Write-Host ""
  Write-Host "Dynam Remote is running." -ForegroundColor Green
  Write-Host ""
  Write-Host "Open this on the PHONE:" -ForegroundColor Yellow
  Write-Host "  $phoneUrl" -ForegroundColor White
  Write-Host ""
  Write-Host "PIN:" -ForegroundColor Yellow
  Write-Host "  $($pin.pin)  (valid for about $($pin.secondsRemaining) seconds)" -ForegroundColor White
  Write-Host ""
  Write-Host "Laptop host page:" -ForegroundColor DarkGray
  Write-Host "  $hostUrl" -ForegroundColor DarkGray
  Write-Host ""
  Write-Host "If Windows Firewall asks, choose Allow on private networks." -ForegroundColor Yellow
  Write-Host "Leave this window open while testing. Use Stop Remote Controller.bat when finished." -ForegroundColor DarkGray

  if (-not $NoOpen) {
    Start-Process $hostUrl | Out-Null
  }

  return [pscustomobject]@{
    ok = $true
    port = $SelectedPort
    phoneUrl = $phoneUrl
    hostUrl = $hostUrl
    pin = $pin.pin
    secondsRemaining = $pin.secondsRemaining
    verifiedDisplays = @($state.capturePool.slots | Where-Object { $_.status -eq "verified" -and $_.usable }).Count
  }
}

$nodePath = Get-NodePath
$hostKey = Get-HostKey
$selectedPort = Get-LaunchPort $Port
$existing = Get-ServerProcessFromPid

if ($existing -and (Test-Health $selectedPort)) {
  Write-Step "Remote Controller is already running. Reusing it."
  $ready = Show-Ready $selectedPort $hostKey
  if ($StartOnly) { $ready | ConvertTo-Json -Depth 4; return }
  while (-not $existing.HasExited) { Start-Sleep -Seconds 1; $existing.Refresh() }
  return
}

Write-Step "Starting Dynam Remote on local port $selectedPort..."

$stdoutPath = Join-Path $OutputDir "remote-controller.out.log"
$stderrPath = Join-Path $OutputDir "remote-controller.err.log"
Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue

$env:HOST_KEY = $hostKey
$env:PORT = "$selectedPort"
$env:CAPTURE_MODE = "screen"
$env:REAL_INPUT = "1"
$env:QUALITY_DEFAULT = "fast"
$env:RTC_CAPTURE_AUTOSTART = "1"
$env:RTC_CAPTURE_ENGINE = "electron"

$process = Start-Process -FilePath $nodePath `
  -ArgumentList "src/server.js" `
  -WorkingDirectory $Root `
  -WindowStyle Hidden `
  -PassThru

Set-Content -LiteralPath $PidPath -Value $process.Id -Encoding ASCII
Set-Content -LiteralPath $PortPath -Value $selectedPort -Encoding ASCII

if (-not (Wait-ForServer $selectedPort)) {
  Write-Host "The controller did not finish starting." -ForegroundColor Red
  Write-Host "If this repeats, restart the laptop or try another extracted copy of the zip."
  exit 1
}

$ready = Show-Ready $selectedPort $hostKey
if ($StartOnly) {
  $ready | ConvertTo-Json -Depth 4
  return
}

while (-not $process.HasExited) {
  Start-Sleep -Seconds 1
  $process.Refresh()
}

Write-Host ""
Write-Host "Dynam Remote stopped. If this was not expected, check:" -ForegroundColor Yellow
Write-Host "  $stderrPath"
