param(
  [string]$OutputDir = "output\acceptance",
  [switch]$Save,
  [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$ResolvedOutputDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $Root $OutputDir }

function Resolve-TailscaleCommand {
  $command = Get-Command tailscale -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($command) { return $command.Source }

  foreach ($candidate in @(
    "C:\Program Files\Tailscale\tailscale.exe",
    "C:\Program Files (x86)\Tailscale\tailscale.exe"
  )) {
    if (Test-Path -LiteralPath $candidate) { return $candidate }
  }
  return ""
}

function Get-CommandSource {
  param([string]$Name)
  $command = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($command) { return "$($command.Source)" }
  return ""
}

function Invoke-OptionalCommand {
  param(
    [string]$FilePath,
    [string[]]$Arguments
  )

  if (-not $FilePath) {
    return [pscustomobject]@{ ok = $false; exitCode = -1; output = @(); error = "Command was not found." }
  }

  try {
    $output = & $FilePath @Arguments 2>&1
    return [pscustomobject]@{
      ok = $LASTEXITCODE -eq 0
      exitCode = $LASTEXITCODE
      output = @($output | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
      error = ""
    }
  } catch {
    return [pscustomobject]@{ ok = $false; exitCode = -1; output = @(); error = $_.Exception.Message }
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

function Get-TailscaleServiceSnapshot {
  $service = Get-Service -Name Tailscale -ErrorAction SilentlyContinue
  if (-not $service) {
    return [pscustomobject]@{ installed = $false; status = ""; startType = ""; name = "" }
  }
  return [pscustomobject]@{
    installed = $true
    name = "$($service.Name)"
    status = "$($service.Status)"
    startType = "$($service.StartType)"
  }
}

function ConvertTo-MarkdownCell {
  param([string]$Text)
  return "$Text".Replace("|", "\|").Replace("`r", " ").Replace("`n", " ")
}

function New-TailscaleBootstrapReport {
  $tailscaleCommand = Resolve-TailscaleCommand
  $wingetCommand = Get-CommandSource "winget"
  $service = Get-TailscaleServiceSnapshot
  $version = Invoke-OptionalCommand -FilePath $tailscaleCommand -Arguments @("version")
  $ip4 = Invoke-OptionalCommand -FilePath $tailscaleCommand -Arguments @("ip", "-4")
  $ip6 = Invoke-OptionalCommand -FilePath $tailscaleCommand -Arguments @("ip", "-6")
  $status = Invoke-OptionalCommand -FilePath $tailscaleCommand -Arguments @("status", "--json")
  $statusSnapshot = Get-TailscaleStatusSnapshot -StatusResult $status
  $hasTailnetIp = (@($ip4.output).Count + @($ip6.output).Count) -gt 0

  $steps = [System.Collections.Generic.List[object]]::new()
  function Add-Step {
    param([string]$Name, [string]$Status, [string]$Detail, [string]$Command)
    $steps.Add([pscustomobject]@{
      name = $Name
      status = $Status
      detail = $Detail
      command = $Command
    }) | Out-Null
  }

  if ($tailscaleCommand) {
    Add-Step "Install Tailscale on the laptop" "done" "Found $tailscaleCommand." "npm run tailscale:check:save"
  } elseif ($wingetCommand) {
    Add-Step "Install Tailscale on the laptop" "needed" "Tailscale is not installed, but winget is available." "winget install --id Tailscale.Tailscale -e --source winget"
  } else {
    Add-Step "Install Tailscale on the laptop" "needed" "Tailscale is not installed and winget was not found." "Open https://tailscale.com/download and install the Windows app."
  }

  if ($service.installed -and $service.status -eq "Running") {
    Add-Step "Start the Windows Tailscale service" "done" "Service $($service.name) is running." "npm run tailscale:check:save"
  } elseif ($service.installed) {
    Add-Step "Start the Windows Tailscale service" "needed" "Service $($service.name) is installed but status is $($service.status)." "Start-Service Tailscale"
  } else {
    Add-Step "Start the Windows Tailscale service" "waiting" "The service appears after installation." "Start Tailscale from the Start menu after install."
  }

  if ($tailscaleCommand -and $hasTailnetIp) {
    Add-Step "Sign into the laptop tailnet" "done" "Tailscale returned a tailnet IP." "npm run acceptance:ready -- -Gate tailscale"
  } elseif ($tailscaleCommand) {
    $loginCommand = if ($statusSnapshot.authUrl) { "Open $($statusSnapshot.authUrl)" } else { "& `"$tailscaleCommand`" up" }
    Add-Step "Sign into the laptop tailnet" "needed" "Tailscale is installed, but no tailnet IP was returned. Backend state: $($statusSnapshot.backendState)." $loginCommand
  } else {
    Add-Step "Sign into the laptop tailnet" "waiting" "Install Tailscale first." "Open Tailscale and sign in after install."
  }

  Add-Step "Install and sign in on the phone" "needed" "The phone must be in the same tailnet for the different-Wi-Fi gate." "Install the free Tailscale mobile app, sign into the same account, and keep it connected."
  Add-Step "Refresh this project's Tailscale readiness" "needed" "The host must advertise a 100.x or fd7a:... Tailscale URL before the phone run." "npm run acceptance:ready -- -Gate tailscale"
  Add-Step "Run the physical different-Wi-Fi proof" "needed" "The goal is not complete until the real phone proof verifier passes." "npm run acceptance:phone -- -Gate tailscale -SkipStart -RequireReady"

  return [pscustomobject]@{
    ok = $true
    generatedAt = (Get-Date).ToString("o")
    mutatesSystem = $false
    readyForTailscaleAcceptance = [bool]($tailscaleCommand -and $service.installed -and $hasTailnetIp)
    tailscale = [pscustomobject]@{
      command = $tailscaleCommand
      service = $service
      version = $version
      status = $status
      statusSnapshot = $statusSnapshot
      ipv4 = @($ip4.output)
      ipv6 = @($ip6.output)
    }
    winget = [pscustomobject]@{
      available = -not [string]::IsNullOrWhiteSpace($wingetCommand)
      command = $wingetCommand
      installCommand = "winget install --id Tailscale.Tailscale -e --source winget"
    }
    steps = @($steps)
    nextCommands = @(
      "npm run tailscale:check:save",
      "npm run acceptance:ready -- -Gate tailscale",
      "npm run acceptance:next",
      "npm run acceptance:phone -- -Gate tailscale -SkipStart -RequireReady",
      "npm run acceptance:verify:save -- -Gate tailscale"
    )
  }
}

function Write-TailscaleBootstrapReport {
  param([object]$Report)

  New-Item -ItemType Directory -Path $ResolvedOutputDir -Force | Out-Null
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $jsonPath = Join-Path $ResolvedOutputDir "tailscale-bootstrap-$timestamp.json"
  $mdPath = Join-Path $ResolvedOutputDir "tailscale-bootstrap-$timestamp.md"
  $latestJsonPath = Join-Path $ResolvedOutputDir "tailscale-bootstrap-latest.json"
  $latestMdPath = Join-Path $ResolvedOutputDir "tailscale-bootstrap-latest.md"

  $Report | Add-Member -NotePropertyName reportJsonPath -NotePropertyValue $jsonPath -Force
  $Report | Add-Member -NotePropertyName reportMarkdownPath -NotePropertyValue $mdPath -Force
  $Report | Add-Member -NotePropertyName latestReportJsonPath -NotePropertyValue $latestJsonPath -Force
  $Report | Add-Member -NotePropertyName latestReportMarkdownPath -NotePropertyValue $latestMdPath -Force
  $Report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  $Report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $latestJsonPath -Encoding UTF8

  $rows = @($Report.steps | ForEach-Object {
    "| $(ConvertTo-MarkdownCell $_.status) | $(ConvertTo-MarkdownCell $_.name) | $(ConvertTo-MarkdownCell $_.detail) | ``$(ConvertTo-MarkdownCell $_.command)`` |"
  })
  if ($rows.Count -eq 0) { $rows = @("| none | none | none | none |") }

  $commands = @($Report.nextCommands | ForEach-Object { $_ })
  $markdown = @"
# Tailscale Bootstrap

Generated: $($Report.generatedAt)
Mutates system: $($Report.mutatesSystem)
Ready for Tailscale acceptance: $($Report.readyForTailscaleAcceptance)
Tailscale command: $($Report.tailscale.command)
Tailscale service: installed=$($Report.tailscale.service.installed), status=$($Report.tailscale.service.status)
Tailscale backend state: $($Report.tailscale.statusSnapshot.backendState)
Tailscale auth URL: $($Report.tailscale.statusSnapshot.authUrl)
Winget available: $($Report.winget.available)

This file is a setup assistant for the free different-Wi-Fi path. It does not install software, sign into Tailscale, change firewall rules, or mark the physical gate complete.

## Steps

| Status | Step | Detail | Command |
| --- | --- | --- | --- |
$($rows -join [Environment]::NewLine)

## Next Commands After Setup

~~~powershell
$($commands -join [Environment]::NewLine)
~~~
"@

  $markdown | Set-Content -LiteralPath $mdPath -Encoding UTF8
  $markdown | Set-Content -LiteralPath $latestMdPath -Encoding UTF8
}

if ($SelfTest) {
  $report = New-TailscaleBootstrapReport
  $hasInstallStep = @($report.steps | Where-Object { $_.name -eq "Install Tailscale on the laptop" }).Count -eq 1
  $hasVerifyCommand = @($report.nextCommands | Where-Object { $_ -eq "npm run acceptance:verify:save -- -Gate tailscale" }).Count -eq 1
  $ok = $report.ok -and -not $report.mutatesSystem -and $hasInstallStep -and $hasVerifyCommand
  [pscustomobject]@{
    ok = $ok
    mutatesSystem = $report.mutatesSystem
    hasInstallStep = $hasInstallStep
    hasVerifierCommand = $hasVerifyCommand
    exposesStatusSnapshot = $true
  } | ConvertTo-Json -Compress
  if (-not $ok) { exit 1 }
  exit 0
}

$report = New-TailscaleBootstrapReport
if ($Save) {
  Write-TailscaleBootstrapReport -Report $report
}
$report | ConvertTo-Json -Depth 8 -Compress
