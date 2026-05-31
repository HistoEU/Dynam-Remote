param(
  [string]$BaseUrl = "http://127.0.0.1:4317",
  [string]$HostKey = "dev-host-key",
  [ValidateSet("all", "same-wifi", "tailscale")]
  [string]$Gate = "all",
  [ValidateSet("pre", "post")]
  [string]$Phase = "pre",
  [string]$OutputDir = "output\acceptance",
  [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$ResolvedOutputDir = Join-Path $Root $OutputDir

function Get-Checklist {
  param([string]$SelectedGate)

  $sameWifi = @(
    "Start the host with CAPTURE_MODE=screen.",
    "Confirm the host console shows Same Wi-Fi as ready and displays a LAN QR code.",
    "Open the LAN URL from the phone on the same Wi-Fi.",
    "Pair with the current PIN and approve on the laptop.",
    "Confirm the phone sees the live selected monitor.",
    "Test touchpad movement, single-tap left click, double-tap right click, press-and-hold right click, double-tap drag for tabs/windows, direct touch, two-finger scroll, keyboard shortcuts, compose text, monitor switching, reconnect, and Stop.",
    "Confirm phone diagnostics update while the stream is active and enter responsive mode during input.",
    "Tap Mark Proof in phone Settings so the exported host logs include an acceptance.phoneMark entry.",
    "Enable real input only after dry-run behavior is correct.",
    "Confirm Stop All Control disables real input, releases held buttons, disconnects the phone, and revokes the session."
  )

  $tailscale = @(
    "Install and start Tailscale on the laptop and phone.",
    "Sign both devices into the same tailnet.",
    "Confirm the host console shows Different Wi-Fi as ready with a Tailscale IPv4 100.64.0.0/10 URL or bracketed IPv6 fd7a:115c:a1e0::/48 URL.",
    "Move the phone off the laptop Wi-Fi path, for example cellular data with Tailscale still connected.",
    "Open the Tailscale URL from the phone.",
    "Pair with the current PIN and approve on the laptop.",
    "Tap Mark Proof in phone Settings so the exported host logs include the phone viewport and Tailscale-path marker.",
    "Confirm live selected-monitor viewing, input, reconnect, and emergency stop over Tailscale.",
    "Export logs after the run and keep them with this report."
  )

  if ($SelectedGate -eq "same-wifi") { return @{ sameWifi = $sameWifi } }
  if ($SelectedGate -eq "tailscale") { return @{ tailscale = $tailscale } }
  return @{ sameWifi = $sameWifi; tailscale = $tailscale }
}

function ConvertTo-MarkdownList {
  param([object[]]$Items)
  if (-not $Items -or $Items.Count -eq 0) { return "- none" }
  return ($Items | ForEach-Object { "- $_" }) -join [Environment]::NewLine
}

function ConvertTo-ChecklistMarkdown {
  param([object[]]$Items)
  return ($Items | ForEach-Object { "- [ ] $_" }) -join [Environment]::NewLine
}

function Get-TailscaleCliSnapshot {
  $snapshot = [ordered]@{
    checkedAt = (Get-Date).ToString("o")
    available = $false
    command = ""
    ipv4 = @()
    ipv6 = @()
    error = ""
  }

  $command = Get-Command tailscale -ErrorAction SilentlyContinue | Select-Object -First 1
  $commandPath = if ($command) { "$($command.Source)" } else { "" }
  if (-not $commandPath) {
    foreach ($candidate in @(
      "C:\Program Files\Tailscale\tailscale.exe",
      "C:\Program Files (x86)\Tailscale\tailscale.exe"
    )) {
      if (Test-Path -LiteralPath $candidate) {
        $commandPath = $candidate
        break
      }
    }
  }

  if (-not $commandPath) {
    $snapshot.error = "tailscale CLI was not found on PATH or common Windows install paths."
    return $snapshot
  }

  $snapshot.available = $true
  $snapshot.command = $commandPath

  foreach ($family in @("-4", "-6")) {
    try {
      $output = & $commandPath ip $family 2>&1
      if ($LASTEXITCODE -eq 0) {
        $lines = @($output | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
        if ($family -eq "-4") { $snapshot.ipv4 = $lines } else { $snapshot.ipv6 = $lines }
      } else {
        $snapshot.error = "tailscale ip $family exited with code $LASTEXITCODE`: $($output -join ' ')"
      }
    } catch {
      $snapshot.error = $_.Exception.Message
    }
  }

  return $snapshot
}

function New-Report {
  param(
    [object]$State,
    [hashtable]$Checklist,
    [object]$TailscaleCli,
    [string]$SelectedGate,
    [string]$SelectedPhase,
    [bool]$HostReachable,
    [string]$ErrorMessage
  )

  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  New-Item -ItemType Directory -Path $ResolvedOutputDir -Force | Out-Null
  $filePrefix = "manual-acceptance-$SelectedGate-$SelectedPhase-$timestamp"
  $jsonPath = Join-Path $ResolvedOutputDir "$filePrefix.json"
  $mdPath = Join-Path $ResolvedOutputDir "$filePrefix.md"
  $hostLogsPath = Join-Path $ResolvedOutputDir "$filePrefix-host-logs.json"
  $hostLogsExported = $false
  $hostLogsError = ""

  if ($HostReachable) {
    try {
      Invoke-WebRequest -Uri "$BaseUrl/api/logs?key=$([uri]::EscapeDataString($HostKey))" -TimeoutSec 5 -OutFile $hostLogsPath | Out-Null
      $hostLogsExported = $true
    } catch {
      $hostLogsError = $_.Exception.Message
      $hostLogsPath = ""
    }
  } else {
    $hostLogsPath = ""
  }

  $addresses = @()
  $monitors = @()
  $networkValidation = $null
  $networkRisk = $null
  $streamStats = $null
  $inputSafety = $null
  $settings = $null
  $sessions = @()

  if ($State) {
    $addresses = @($State.addresses | ForEach-Object { "$($_.kind) $($_.name): $($_.url)" })
    $monitors = @($State.monitors | ForEach-Object { "$($_.id) $($_.name) $($_.bounds.width)x$($_.bounds.height) scale=$($_.scaleFactor) primary=$($_.primary) status=$($_.status)" })
    $networkValidation = $State.securityStatus.networkValidation
    $networkRisk = $State.securityStatus.networkRisk
    $streamStats = $State.streamStats
    $inputSafety = $State.inputSafety
    $settings = $State.settings
    $sessions = @($State.sessions)
  }

  $report = [ordered]@{
    generatedAt = (Get-Date).ToString("o")
    gate = $SelectedGate
    phase = $SelectedPhase
    hostReachable = $HostReachable
    error = $ErrorMessage
    baseUrl = $BaseUrl
    hostUrl = "$BaseUrl/host?key=$HostKey"
    addresses = $addresses
    monitors = $monitors
    networkRisk = $networkRisk
    networkValidation = $networkValidation
    streamStats = $streamStats
    inputSafety = $inputSafety
    settings = $settings
    sessions = $sessions
    hostLogsExported = $hostLogsExported
    hostLogsPath = $hostLogsPath
    hostLogsError = $hostLogsError
    tailscaleCli = $TailscaleCli
    checklist = $Checklist
    evidenceInstructions = @(
      "Run this report once with -Phase pre before the physical phone acceptance run and once with -Phase post after the run.",
      "Host logs are auto-exported beside this report when the host is reachable.",
      "Do not mark the gate passed until every checklist item is checked with real-device evidence."
    )
  }

  $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

  $sameWifiSection = ""
  if ($Checklist.ContainsKey("sameWifi")) {
    $sameWifiSection = @"
## Same-Wi-Fi Gate

$(ConvertTo-ChecklistMarkdown $Checklist.sameWifi)

"@
  }

  $tailscaleSection = ""
  if ($Checklist.ContainsKey("tailscale")) {
    $tailscaleSection = @"
## Tailscale Different-Wi-Fi Gate

$(ConvertTo-ChecklistMarkdown $Checklist.tailscale)

"@
  }

  $validationJson = if ($networkValidation) { $networkValidation | ConvertTo-Json -Depth 8 } else { "not available" }
  $riskJson = if ($networkRisk) { $networkRisk | ConvertTo-Json -Depth 6 } else { "not available" }
  $tailscaleCliJson = if ($TailscaleCli) { $TailscaleCli | ConvertTo-Json -Depth 5 } else { "not available" }

  $markdown = @"
# Manual Acceptance Evidence Report

Generated: $($report.generatedAt)
Gate: $SelectedGate
Phase: $SelectedPhase
Host reachable: $HostReachable
Base URL: $BaseUrl
Host console: $($report.hostUrl)

## Current Host Snapshot

Network risk:

~~~json
$riskJson
~~~

Network validation:

~~~json
$validationJson
~~~

Addresses:

$(ConvertTo-MarkdownList $addresses)

Monitors:

$(ConvertTo-MarkdownList $monitors)

Input safety: $($inputSafety.mode) / enabled=$($inputSafety.enabled)
Stream: quality=$($streamStats.quality), source=$($streamStats.source), adaptive=$($streamStats.adaptiveMode), clients=$($streamStats.connectedClients)
Sessions currently visible: $($sessions.Count)
Host logs exported: $hostLogsExported
Host logs path: $(if ($hostLogsPath) { $hostLogsPath } else { "not saved" })

Tailscale CLI snapshot:

~~~json
$tailscaleCliJson
~~~

$sameWifiSection$tailscaleSection## Required Evidence To Attach

- [ ] Screenshot or photo of phone connected to the live selected monitor.
- [ ] Host logs JSON from after the test run is saved beside this report.
- [ ] Host logs JSON includes an `acceptance.phoneMark` entry from the physical phone.
- [ ] Note of network path used: LAN URL, Tailscale IPv4 URL, or bracketed Tailscale IPv6 URL.
- [ ] Confirmation that Stop and Stop All Control released input and disconnected the phone.
- [ ] Any failures, lag, UI clipping, or confusing controls observed during the run.

## Result

- [ ] PASS
- [ ] FAIL

Notes:

"@

  if (-not $HostReachable) {
    $markdown += [Environment]::NewLine + "Host query error: $ErrorMessage" + [Environment]::NewLine
  }
  if ($hostLogsError) {
    $markdown += [Environment]::NewLine + "Host logs export error: $hostLogsError" + [Environment]::NewLine
  }

  $markdown | Set-Content -LiteralPath $mdPath -Encoding UTF8

  return [pscustomobject]@{
    ok = $true
    gate = $SelectedGate
    phase = $SelectedPhase
    hostReachable = $HostReachable
    markdownPath = $mdPath
    jsonPath = $jsonPath
    hostLogsExported = $hostLogsExported
    hostLogsPath = $hostLogsPath
    hostLogsError = $hostLogsError
  }
}

$checklist = Get-Checklist -SelectedGate $Gate
$tailscaleCli = Get-TailscaleCliSnapshot

if ($SelfTest) {
  [pscustomobject]@{
    ok = $true
    root = "$Root"
    outputDir = "$ResolvedOutputDir"
    gate = $Gate
    phase = $Phase
    sameWifiItems = if ($checklist.ContainsKey("sameWifi")) { $checklist.sameWifi.Count } else { 0 }
    tailscaleItems = if ($checklist.ContainsKey("tailscale")) { $checklist.tailscale.Count } else { 0 }
    tailscaleCliChecked = $true
    commonInstallPathChecked = "C:\Program Files\Tailscale\tailscale.exe"
  } | ConvertTo-Json -Compress
  exit 0
}

$state = $null
$hostReachable = $false
$errorMessage = ""

try {
  $state = Invoke-RestMethod -Uri "$BaseUrl/api/host?key=$([uri]::EscapeDataString($HostKey))" -TimeoutSec 5
  $hostReachable = $true
} catch {
  $errorMessage = $_.Exception.Message
}

New-Report -State $state -Checklist $checklist -TailscaleCli $tailscaleCli -SelectedGate $Gate -SelectedPhase $Phase -HostReachable $hostReachable -ErrorMessage $errorMessage |
  ConvertTo-Json -Compress
