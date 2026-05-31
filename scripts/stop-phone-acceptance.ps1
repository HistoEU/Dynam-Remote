param(
  [ValidateSet("same-wifi", "tailscale")]
  [string]$Gate = "same-wifi",
  [int]$Port = 4317,
  [string]$OutputDir = "output\acceptance",
  [switch]$Force,
  [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$ResolvedOutputDir = Join-Path $Root $OutputDir

function Get-ListeningProcessId {
  $connection = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($connection) { return $connection.OwningProcess }
  return $null
}

function Read-LatestSession {
  $latestPath = Join-Path $ResolvedOutputDir "phone-acceptance-session-$Gate-latest.json"
  if (-not (Test-Path -LiteralPath $latestPath)) { return $null }
  return Get-Content -Raw -LiteralPath $latestPath | ConvertFrom-Json
}

if ($SelfTest) {
  [pscustomobject]@{
    ok = $true
    gate = $Gate
    root = "$Root"
    outputDir = "$ResolvedOutputDir"
    onlyStopsPreparedHostByDefault = $true
  } | ConvertTo-Json -Compress
  exit 0
}

$session = Read-LatestSession
$listeningPid = Get-ListeningProcessId
$stopped = $false
$message = ""

if (-not $session) {
  $message = "No latest phone acceptance session was found for gate '$Gate'."
} elseif (-not $listeningPid) {
  $message = "No process is currently listening on port $Port."
} elseif ($Force -or ($session.startedByPrepare -eq $true -and [int]$session.pid -eq [int]$listeningPid)) {
  Stop-Process -Id $listeningPid -Force -ErrorAction SilentlyContinue
  $stopped = $true
  $message = "Stopped host process $listeningPid."
} else {
  $message = "Refusing to stop process $listeningPid because it was not started by prepare for gate '$Gate'. Use -Force to stop it anyway."
}

[pscustomobject]@{
  ok = $stopped -or (-not $listeningPid)
  gate = $Gate
  stopped = $stopped
  pid = $listeningPid
  sessionFound = $null -ne $session
  message = $message
} | ConvertTo-Json -Compress

if ($listeningPid -and -not $stopped) { exit 1 }
