param(
  [string]$TaskName = "RemoteControllerHost",
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

if ($SelfTest) {
  [pscustomobject]@{
    ok = $true
    taskName = $TaskName
    executable = $PowerShell
    arguments = $Arguments
    workingDirectory = "$Root"
  } | ConvertTo-Json -Compress
  exit 0
}

$action = New-ScheduledTaskAction -Execute $PowerShell -Argument $Arguments -WorkingDirectory "$Root"
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Description "Starts the Remote Controller tray host at login." -Force | Out-Null

[pscustomobject]@{
  ok = $true
  taskName = $TaskName
  installed = $true
} | ConvertTo-Json -Compress
