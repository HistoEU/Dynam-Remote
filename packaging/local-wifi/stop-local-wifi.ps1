param(
  [int]$Port = 4317
)

$ErrorActionPreference = "SilentlyContinue"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$DataDir = Join-Path $Root "data"
$PidPath = Join-Path $DataDir "remote-controller.pid"
$PortPath = Join-Path $DataDir "remote-controller.port"

if ((Test-Path -LiteralPath $PortPath) -and -not $PSBoundParameters.ContainsKey("Port")) {
  $portText = (Get-Content -Raw -LiteralPath $PortPath).Trim()
  if ($portText) { $Port = [int]$portText }
}

Write-Host "Stopping Remote Controller..." -ForegroundColor Yellow
if (Test-Path -LiteralPath $PidPath) {
  $pidText = (Get-Content -Raw -LiteralPath $PidPath).Trim()
  if ($pidText) {
    $process = Get-Process -Id ([int]$pidText)
    if ($process) {
      Stop-Process -Id $process.Id -Force
      Write-Host "Stopped packaged host process $pidText." -ForegroundColor Green
    }
  }
  Remove-Item -LiteralPath $PidPath -Force
}

$listeners = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
foreach ($listener in $listeners) {
  if ($listener.OwningProcess) {
    $proc = Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
    if ($proc -and $proc.ProcessName -eq "node") {
      Stop-Process -Id $proc.Id -Force
      Write-Host "Stopped Node host listening on port $Port." -ForegroundColor Green
    }
  }
}

$nodes = @(Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" | Where-Object {
  $_.CommandLine -like "*src/server.js*" -and $_.CommandLine -like "*$Root*"
})
foreach ($node in $nodes) {
  Stop-Process -Id $node.ProcessId -Force
  Write-Host "Stopped host process $($node.ProcessId)." -ForegroundColor Green
}

$helpers = @(Get-CimInstance Win32_Process -Filter "Name = 'electron.exe'" | Where-Object {
  $_.CommandLine -like "*electron-capture-main.js*" -and $_.CommandLine -like "*$Root*"
})
foreach ($helper in $helpers) {
  Stop-Process -Id $helper.ProcessId -Force
  Write-Host "Stopped capture helper $($helper.ProcessId)." -ForegroundColor Green
}

Write-Host "Done."
