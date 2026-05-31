param(
  [int]$Port = 4317,
  [ValidateSet("screen", "fake")]
  [string]$CaptureMode = "screen",
  [switch]$NoOpen
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$DataDir = Join-Path $Root "data"

function Fail-Start {
  param([string]$Message)
  Write-Host ""
  Write-Host $Message -ForegroundColor Red
  Write-Host ""
  Write-Host "Fix this, then run Start Remote Controller.bat again." -ForegroundColor Yellow
  exit 1
}

Push-Location $Root
try {
  $node = Get-Command "node" -ErrorAction SilentlyContinue
  if (-not $node) {
    Fail-Start "Node.js 20 or newer is required. Install it from https://nodejs.org/ first."
  }

  $majorText = (& node -e "process.stdout.write(process.versions.node.split('.')[0])")
  $major = 0
  [void][int]::TryParse($majorText, [ref]$major)
  if ($major -lt 20) {
    Fail-Start "Node.js 20 or newer is required. Current major version: $majorText."
  }

  if (-not (Test-Path -LiteralPath (Join-Path $Root "src\server.js"))) {
    Fail-Start "The package is incomplete: src\server.js is missing."
  }

  if (-not (Test-Path -LiteralPath (Join-Path $Root "node_modules\qrcode"))) {
    Fail-Start "The package is missing dependencies. Rebuild the zip with npm run package:local-wifi."
  }

  New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

  $env:PORT = "$Port"
  $env:HOST = "0.0.0.0"
  $env:CAPTURE_MODE = $CaptureMode
  $env:REAL_INPUT = "1"
  $env:QUALITY_DEFAULT = "fast"

  Write-Host "Remote Controller - Local Wi-Fi" -ForegroundColor Cyan
  Write-Host "This free local mode does not require an account or paid service."
  Write-Host "Laptop and phone must be on the same Wi-Fi."
  Write-Host ""
  Write-Host "When the server prints LAN URLs, paste one on your phone."
  Write-Host "Approve the phone from the host console before control is allowed."
  Write-Host "Use Stop Remote Controller.bat when finished."
  Write-Host ""

  & node src\server.js
} finally {
  Pop-Location
}
