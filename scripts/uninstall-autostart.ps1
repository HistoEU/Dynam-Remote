param(
  [string]$TaskName = "RemoteControllerHost",
  [switch]$SelfTest
)

$ErrorActionPreference = "Stop"

if ($SelfTest) {
  [pscustomobject]@{
    ok = $true
    taskName = $TaskName
    action = "unregister"
  } | ConvertTo-Json -Compress
  exit 0
}

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task) {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

[pscustomobject]@{
  ok = $true
  taskName = $TaskName
  installed = $false
} | ConvertTo-Json -Compress
