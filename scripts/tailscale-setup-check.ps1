param(
  [string]$HostKey = "dev-host-key",
  [int]$Port = 4317,
  [string]$OutputDir = "output\acceptance",
  [switch]$Save,
  [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$ResolvedOutputDir = Join-Path $Root $OutputDir
$FirewallRule = Join-Path $PSScriptRoot "firewall-rule.ps1"

function Resolve-TailscaleCommand {
  $command = Get-Command tailscale -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($command) { return $command.Source }

  $candidates = @(
    "C:\Program Files\Tailscale\tailscale.exe",
    "C:\Program Files (x86)\Tailscale\tailscale.exe"
  )
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) { return $candidate }
  }
  return ""
}

function Invoke-Tailscale {
  param(
    [string]$CommandPath,
    [string[]]$Arguments
  )

  if (-not $CommandPath) {
    return [pscustomobject]@{
      ok = $false
      exitCode = -1
      output = @()
      error = "tailscale CLI was not found."
    }
  }

  try {
    $output = & $CommandPath @Arguments 2>&1
    return [pscustomobject]@{
      ok = $LASTEXITCODE -eq 0
      exitCode = $LASTEXITCODE
      output = @($output | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
      error = ""
    }
  } catch {
    return [pscustomobject]@{
      ok = $false
      exitCode = -1
      output = @()
      error = $_.Exception.Message
    }
  }
}

function Get-TailscaleStatusSnapshot {
  param([object]$StatusResult)

  $snapshot = [ordered]@{
    backendState = ""
    authUrl = ""
    currentTailnet = ""
    health = @()
    hasTailnetIp = $false
    parseError = ""
  }

  if (-not $StatusResult -or -not $StatusResult.output) {
    return [pscustomobject]$snapshot
  }

  try {
    $parsed = ($StatusResult.output -join [Environment]::NewLine) | ConvertFrom-Json
    $snapshot.backendState = "$($parsed.BackendState)"
    $snapshot.authUrl = "$($parsed.AuthURL)"
    $snapshot.currentTailnet = "$($parsed.CurrentTailnet)"
    $snapshot.health = @($parsed.Health | ForEach-Object { "$_" })
    $snapshot.hasTailnetIp = @($parsed.TailscaleIPs | Where-Object { $_ }).Count -gt 0
  } catch {
    $snapshot.parseError = $_.Exception.Message
  }

  return [pscustomobject]$snapshot
}

function Get-FirewallReadiness {
  try {
    $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $FirewallRule -Action status -Port $Port
    $jsonLine = @($raw | Where-Object { "$_".Trim().StartsWith("{") }) | Select-Object -Last 1
    if ($jsonLine) { return $jsonLine | ConvertFrom-Json }
  } catch {
    return [pscustomobject]@{ ready = $false; error = $_.Exception.Message }
  }
  return [pscustomobject]@{ ready = $false; error = "Firewall status did not return JSON." }
}

function Get-HostSnapshot {
  $baseUrl = "http://127.0.0.1:$Port"
  $snapshot = [ordered]@{
    reachable = $false
    healthMode = ""
    networkRisk = ""
    monitorCount = 0
    addressCount = 0
    tailscaleUrls = @()
    lanUrls = @()
    connectionSetupStatus = ""
    error = ""
  }

  try {
    $health = Invoke-RestMethod -Uri "$baseUrl/api/health" -TimeoutSec 4
    $snapshot.reachable = [bool]$health.ok
    $snapshot.healthMode = "$($health.state.app.mode)"
    $snapshot.networkRisk = "$($health.state.networkRisk.level)"
    $snapshot.connectionSetupStatus = "$($health.state.connectionSetup.tailscale.status)"

    $hostState = Invoke-RestMethod -Uri "$baseUrl/api/host?key=$([uri]::EscapeDataString($HostKey))" -TimeoutSec 4
    $snapshot.monitorCount = @($hostState.monitors).Count
    $snapshot.addressCount = @($hostState.addresses).Count
    $snapshot.tailscaleUrls = @($hostState.addresses | Where-Object { $_.kind -eq "tailscale" } | ForEach-Object { $_.url })
    $snapshot.lanUrls = @($hostState.addresses | Where-Object { $_.kind -eq "lan" } | ForEach-Object { $_.url })
  } catch {
    $snapshot.error = $_.Exception.Message
  }

  return [pscustomobject]$snapshot
}

function Add-Step {
  param(
    [System.Collections.Generic.List[object]]$Steps,
    [string]$Name,
    [ValidateSet("pass", "warn", "fail")]
    [string]$Status,
    [string]$Detail,
    [string]$NextAction
  )

  $Steps.Add([pscustomobject]@{
    name = $Name
    status = $Status
    detail = $Detail
    nextAction = $NextAction
  }) | Out-Null
}

function ConvertTo-MarkdownCell {
  param([string]$Text)
  return "$Text".Replace("|", "\|").Replace("`r", " ").Replace("`n", " ")
}

function Write-SetupReport {
  param([object]$Result)

  New-Item -ItemType Directory -Path $ResolvedOutputDir -Force | Out-Null
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $jsonPath = Join-Path $ResolvedOutputDir "tailscale-setup-check-$timestamp.json"
  $mdPath = Join-Path $ResolvedOutputDir "tailscale-setup-check-$timestamp.md"
  $latestJsonPath = Join-Path $ResolvedOutputDir "tailscale-setup-check-latest.json"
  $latestMdPath = Join-Path $ResolvedOutputDir "tailscale-setup-check-latest.md"

  $Result | Add-Member -NotePropertyName reportJsonPath -NotePropertyValue $jsonPath -Force
  $Result | Add-Member -NotePropertyName reportMarkdownPath -NotePropertyValue $mdPath -Force
  $Result | Add-Member -NotePropertyName latestReportJsonPath -NotePropertyValue $latestJsonPath -Force
  $Result | Add-Member -NotePropertyName latestReportMarkdownPath -NotePropertyValue $latestMdPath -Force
  $Result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  $Result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $latestJsonPath -Encoding UTF8

  $rows = @($Result.steps | ForEach-Object {
    "| $(ConvertTo-MarkdownCell $_.status) | $(ConvertTo-MarkdownCell $_.name) | $(ConvertTo-MarkdownCell $_.detail) | $(ConvertTo-MarkdownCell $_.nextAction) |"
  })
  if ($rows.Count -eq 0) { $rows = @("| none | none | none | none |") }

  $tailscaleUrls = if ($Result.host.tailscaleUrls.Count -gt 0) { ($Result.host.tailscaleUrls | ForEach-Object { "- $_" }) -join [Environment]::NewLine } else { "- none" }
  $lanUrls = if ($Result.host.lanUrls.Count -gt 0) { ($Result.host.lanUrls | ForEach-Object { "- $_" }) -join [Environment]::NewLine } else { "- none" }

  $markdown = @"
# Tailscale Setup Check

Generated: $($Result.generatedAt)
Ready for Tailscale gate: $($Result.ok)
Tailscale CLI: $($Result.tailscale.command)
Tailscale backend state: $($Result.tailscale.statusSnapshot.backendState)
Tailscale auth URL: $($Result.tailscale.statusSnapshot.authUrl)
Host reachable: $($Result.host.reachable)
Firewall ready: $($Result.firewall.ready)

## Steps

| Status | Check | Detail | Next action |
| --- | --- | --- | --- |
$($rows -join [Environment]::NewLine)

## Tailscale URLs Advertised By Host

$tailscaleUrls

## LAN URLs Advertised By Host

$lanUrls

## Next Commands After This Is Ready

~~~powershell
npm run acceptance:doctor -- -Gate tailscale
npm run acceptance:prepare -- -Gate tailscale
npm run acceptance:phone -- -Gate tailscale
npm run acceptance:verify:save -- -Gate tailscale
# Stop only after this is the last remaining physical gate.
npm run acceptance:stop -- -Gate tailscale
~~~
"@

  $markdown | Set-Content -LiteralPath $mdPath -Encoding UTF8
  $markdown | Set-Content -LiteralPath $latestMdPath -Encoding UTF8
}

function Invoke-TailscaleSetupCheck {
  $steps = [System.Collections.Generic.List[object]]::new()
  $commandPath = Resolve-TailscaleCommand
  $version = Invoke-Tailscale -CommandPath $commandPath -Arguments @("version")
  $ip4 = Invoke-Tailscale -CommandPath $commandPath -Arguments @("ip", "-4")
  $ip6 = Invoke-Tailscale -CommandPath $commandPath -Arguments @("ip", "-6")
  $status = Invoke-Tailscale -CommandPath $commandPath -Arguments @("status", "--json")
  $statusSnapshot = Get-TailscaleStatusSnapshot -StatusResult $status
  $hostSnapshot = Get-HostSnapshot
  $firewall = Get-FirewallReadiness

  if ($commandPath) {
    Add-Step $steps "tailscale CLI installed" "pass" "Found $commandPath." "Keep laptop and phone signed into the same tailnet."
  } else {
    Add-Step $steps "tailscale CLI installed" "fail" "Tailscale CLI was not found on PATH or common install paths." "Install Tailscale from tailscale.com/download or run winget search tailscale, then sign in."
  }

  $ipCount = @($ip4.output).Count + @($ip6.output).Count
  if ($ipCount -gt 0) {
    Add-Step $steps "tailscale IP assigned" "pass" "tailscale ip returned $ipCount address(es)." "Restart the host so it advertises the Tailscale URL."
  } elseif ($commandPath) {
    $loginAction = if ($statusSnapshot.authUrl) { "Open $($statusSnapshot.authUrl) and finish Tailscale sign-in." } else { "Run tailscale status, sign in, and connect the laptop to the tailnet." }
    Add-Step $steps "tailscale IP assigned" "fail" "Tailscale is installed but no tailnet IP was returned. Backend state: $($statusSnapshot.backendState)." $loginAction
  }

  if ($status.ok) {
    $statusDetail = if ($statusSnapshot.authUrl) { "tailscale status --json succeeded; login URL is available." } else { "tailscale status --json succeeded." }
    $statusAction = if ($statusSnapshot.authUrl) { "Open $($statusSnapshot.authUrl), sign in, then run npm run tailscale:check:save." } else { "Confirm the phone appears in the same tailnet before the physical run." }
    Add-Step $steps "tailscale status" "pass" $statusDetail $statusAction
  } elseif ($commandPath) {
    $detail = if ($status.error) { $status.error } else { ($status.output -join " ") }
    Add-Step $steps "tailscale status" "warn" $detail "Open Tailscale, sign in, and confirm the device is connected."
  }

  if ($hostSnapshot.reachable) {
    Add-Step $steps "host reachable" "pass" "Host responded on http://127.0.0.1:$Port." "Keep this host running for the Tailscale acceptance run."
  } else {
    Add-Step $steps "host reachable" "fail" $hostSnapshot.error "Run npm run acceptance:prepare -- -Gate tailscale after Tailscale is connected."
  }

  if ($hostSnapshot.tailscaleUrls.Count -gt 0) {
    Add-Step $steps "host advertises Tailscale URL" "pass" ($hostSnapshot.tailscaleUrls -join ", ") "Open this URL from the phone while it is off the laptop Wi-Fi path."
  } else {
    Add-Step $steps "host advertises Tailscale URL" "fail" "Host does not advertise a Tailscale IPv4/IPv6 URL." "Connect Tailscale, then restart or prepare the host again."
  }

  if ($firewall.ready) {
    Add-Step $steps "windows firewall" "pass" "Inbound TCP $Port rule is ready." "No firewall action needed."
  } else {
    Add-Step $steps "windows firewall" "warn" "Inbound TCP $Port rule is not installed or not ready." "If the phone cannot connect, run npm run firewall:handoff first, then run the copied elevated install command only if you choose to allow inbound TCP $Port."
  }

  $failures = @($steps | Where-Object { $_.status -eq "fail" })
  $warnings = @($steps | Where-Object { $_.status -eq "warn" })
  return [pscustomobject]@{
    ok = $failures.Count -eq 0
    generatedAt = (Get-Date).ToString("o")
    port = $Port
    failureCount = $failures.Count
    warningCount = $warnings.Count
    steps = $steps
    tailscale = [pscustomobject]@{
      command = $commandPath
      version = $version
      ipv4 = @($ip4.output)
      ipv6 = @($ip6.output)
      status = $status
      statusSnapshot = $statusSnapshot
    }
    host = $hostSnapshot
    firewall = $firewall
  }
}

if ($SelfTest) {
  $ok = (Test-Path -LiteralPath $FirewallRule) -and (Test-Path -LiteralPath (Join-Path $Root "src\network.js"))
  [pscustomobject]@{
    ok = $ok
    firewallRuleExists = Test-Path -LiteralPath $FirewallRule
    networkModuleExists = Test-Path -LiteralPath (Join-Path $Root "src\network.js")
    commonInstallPathChecked = "C:\Program Files\Tailscale\tailscale.exe"
    exposesStatusSnapshot = $true
  } | ConvertTo-Json -Compress
  if (-not $ok) { exit 1 }
  exit 0
}

$result = Invoke-TailscaleSetupCheck
if ($Save) {
  Write-SetupReport -Result $result
}
$result | ConvertTo-Json -Depth 10 -Compress
if (-not $result.ok) { exit 1 }
