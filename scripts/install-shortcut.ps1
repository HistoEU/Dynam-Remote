param(
  [string]$ShortcutName = "Remote Controller Host",
  [ValidateSet("Desktop", "StartMenu")]
  [string]$Scope = "Desktop",
  [string]$NodePath = "node",
  [string]$HostKey = "dev-host-key",
  [ValidateSet("screen", "fake")]
  [string]$CaptureMode = "screen",
  [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TrayScript = Join-Path $Root "scripts\tray-host.ps1"
$PowerShell = (Get-Command powershell.exe).Source
$Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$TrayScript`" -NodePath `"$NodePath`" -HostKey `"$HostKey`" -CaptureMode $CaptureMode"

function Get-ShortcutDirectory {
  param([string]$SelectedScope)

  if ($SelectedScope -eq "StartMenu") {
    return [Environment]::GetFolderPath("Programs")
  }
  return [Environment]::GetFolderPath("Desktop")
}

function Get-ShortcutPath {
  param(
    [string]$SelectedScope,
    [string]$Name
  )

  $safeName = ($Name -replace '[\\/:*?"<>|]', "-").Trim()
  if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = "Remote Controller Host" }
  return Join-Path (Get-ShortcutDirectory -SelectedScope $SelectedScope) "$safeName.lnk"
}

$ShortcutPath = Get-ShortcutPath -SelectedScope $Scope -Name $ShortcutName

if ($SelfTest) {
  $scriptText = Get-Content -Raw -LiteralPath $PSCommandPath
  $ok = (Test-Path -LiteralPath $TrayScript) -and
    -not [string]::IsNullOrWhiteSpace($PowerShell) -and
    $Arguments -like "*tray-host.ps1*" -and
    $Arguments -like "*-CaptureMode $CaptureMode*" -and
    $scriptText -like "*CreateShortcut*" -and
    $scriptText -like "*WorkingDirectory*" -and
    $scriptText -like "*Save()*"
  [pscustomobject]@{
    ok = $ok
    shortcutPath = $ShortcutPath
    executable = $PowerShell
    arguments = $Arguments
    workingDirectory = "$Root"
    trayScriptExists = (Test-Path -LiteralPath $TrayScript)
    scope = $Scope
  } | ConvertTo-Json -Compress
  if (-not $ok) { exit 1 }
  exit 0
}

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($ShortcutPath)
$shortcut.TargetPath = $PowerShell
$shortcut.Arguments = $Arguments
$shortcut.WorkingDirectory = "$Root"
$shortcut.Description = "Starts the Remote Controller tray host."
$shortcut.IconLocation = "$PowerShell,0"
$shortcut.Save()

[pscustomobject]@{
  ok = $true
  shortcutPath = $ShortcutPath
  executable = $PowerShell
  arguments = $Arguments
  workingDirectory = "$Root"
  scope = $Scope
} | ConvertTo-Json -Compress
