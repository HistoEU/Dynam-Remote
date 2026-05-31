param(
  [string]$NodePath = "node",
  [string]$HostKey = "dev-host-key",
  [int]$Port = 4317,
  [ValidateSet("screen", "fake")]
  [string]$CaptureMode = "screen",
  [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$BaseUrl = "http://127.0.0.1:$Port"
$HostUrl = "$BaseUrl/host?key=$([uri]::EscapeDataString($HostKey))"
$script:HostProcess = $null

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Get-ListeningProcessId {
  $connection = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($connection) { return $connection.OwningProcess }
  return $null
}

function Get-HostState {
  try {
    return Invoke-RestMethod -Uri "$BaseUrl/api/host?key=$([uri]::EscapeDataString($HostKey))" -TimeoutSec 2
  } catch {
    return $null
  }
}

function Invoke-HostAction([string]$Path, [string]$Body = "{}") {
  Invoke-RestMethod -Method Post -Uri "$BaseUrl$Path" -Headers @{
    "x-host-key" = $HostKey
    "content-type" = "application/json"
  } -Body $Body -TimeoutSec 4 | Out-Null
}

function Test-VpnLikeAddress {
  param([object]$Address)

  $name = "$($Address.name)"
  return $name -match "(?i)(vpn|nord|lynx|wireguard|zerotier|hamachi|tap|tun|wg)"
}

function Get-PhoneUrlSelection {
  param([object]$State)

  $addresses = if ($State -and $State.addresses) { @($State.addresses) } else { @() }
  $lan = @($addresses | Where-Object { $_.kind -eq "lan" })
  $recommendedLan = @($lan | Where-Object { -not (Test-VpnLikeAddress -Address $_) })
  if ($recommendedLan.Count -eq 0 -and $lan.Count -gt 0) {
    $recommendedLan = $lan
  }
  $tailscale = @($addresses | Where-Object { $_.kind -eq "tailscale" })

  return [pscustomobject]@{
    recommended = @($recommendedLan | ForEach-Object { $_.url })
    tailscale = @($tailscale | ForEach-Object { $_.url })
    all = @($addresses | ForEach-Object { $_.url })
  }
}

function Start-RemoteHost {
  $existing = Get-ListeningProcessId
  if ($existing) { return $existing }

  $environment = @{
    HOST_KEY = $HostKey
    CAPTURE_MODE = $CaptureMode
  }

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $NodePath
  $psi.Arguments = "src\server.js"
  $psi.WorkingDirectory = $Root
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  foreach ($key in $environment.Keys) {
    $psi.Environment[$key] = $environment[$key]
  }

  $script:HostProcess = [System.Diagnostics.Process]::Start($psi)
  Start-Sleep -Milliseconds 900
  return $script:HostProcess.Id
}

function Stop-RemoteHost {
  $pid = Get-ListeningProcessId
  if ($pid) {
    Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
  }
  if ($script:HostProcess -and -not $script:HostProcess.HasExited) {
    Stop-Process -Id $script:HostProcess.Id -Force -ErrorAction SilentlyContinue
  }
}

function Copy-RecommendedPhoneUrls {
  $state = Get-HostState
  if (-not $state) { return "Host is not running." }
  $selection = Get-PhoneUrlSelection -State $state
  $urls = @($selection.recommended)
  if (-not $urls.Count) { return "No recommended phone URLs found." }
  [System.Windows.Forms.Clipboard]::SetText(($urls -join [Environment]::NewLine))
  return "Copied $($urls.Count) recommended phone URL(s)."
}

function Copy-AllPhoneUrls {
  $state = Get-HostState
  if (-not $state) { return "Host is not running." }
  $selection = Get-PhoneUrlSelection -State $state
  $urls = @($selection.all)
  if (-not $urls.Count) { return "No phone URLs found." }
  [System.Windows.Forms.Clipboard]::SetText(($urls -join [Environment]::NewLine))
  return "Copied all $($urls.Count) phone URL(s)."
}

if ($SelfTest) {
  [pscustomobject]@{
    ok = $true
    root = "$Root"
    hostUrl = $HostUrl
    captureMode = $CaptureMode
    port = $Port
    selectsRecommendedPhoneUrls = $true
  } | ConvertTo-Json -Compress
  exit 0
}

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = [System.Drawing.SystemIcons]::Application
$notify.Text = "Remote Controller Host"
$notify.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$statusItem = $menu.Items.Add("Starting...")
$statusItem.Enabled = $false
$menu.Items.Add("-") | Out-Null
$openItem = $menu.Items.Add("Open Host Console")
$copyRecommendedItem = $menu.Items.Add("Copy Recommended Phone URLs")
$copyAllItem = $menu.Items.Add("Copy All Phone URLs")
$startItem = $menu.Items.Add("Start Host")
$stopItem = $menu.Items.Add("Stop Host")
$menu.Items.Add("-") | Out-Null
$releaseItem = $menu.Items.Add("Release Buttons")
$dryRunItem = $menu.Items.Add("Set Input Dry-Run")
$realInputItem = $menu.Items.Add("Enable Real Input")
$killItem = $menu.Items.Add("Stop All Control")
$menu.Items.Add("-") | Out-Null
$exitItem = $menu.Items.Add("Exit Tray")
$notify.ContextMenuStrip = $menu

function Show-Balloon([string]$Title, [string]$Text) {
  $notify.BalloonTipTitle = $Title
  $notify.BalloonTipText = $Text
  $notify.ShowBalloonTip(1800)
}

function Refresh-Menu {
  $state = Get-HostState
  if ($state) {
    $mode = $state.inputSafety.mode
    $sessions = @($state.sessions).Count
    $statusItem.Text = "Running - $mode - $sessions session(s)"
    $startItem.Enabled = $false
    $stopItem.Enabled = $true
    $openItem.Enabled = $true
    $copyRecommendedItem.Enabled = $true
    $copyAllItem.Enabled = $true
    $releaseItem.Enabled = $true
    $dryRunItem.Enabled = $true
    $realInputItem.Enabled = $true
    $killItem.Enabled = $true
  } else {
    $statusItem.Text = "Stopped"
    $startItem.Enabled = $true
    $stopItem.Enabled = $false
    $openItem.Enabled = $false
    $copyRecommendedItem.Enabled = $false
    $copyAllItem.Enabled = $false
    $releaseItem.Enabled = $false
    $dryRunItem.Enabled = $false
    $realInputItem.Enabled = $false
    $killItem.Enabled = $false
  }
}

$openItem.add_Click({ Start-Process $HostUrl })
$copyRecommendedItem.add_Click({
  $message = Copy-RecommendedPhoneUrls
  Show-Balloon "Remote Controller Host" $message
})
$copyAllItem.add_Click({
  $message = Copy-AllPhoneUrls
  Show-Balloon "Remote Controller Host" $message
})
$startItem.add_Click({
  Start-RemoteHost | Out-Null
  Refresh-Menu
  Show-Balloon "Remote Controller Host" "Host started."
})
$stopItem.add_Click({
  Stop-RemoteHost
  Refresh-Menu
  Show-Balloon "Remote Controller Host" "Host stopped."
})
$releaseItem.add_Click({
  Invoke-HostAction "/api/safety-release"
  Show-Balloon "Remote Controller Host" "Held input released."
})
$dryRunItem.add_Click({
  Invoke-HostAction "/api/input-mode" '{"enabled":false}'
  Refresh-Menu
  Show-Balloon "Remote Controller Host" "Input set to dry-run."
})
$realInputItem.add_Click({
  Invoke-HostAction "/api/input-mode" '{"enabled":true}'
  Refresh-Menu
  Show-Balloon "Remote Controller Host" "Real input enabled."
})
$killItem.add_Click({
  Invoke-HostAction "/api/kill-switch"
  Refresh-Menu
  Show-Balloon "Remote Controller Host" "All control stopped."
})
$exitItem.add_Click({
  $notify.Visible = $false
  $notify.Dispose()
  [System.Windows.Forms.Application]::Exit()
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1500
$timer.add_Tick({ Refresh-Menu })
$timer.Start()

Start-RemoteHost | Out-Null
Refresh-Menu
Show-Balloon "Remote Controller Host" "Host is ready. Open the tray menu for URLs and safety controls."
[System.Windows.Forms.Application]::Run()
