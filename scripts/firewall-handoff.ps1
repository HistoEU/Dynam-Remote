param(
  [ValidateSet("install", "remove")]
  [string]$Action = "install",
  [string]$OutputDir = "output\acceptance",
  [switch]$NoOpen,
  [switch]$NoClipboard,
  [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$ResolvedOutputDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $Root $OutputDir }
$FirewallRule = Join-Path $PSScriptRoot "firewall-rule.ps1"

function Invoke-FirewallStatus {
  try {
    $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $FirewallRule -Action status 2>&1
    $jsonLine = @($raw | Where-Object { "$_".Trim().StartsWith("{") }) | Select-Object -Last 1
    if ($jsonLine) { return $jsonLine | ConvertFrom-Json }
  } catch {
    return [pscustomobject]@{
      ready = $false
      error = $_.Exception.Message
    }
  }
  return [pscustomobject]@{
    ready = $false
    error = "Firewall status did not return JSON."
  }
}

function ConvertTo-MarkdownText {
  param([string]$Text)
  return "$Text".Replace("`r", " ").Replace("`n", " ")
}

function New-FirewallHandoff {
  param([string]$SelectedAction)

  New-Item -ItemType Directory -Path $ResolvedOutputDir -Force | Out-Null
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $jsonPath = Join-Path $ResolvedOutputDir "firewall-handoff-$SelectedAction-$timestamp.json"
  $mdPath = Join-Path $ResolvedOutputDir "firewall-handoff-$SelectedAction-$timestamp.md"
  $scriptPath = Join-Path $ResolvedOutputDir "firewall-handoff-$SelectedAction-$timestamp.ps1"
  $latestJsonPath = Join-Path $ResolvedOutputDir "firewall-handoff-$SelectedAction-latest.json"
  $latestMdPath = Join-Path $ResolvedOutputDir "firewall-handoff-$SelectedAction-latest.md"
  $latestScriptPath = Join-Path $ResolvedOutputDir "firewall-handoff-$SelectedAction-latest.ps1"
  $status = Invoke-FirewallStatus
  $command = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$FirewallRule`" -Action $SelectedAction"

  @"
Set-Location -LiteralPath "$Root"
& powershell -NoProfile -ExecutionPolicy Bypass -File "$FirewallRule" -Action $SelectedAction
Write-Host ""
Write-Host "Firewall $SelectedAction finished. Close this elevated window after reviewing the result."
Read-Host "Press Enter to close"
"@ | Set-Content -LiteralPath $scriptPath -Encoding UTF8
  Copy-Item -LiteralPath $scriptPath -Destination $latestScriptPath -Force

  $handoff = [pscustomobject]@{
    ok = $true
    generatedAt = (Get-Date).ToString("o")
    action = $SelectedAction
    mutatesFirewall = $false
    elevatedScriptWouldMutateFirewall = $true
    requiresElevation = $true
    outputDir = "$ResolvedOutputDir"
    firewallStatus = $status
    command = $command
    elevatedScriptPath = $scriptPath
    latestElevatedScriptPath = $latestScriptPath
    jsonPath = $jsonPath
    markdownPath = $mdPath
    latestJsonPath = $latestJsonPath
    latestMarkdownPath = $latestMdPath
    doesNotInstallFirewall = $true
    doesNotRemoveFirewall = $true
    doesNotMarkPhysicalGate = $true
  }

  $handoff | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  $handoff | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $latestJsonPath -Encoding UTF8

  $markdown = @"
# Firewall Handoff

Generated: $($handoff.generatedAt)
Action: $($handoff.action)
Firewall ready now: $($status.ready)
Requires elevation: $($handoff.requiresElevation)

This handoff writes the exact elevated command for the optional inbound TCP `4317` firewall rule. It does not install or remove the rule, does not run the physical phone checklist, and does not mark any physical gate complete.

## Command

~~~powershell
$command
~~~

## Elevated Script

$scriptPath

## Current Firewall Status

~~~json
$($status | ConvertTo-Json -Depth 8)
~~~

## Reminder

Run this only if the phone cannot reach the laptop over same-Wi-Fi or Tailscale and you are comfortable approving the Windows elevation prompt.
"@
  $markdown | Set-Content -LiteralPath $mdPath -Encoding UTF8
  $markdown | Set-Content -LiteralPath $latestMdPath -Encoding UTF8

  $opened = @()
  $openError = ""
  if (-not $NoOpen) {
    try {
      Start-Process -FilePath "explorer.exe" -ArgumentList @($mdPath) | Out-Null
      $opened = @($mdPath)
    } catch {
      $openError = $_.Exception.Message
    }
  }

  $clipboardCopied = $false
  $clipboardError = ""
  if (-not $NoClipboard) {
    try {
      Set-Clipboard -Value $command
      $clipboardCopied = $true
    } catch {
      $clipboardError = $_.Exception.Message
    }
  }

  $handoff | Add-Member -NotePropertyName openedPaths -NotePropertyValue $opened -Force
  $handoff | Add-Member -NotePropertyName openSkipped -NotePropertyValue ([bool]$NoOpen) -Force
  $handoff | Add-Member -NotePropertyName openError -NotePropertyValue $openError -Force
  $handoff | Add-Member -NotePropertyName clipboardCopied -NotePropertyValue $clipboardCopied -Force
  $handoff | Add-Member -NotePropertyName clipboardSkipped -NotePropertyValue ([bool]$NoClipboard) -Force
  $handoff | Add-Member -NotePropertyName clipboardError -NotePropertyValue $clipboardError -Force
  $handoff | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  $handoff | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $latestJsonPath -Encoding UTF8

  return $handoff
}

if ($SelfTest) {
  $tempOutput = Join-Path ([System.IO.Path]::GetTempPath()) "remote-firewall-handoff-$([guid]::NewGuid().ToString('N'))"
  $oldOutput = $script:ResolvedOutputDir
  $script:ResolvedOutputDir = $tempOutput
  try {
    $handoff = New-FirewallHandoff -SelectedAction "install"
    $markdown = Get-Content -Raw -LiteralPath $handoff.markdownPath
    $scriptText = Get-Content -Raw -LiteralPath $PSCommandPath
    $ok = $handoff.ok -and
      $handoff.mutatesFirewall -eq $false -and
      $handoff.elevatedScriptWouldMutateFirewall -eq $true -and
      $handoff.doesNotInstallFirewall -eq $true -and
      $handoff.doesNotMarkPhysicalGate -eq $true -and
      (Test-Path -LiteralPath $handoff.elevatedScriptPath) -and
      (Test-Path -LiteralPath $handoff.latestElevatedScriptPath) -and
      "$($handoff.command)" -like "*firewall-rule.ps1*" -and
      "$($handoff.command)" -like "*-Action install*" -and
      $markdown -match "does not install or remove the rule" -and
      $scriptText -like "*Set-Clipboard*" -and
      $scriptText -like "*explorer.exe*"
    [pscustomobject]@{
      ok = $ok
      action = $handoff.action
      mutatesFirewall = $handoff.mutatesFirewall
      elevatedScriptWouldMutateFirewall = $handoff.elevatedScriptWouldMutateFirewall
      writesJsonMarkdownAndScript = (Test-Path -LiteralPath $handoff.jsonPath) -and (Test-Path -LiteralPath $handoff.markdownPath) -and (Test-Path -LiteralPath $handoff.elevatedScriptPath)
    } | ConvertTo-Json -Compress
    if (-not $ok) { exit 1 }
    exit 0
  } finally {
    $script:ResolvedOutputDir = $oldOutput
  }
}

$result = New-FirewallHandoff -SelectedAction $Action
$result | ConvertTo-Json -Depth 8 -Compress
