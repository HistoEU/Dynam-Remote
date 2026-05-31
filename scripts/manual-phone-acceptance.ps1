param(
  [ValidateSet("same-wifi", "tailscale")]
  [string]$Gate = "same-wifi",
  [string]$HostKey = "dev-host-key",
  [int]$Port = 4317,
  [string]$NodePath = "node",
  [string]$OutputDir = "output\acceptance",
  [switch]$SkipStart,
  [switch]$SkipVerifyAfter,
  [switch]$RequireReady,
  [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$ResolvedOutputDir = Join-Path $Root $OutputDir
$AcceptanceReport = Join-Path $PSScriptRoot "acceptance-report.ps1"
$FirewallRule = Join-Path $PSScriptRoot "firewall-rule.ps1"
$DoctorScript = Join-Path $PSScriptRoot "acceptance-doctor.ps1"
$VerifierScript = Join-Path $PSScriptRoot "verify-phone-acceptance.ps1"

function Get-PhoneAppVersion {
  $serviceWorkerPath = Join-Path $Root "public\sw.js"
  if (-not (Test-Path -LiteralPath $serviceWorkerPath -PathType Leaf)) {
    throw "Cannot derive phone app version because public\sw.js is missing."
  }
  $source = Get-Content -Raw -LiteralPath $serviceWorkerPath
  $match = [regex]::Match($source, 'remote-controller-shell-v(?<version>[0-9]+)')
  if (-not $match.Success) {
    throw "Cannot derive phone app version from public\sw.js cache name."
  }
  return $match.Groups["version"].Value
}

$PhoneAppVersion = Get-PhoneAppVersion

function Get-Checklist {
  param([string]$SelectedGate)

  if ($SelectedGate -eq "same-wifi") {
    return @(
      "Start from the LAN URL shown by the host console.",
      "Open the LAN URL from the phone on the same Wi-Fi.",
      "Pair with the current PIN and approve on the laptop.",
      "Confirm the phone sees the live selected monitor.",
      "Move with the touchpad, single-tap left click, double-tap right click, press-and-hold right click, double-tap drag a tab/window, scroll, use the keyboard sheet, compose text, switch monitor, reconnect, and press Stop.",
      "Confirm diagnostics enter responsive mode during input and settle after idle.",
      "Lock the phone or switch away from the PWA, then confirm hidden-stream mode and resume.",
      "Adjust scroll speed, touch halo, haptics, zoom, pinch pan, edge pan, and precision mode.",
      "Tap Mark Proof from the controller proof banner or phone Settings so the host logs the phone viewport, PWA mode, and diagnostics marker.",
      "Add the PWA to the home screen and confirm it reopens the remembered host session.",
      "Enable real input only after dry-run behavior is correct, then test one low-risk click/move/text action.",
      "Enable trusted devices, approve once manually, verify repeat correct-PIN pairing can auto-approve, then revoke trust.",
      "Confirm Stop All Control disables real input, releases held buttons, disconnects the phone, and revokes the session."
    )
  }

  return @(
    "Install and start Tailscale on the laptop and phone.",
    "Sign both devices into the same Tailscale tailnet.",
    "Confirm the host console shows Different Wi-Fi as ready with a Tailscale IPv4 URL or bracketed IPv6 URL.",
    "Move the phone away from the laptop Wi-Fi path, for example cellular data with Tailscale still connected.",
    "Open the Tailscale URL from the phone.",
    "Pair with the current PIN and approve on the laptop.",
    "Tap Mark Proof from the controller proof banner or phone Settings so the exported host logs include the different-Wi-Fi phone marker.",
    "Confirm live selected-monitor viewing, dry-run input, real-input safety gating, reconnect, and Stop.",
    "Confirm Stop All Control disables real input, releases held buttons, disconnects the phone, and revokes the session."
  )
}

function Invoke-AcceptanceReport {
  param(
    [string]$SelectedGate,
    [string]$SelectedPhase,
    [string]$BaseUrl
  )

  $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $AcceptanceReport -Gate $SelectedGate -Phase $SelectedPhase -BaseUrl $BaseUrl -HostKey $HostKey -OutputDir $OutputDir
  $jsonLine = @($raw | Where-Object { "$_".Trim().StartsWith("{") }) | Select-Object -Last 1
  if (-not $jsonLine) {
    throw "Acceptance report did not return JSON for $SelectedGate $SelectedPhase."
  }
  return $jsonLine | ConvertFrom-Json
}

function Get-HostState {
  param([string]$BaseUrl)
  return Invoke-RestMethod -Uri "$BaseUrl/api/host?key=$([uri]::EscapeDataString($HostKey))" -TimeoutSec 5
}

function Get-ShortLivedPin {
  param([string]$BaseUrl)
  try {
    $pin = Invoke-RestMethod `
      -Uri "$BaseUrl/api/refresh-pin" `
      -Method Post `
      -Headers @{ "x-host-key" = $HostKey } `
      -Body "{}" `
      -ContentType "application/json" `
      -TimeoutSec 6
    return [pscustomobject]@{
      available = $true
      pin = "$($pin.pin)"
      secondsRemaining = if ($null -ne $pin.secondsRemaining) { [int]$pin.secondsRemaining } else { 0 }
      refreshedAt = (Get-Date).ToString("o")
      error = ""
    }
  } catch {
    return [pscustomobject]@{
      available = $false
      pin = ""
      secondsRemaining = 0
      refreshedAt = ""
      error = $_.Exception.Message
    }
  }
}

function Write-RunNote {
  param(
    [string]$Path,
    [string]$Text
  )
  Add-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

function Read-JsonFile {
  param([string]$PathValue)
  if ([string]::IsNullOrWhiteSpace($PathValue) -or -not (Test-Path -LiteralPath $PathValue -PathType Leaf)) {
    return $null
  }
  try {
    return Get-Content -Raw -LiteralPath $PathValue | ConvertFrom-Json
  } catch {
    return $null
  }
}

function Get-LatestPreparedSession {
  param([string]$SelectedGate)
  return Read-JsonFile -PathValue (Join-Path $ResolvedOutputDir "phone-acceptance-session-$SelectedGate-latest.json")
}

function Get-LatestReadyStatus {
  param([string]$SelectedGate)
  return Read-JsonFile -PathValue (Join-Path $ResolvedOutputDir "phone-acceptance-ready-$SelectedGate-latest.json")
}

function ConvertTo-StringArray {
  param([object]$Values)
  if ($null -eq $Values) { return @() }
  return @($Values | Where-Object { $null -ne $_ } | ForEach-Object { "$_" })
}

function Add-AcceptanceQuery {
  param(
    [string]$Url,
    [string]$SelectedGate
  )

  if ([string]::IsNullOrWhiteSpace($Url)) { return $Url }
  $proofUrl = "$Url"
  if ($proofUrl -notmatch "(\?|&)v=") {
    $versionSeparator = if ($proofUrl.Contains("?")) { "&" } else { "?" }
    $proofUrl = "$proofUrl${versionSeparator}v=$PhoneAppVersion"
  }
  $separator = if ($proofUrl.Contains("?")) { "&" } else { "?" }
  return "$proofUrl${separator}acceptance=1&gate=$([uri]::EscapeDataString($SelectedGate))&step=physical-phone-proof"
}

function Get-HealthUrl {
  param([string]$Url)
  try {
    $uri = [uri]$Url
    return "$($uri.GetLeftPart([System.UriPartial]::Authority))/api/health"
  } catch {
    return "$Url/api/health"
  }
}

function Test-PhoneUrlPreflight {
  param([object[]]$Urls)

  $results = @()
  foreach ($url in @($Urls)) {
    $healthUrl = Get-HealthUrl -Url "$url"
    try {
      $response = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 4
      $results += [pscustomobject]@{
        url = "$url"
        healthUrl = $healthUrl
        ok = $response.StatusCode -eq 200
        statusCode = $response.StatusCode
        error = ""
      }
    } catch {
      $statusCode = 0
      if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
        $statusCode = [int]$_.Exception.Response.StatusCode
      }
      $results += [pscustomobject]@{
        url = "$url"
        healthUrl = $healthUrl
        ok = $false
        statusCode = $statusCode
        error = $_.Exception.Message
      }
    }
  }
  return $results
}

function Test-VpnLikeAddress {
  param([object]$Address)

  $name = "$($Address.name)"
  return $name -match "(?i)(vpn|nord|lynx|wireguard|zerotier|hamachi|tap|tun|wg)"
}

function Get-PhoneAddressSelection {
  param(
    [object]$State,
    [string]$SelectedGate
  )

  $addresses = if ($State -and $State.addresses) { @($State.addresses) } else { @() }
  if ($SelectedGate -eq "tailscale") {
    $tailscale = @($addresses | Where-Object { $_.kind -eq "tailscale" })
    return [pscustomobject]@{
      targetKind = "tailscale"
      recommended = @($tailscale | ForEach-Object { $_.url })
      secondary = @()
      allPhoneUrls = @($addresses | Where-Object { $_.kind -eq "lan" -or $_.kind -eq "tailscale" } | ForEach-Object { $_.url })
      note = "Tailscale gate uses only Tailscale URLs so the different-Wi-Fi proof cannot accidentally use a LAN path."
    }
  }

  $lan = @($addresses | Where-Object { $_.kind -eq "lan" })
  $recommended = @($lan | Where-Object { -not (Test-VpnLikeAddress -Address $_) })
  $secondary = @($lan | Where-Object { Test-VpnLikeAddress -Address $_ })
  if ($recommended.Count -eq 0 -and $lan.Count -gt 0) {
    $recommended = $lan
    $secondary = @()
  }

  return [pscustomobject]@{
    targetKind = "lan"
    recommended = @($recommended | ForEach-Object { $_.url })
    secondary = @($secondary | ForEach-Object { "$($_.url) ($($_.name))" })
    allPhoneUrls = @($addresses | Where-Object { $_.kind -eq "lan" -or $_.kind -eq "tailscale" } | ForEach-Object { $_.url })
    note = "Same-Wi-Fi gate recommends non-VPN LAN adapters first; VPN-like private adapters are secondary candidates."
  }
}

function Get-FirewallReadiness {
  try {
    $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $FirewallRule -Action status -Port $Port
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

function Invoke-AcceptanceDoctor {
  param([string]$SelectedGate)

  $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $DoctorScript -Gate $SelectedGate -HostKey $HostKey -Port $Port -NodePath $NodePath -OutputDir $OutputDir -SkipStart 2>&1
  $jsonLine = @($raw | Where-Object { "$_".Trim().StartsWith("{") }) | Select-Object -Last 1
  if (-not $jsonLine) {
    return [pscustomobject]@{
      ok = $false
      status = "doctor-error"
      error = "Acceptance doctor did not return JSON."
      raw = @($raw | ForEach-Object { "$_" })
    }
  }
  return $jsonLine | ConvertFrom-Json
}

function Invoke-AcceptanceVerifier {
  param(
    [string]$SelectedGate,
    [string]$SelectedSummaryPath
  )

  $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $VerifierScript -Gate $SelectedGate -SummaryPath $SelectedSummaryPath -OutputDir $OutputDir -Save 2>&1
  $exitCode = $LASTEXITCODE
  $jsonLine = @($raw | Where-Object { "$_".Trim().StartsWith("{") }) | Select-Object -Last 1
  $parsed = $null
  if ($jsonLine) {
    try {
      $parsed = $jsonLine | ConvertFrom-Json
    } catch {
      $parsed = $null
    }
  }

  return [pscustomobject]@{
    ok = ($exitCode -eq 0) -and $parsed -and $parsed.ok -eq $true
    exitCode = $exitCode
    result = $parsed
    raw = @($raw | ForEach-Object { "$_" })
  }
}

function Get-PreRunBlockers {
  param(
    [object]$Doctor,
    [string]$TargetKind,
    [object[]]$TargetPhoneUrls,
    [object[]]$Preflight
  )

  $blockers = @()
  foreach ($failure in @($Doctor.checks | Where-Object { $_.status -eq "fail" })) {
    $blockers += [pscustomobject]@{
      name = "doctor: $($failure.name)"
      detail = "$($failure.detail)"
      nextAction = "$($failure.nextAction)"
    }
  }
  if (@($TargetPhoneUrls).Count -eq 0) {
    $blockers += [pscustomobject]@{
      name = "phone URL"
      detail = "No $TargetKind phone URL is currently advertised for this gate."
      nextAction = "Run npm run acceptance:ready -- -Gate $Gate after fixing network setup."
    }
  }
  $passingPreflight = @($Preflight | Where-Object { $_.ok -eq $true })
  if (@($TargetPhoneUrls).Count -gt 0 -and $passingPreflight.Count -eq 0) {
    $blockers += [pscustomobject]@{
      name = "selected-gate URL preflight"
      detail = "The laptop could not preflight any selected $TargetKind /api/health URL."
      nextAction = "Fix the advertised URL, host listener, firewall, or Tailscale setup before using the phone."
    }
  }
  return @($blockers)
}

function Read-ChecklistAnswer {
  param([string]$Prompt = "Result [y/n/s]")

  while ($true) {
    $answer = (Read-Host $Prompt).Trim().ToLowerInvariant()
    if (@("y", "n", "s").Contains($answer)) {
      return $answer
    }
    Write-Host "Please enter y for PASS, n for FAIL, or s for SKIP. Blank or other input is not recorded."
  }
}

$checklist = Get-Checklist -SelectedGate $Gate

if ($SelfTest) {
  $proofUrl = Add-AcceptanceQuery -Url "http://192.168.1.10:4317" -SelectedGate $Gate
  $healthUrl = Get-HealthUrl -Url $proofUrl
  $scriptText = Get-Content -Raw -LiteralPath $PSCommandPath
  [pscustomobject]@{
    ok = ($proofUrl -match "acceptance=1") -and
      ($proofUrl -match "v=$PhoneAppVersion") -and
      ($proofUrl -match "gate=$Gate") -and
      ($healthUrl -eq "http://192.168.1.10:4317/api/health") -and
      ($scriptText -match "Get-ShortLivedPin") -and
      ($scriptText -match "REAL_INPUT = `"1`"") -and
      ($scriptText -match "QUALITY_DEFAULT = `"fast`"")
    gate = $Gate
    checklistItems = $checklist.Count
    root = "$Root"
    outputDir = "$ResolvedOutputDir"
    acceptanceReportExists = Test-Path -LiteralPath $AcceptanceReport
    acceptanceDoctorExists = Test-Path -LiteralPath $DoctorScript
    verifierExists = Test-Path -LiteralPath $VerifierScript
    firewallScriptExists = Test-Path -LiteralPath $FirewallRule
    startsHostByDefault = -not $SkipStart
    startsRealInput = $true
    startsFastQuality = $true
    showsCurrentPin = $true
    autoVerifyAfterRun = -not $SkipVerifyAfter
    supportsRequireReady = $true
    groupsRecommendedPhoneUrls = $true
    requiresExplicitStepAnswer = $true
    summaryOkRequiresVerifier = $true
    phoneAppVersion = $PhoneAppVersion
    gateAwareProofUrl = $proofUrl
    proofUrlHealthCheck = $healthUrl
  } | ConvertTo-Json -Compress
  exit 0
}

New-Item -ItemType Directory -Path $ResolvedOutputDir -Force | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$baseUrl = "http://127.0.0.1:$Port"
$notesPath = Join-Path $ResolvedOutputDir "manual-phone-run-$Gate-$timestamp.md"
$summaryPath = Join-Path $ResolvedOutputDir "manual-phone-run-$Gate-$timestamp.json"
$started = $null

try {
  $existing = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -First 1
  if (-not $existing -and -not $SkipStart) {
    $env:HOST_KEY = $HostKey
    $env:CAPTURE_MODE = "screen"
    $env:REAL_INPUT = "1"
    $env:QUALITY_DEFAULT = "fast"
    $env:HOST = "::"
    $started = Start-Process -FilePath $NodePath -ArgumentList "src\server.js" -WorkingDirectory $Root -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 2
  }

  $state = Get-HostState -BaseUrl $baseUrl
  $shortLivedPin = Get-ShortLivedPin -BaseUrl $baseUrl
  $doctor = Invoke-AcceptanceDoctor -SelectedGate $Gate
  $pre = Invoke-AcceptanceReport -SelectedGate $Gate -SelectedPhase "pre" -BaseUrl $baseUrl
  $latestSession = Get-LatestPreparedSession -SelectedGate $Gate
  $latestReady = Get-LatestReadyStatus -SelectedGate $Gate

  $addresses = @($state.addresses | ForEach-Object { "$($_.kind) $($_.name): $($_.url)" })
  $phoneSelection = Get-PhoneAddressSelection -State $state -SelectedGate $Gate
  $phoneUrls = @($phoneSelection.allPhoneUrls | ForEach-Object { Add-AcceptanceQuery -Url "$_" -SelectedGate $Gate })
  $rawPhoneUrls = @($phoneSelection.allPhoneUrls)
  $targetKind = $phoneSelection.targetKind
  $targetPhoneUrls = @($phoneSelection.recommended | ForEach-Object { Add-AcceptanceQuery -Url "$_" -SelectedGate $Gate })
  $rawTargetPhoneUrls = @($phoneSelection.recommended)
  $secondaryPhoneUrls = @($phoneSelection.secondary)
  $preflight = @(Test-PhoneUrlPreflight -Urls $targetPhoneUrls)
  $firewall = Get-FirewallReadiness
  $hostConsole = "$baseUrl/host?key=$HostKey"
  $preRunBlockers = @(Get-PreRunBlockers -Doctor $doctor -TargetKind $targetKind -TargetPhoneUrls $targetPhoneUrls -Preflight $preflight)
  $runCardHtml = if ($latestReady -and $latestReady.runCardHtml) { "$($latestReady.runCardHtml)" } elseif ($latestSession -and $latestSession.runCardHtml) { "$($latestSession.runCardHtml)" } else { "" }
  $runCardMarkdown = if ($latestReady -and $latestReady.runCardMarkdown) { "$($latestReady.runCardMarkdown)" } elseif ($latestSession -and $latestSession.runCardMarkdown) { "$($latestSession.runCardMarkdown)" } else { "" }
  $qrCodes = if ($latestSession -and $latestSession.qrCodes) { @($latestSession.qrCodes) } else { @() }

  Write-RunNote -Path $notesPath -Text "# Manual Phone Acceptance Run"
  Write-RunNote -Path $notesPath -Text ""
  Write-RunNote -Path $notesPath -Text "Generated: $((Get-Date).ToString("o"))"
  Write-RunNote -Path $notesPath -Text "Gate: $Gate"
  Write-RunNote -Path $notesPath -Text "Host console: $hostConsole"
  if ($runCardHtml) {
    Write-RunNote -Path $notesPath -Text "Run card HTML: $runCardHtml"
  }
  if ($runCardMarkdown) {
    Write-RunNote -Path $notesPath -Text "Run card Markdown: $runCardMarkdown"
  }
  Write-RunNote -Path $notesPath -Text "Doctor status: $($doctor.status)"
  Write-RunNote -Path $notesPath -Text "Doctor report: $($doctor.reportMarkdownPath)"
  Write-RunNote -Path $notesPath -Text "Pre-report: $($pre.markdownPath)"
  Write-RunNote -Path $notesPath -Text "Firewall ready: $($firewall.ready)"
  Write-RunNote -Path $notesPath -Text "Current PIN: $(if ($shortLivedPin.available) { $shortLivedPin.pin } else { "Unavailable" })"
  Write-RunNote -Path $notesPath -Text "PIN status: $(if ($shortLivedPin.available) { "refreshed $($shortLivedPin.refreshedAt), expires in about $($shortLivedPin.secondsRemaining) seconds" } else { $shortLivedPin.error })"
  Write-RunNote -Path $notesPath -Text ""
  Write-RunNote -Path $notesPath -Text "## Readiness Doctor"
  Write-RunNote -Path $notesPath -Text "- OK: $($doctor.ok)"
  Write-RunNote -Path $notesPath -Text "- Status: $($doctor.status)"
  Write-RunNote -Path $notesPath -Text "- Report: $($doctor.reportMarkdownPath)"
  Write-RunNote -Path $notesPath -Text "- JSON: $($doctor.reportJsonPath)"
  if ($doctor.failureCount -gt 0) {
    foreach ($failure in @($doctor.checks | Where-Object { $_.status -eq "fail" })) {
      Write-RunNote -Path $notesPath -Text "- [FAIL] $($failure.name) -- $($failure.detail) -- $($failure.nextAction)"
    }
  }
  if ($doctor.warningCount -gt 0) {
    foreach ($warning in @($doctor.checks | Where-Object { $_.status -eq "warn" })) {
      Write-RunNote -Path $notesPath -Text "- [WARN] $($warning.name) -- $($warning.detail) -- $($warning.nextAction)"
    }
  }
  Write-RunNote -Path $notesPath -Text ""
  Write-RunNote -Path $notesPath -Text "## Recommended Phone URLs"
  Write-RunNote -Path $notesPath -Text $phoneSelection.note
  if ($targetPhoneUrls.Count -eq 0) {
    Write-RunNote -Path $notesPath -Text "- none"
  } else {
    foreach ($url in $targetPhoneUrls) {
      Write-RunNote -Path $notesPath -Text "- $url"
    }
  }
  Write-RunNote -Path $notesPath -Text ""
  Write-RunNote -Path $notesPath -Text "## Current PIN"
  if ($shortLivedPin.available) {
    Write-RunNote -Path $notesPath -Text "- PIN: $($shortLivedPin.pin)"
    Write-RunNote -Path $notesPath -Text "- Refreshed: $($shortLivedPin.refreshedAt)"
    Write-RunNote -Path $notesPath -Text "- Expires in about $($shortLivedPin.secondsRemaining) seconds."
  } else {
    Write-RunNote -Path $notesPath -Text "- Unavailable: $($shortLivedPin.error)"
  }
  Write-RunNote -Path $notesPath -Text ""
  Write-RunNote -Path $notesPath -Text "## Run Card And QR"
  Write-RunNote -Path $notesPath -Text "- Run card HTML: $(if ($runCardHtml) { $runCardHtml } else { "not available" })"
  Write-RunNote -Path $notesPath -Text "- Run card Markdown: $(if ($runCardMarkdown) { $runCardMarkdown } else { "not available" })"
  if ($qrCodes.Count -eq 0) {
    Write-RunNote -Path $notesPath -Text "- QR: not available"
  } else {
    foreach ($qr in $qrCodes) {
      Write-RunNote -Path $notesPath -Text "- QR: $($qr.path) -> $($qr.url)"
    }
  }
  Write-RunNote -Path $notesPath -Text ""
  Write-RunNote -Path $notesPath -Text "## Secondary Phone URLs"
  if ($secondaryPhoneUrls.Count -eq 0) {
    Write-RunNote -Path $notesPath -Text "- none"
  } else {
    foreach ($url in $secondaryPhoneUrls) {
      Write-RunNote -Path $notesPath -Text "- $url"
    }
  }
  Write-RunNote -Path $notesPath -Text ""
  Write-RunNote -Path $notesPath -Text "## All Advertised Phone URLs"
  foreach ($address in $addresses) {
    Write-RunNote -Path $notesPath -Text "- $address"
  }
  Write-RunNote -Path $notesPath -Text ""
  Write-RunNote -Path $notesPath -Text "## Gate-Aware Proof URLs"
  foreach ($url in $phoneUrls) {
    Write-RunNote -Path $notesPath -Text "- $url"
  }
  Write-RunNote -Path $notesPath -Text ""
  Write-RunNote -Path $notesPath -Text "## Firewall"
  Write-RunNote -Path $notesPath -Text "- Ready: $($firewall.ready)"
  Write-RunNote -Path $notesPath -Text "- Rule: $($firewall.ruleName)"
  Write-RunNote -Path $notesPath -Text "- Port: $($firewall.port)"
  if ($firewall.error) {
    Write-RunNote -Path $notesPath -Text "- Error: $($firewall.error)"
  }
  if (-not $firewall.ready) {
    Write-RunNote -Path $notesPath -Text "- Suggested fix: run npm run firewall:handoff first, then run the copied elevated install command only if you choose to allow inbound TCP $($firewall.port); retry the guided phone acceptance run afterward."
  }
  Write-RunNote -Path $notesPath -Text ""
  Write-RunNote -Path $notesPath -Text "## Preflight"
  if ($preflight.Count -eq 0) {
    Write-RunNote -Path $notesPath -Text "- [FAIL] No $targetKind phone URL was advertised by the host."
  } else {
    foreach ($check in $preflight) {
      $status = if ($check.ok) { "PASS" } else { "FAIL" }
      $detail = if ($check.ok) { "HTTP $($check.statusCode)" } else { "$($check.error)" }
      Write-RunNote -Path $notesPath -Text "- [$status] $($check.healthUrl) -- $detail"
    }
  }
  Write-RunNote -Path $notesPath -Text ""
  Write-RunNote -Path $notesPath -Text "## Pre-Run Blockers"
  if ($preRunBlockers.Count -eq 0) {
    Write-RunNote -Path $notesPath -Text "- none"
  } else {
    foreach ($blocker in $preRunBlockers) {
      Write-RunNote -Path $notesPath -Text "- [BLOCKER] $($blocker.name) -- $($blocker.detail) -- $($blocker.nextAction)"
    }
  }
  Write-RunNote -Path $notesPath -Text ""
  Write-RunNote -Path $notesPath -Text "## Step Results"

  Write-Host ""
  Write-Host "Manual phone acceptance runner"
  Write-Host "Gate: $Gate"
  Write-Host "Host console: $hostConsole"
  if ($runCardHtml) {
    Write-Host "Run card: $runCardHtml"
  }
  if ($qrCodes.Count -gt 0) {
    Write-Host "QR files:"
    foreach ($qr in $qrCodes) {
      Write-Host "  $($qr.path)"
    }
  }
  Write-Host "Doctor status: $($doctor.status)"
  Write-Host "Doctor report: $($doctor.reportMarkdownPath)"
  Write-Host "Pre-report: $($pre.markdownPath)"
  Write-Host "Firewall ready: $($firewall.ready)"
  if ($shortLivedPin.available) {
    Write-Host "Current PIN: $($shortLivedPin.pin) (expires in about $($shortLivedPin.secondsRemaining) seconds)"
  } else {
    Write-Host "Current PIN: unavailable ($($shortLivedPin.error))"
  }
  if (-not $firewall.ready) {
    Write-Host "Firewall rule not ready. If the phone cannot connect, run npm run firewall:handoff first; then run the copied elevated install command only if you choose to allow inbound TCP $($firewall.port)."
  }
  if ($preRunBlockers.Count -gt 0) {
    Write-Host ""
    Write-Host "Pre-run blockers:"
    foreach ($blocker in $preRunBlockers) {
      Write-Host "  $($blocker.name): $($blocker.detail)"
      if ($blocker.nextAction) {
        Write-Host "    Next: $($blocker.nextAction)"
      }
    }
  }
  Write-Host ""
  Write-Host "Open the recommended phone URL for this gate:"
  if ($targetPhoneUrls.Count -eq 0) {
    Write-Host "  No $targetKind URL is currently advertised."
  } else {
    foreach ($url in $targetPhoneUrls) {
      Write-Host "  $url"
    }
  }
  Write-Host "Selection note: $($phoneSelection.note)"
  if ($secondaryPhoneUrls.Count -gt 0) {
    Write-Host ""
    Write-Host "Secondary phone URLs:"
    foreach ($url in $secondaryPhoneUrls) {
      Write-Host "  $url"
    }
  }
  Write-Host ""
  Write-Host "All advertised phone URLs:"
  foreach ($url in $phoneUrls) {
    Write-Host "  $url"
  }
  Write-Host ""
  Write-Host "Selected gate preflight target URLs:"
  if ($targetPhoneUrls.Count -eq 0) {
    Write-Host "  No $targetKind URL is currently advertised."
  } else {
    foreach ($url in $targetPhoneUrls) {
      Write-Host "  $url"
    }
  }
  Write-Host ""
  Write-Host "Host-side URL preflight:"
  if ($preflight.Count -eq 0) {
    Write-Host "  FAIL No $targetKind URL to test."
  } else {
    foreach ($check in $preflight) {
      $status = if ($check.ok) { "PASS" } else { "FAIL" }
      Write-Host "  $status $($check.healthUrl)"
    }
  }
  Write-Host ""

  if ($RequireReady -and $preRunBlockers.Count -gt 0) {
    $summary = [ordered]@{
      ok = $false
      generatedAt = (Get-Date).ToString("o")
      gate = $Gate
      preRunBlocked = $true
      preRunBlockers = $preRunBlockers
      shortLivedPin = $shortLivedPin
      hostConsole = $hostConsole
      runCardHtml = $runCardHtml
      runCardMarkdown = $runCardMarkdown
      qrCodes = @($qrCodes)
      phoneUrls = $phoneUrls
      targetKind = $targetKind
      targetPhoneUrls = $targetPhoneUrls
      preflight = $preflight
      firewall = $firewall
      doctor = $doctor
      doctorReportJson = $doctor.reportJsonPath
      doctorReportMarkdown = $doctor.reportMarkdownPath
      notesPath = $notesPath
      summaryPath = $summaryPath
      preReport = $pre.markdownPath
      preJson = $pre.jsonPath
      passed = 0
      failed = 0
      skipped = 0
      results = @()
    }
    Write-RunNote -Path $notesPath -Text "RequireReady stopped before manual step collection because pre-run blockers are present."
    $summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    [pscustomobject]$summary | ConvertTo-Json -Compress
    exit 1
  }

  Write-Host "For each step, enter y, n, or s. Add detail when something fails."
  Write-Host ""

  $results = @()
  foreach ($item in $checklist) {
    Write-Host "STEP: $item"
    $answer = Read-ChecklistAnswer
    $detail = ""
    if ($answer -ne "y") {
      $detail = Read-Host "Detail"
    }
    $status = if ($answer -eq "y") { "PASS" } elseif ($answer -eq "n") { "FAIL" } else { "SKIP" }
    $results += [pscustomobject]@{ step = $item; status = $status; detail = $detail }
    $resultLine = "- [$status] $item"
    if ($detail) { $resultLine = "$resultLine -- $detail" }
    Write-RunNote -Path $notesPath -Text $resultLine
    Write-Host ""
  }

  $overallNotes = Read-Host "Final notes for this run"
  Write-RunNote -Path $notesPath -Text ""
  Write-RunNote -Path $notesPath -Text "## Final Notes"
  Write-RunNote -Path $notesPath -Text $overallNotes

  $post = Invoke-AcceptanceReport -SelectedGate $Gate -SelectedPhase "post" -BaseUrl $baseUrl
  Write-RunNote -Path $notesPath -Text ""
  Write-RunNote -Path $notesPath -Text "## Post Evidence"
  Write-RunNote -Path $notesPath -Text "- Post-report: $($post.markdownPath)"
  Write-RunNote -Path $notesPath -Text "- Post JSON: $($post.jsonPath)"
  Write-RunNote -Path $notesPath -Text "- Host logs: $(if ($post.hostLogsPath) { $post.hostLogsPath } else { "not saved" })"

  $passedCount = @($results | Where-Object { $_.status -eq "PASS" }).Count
  $failedCount = @($results | Where-Object { $_.status -eq "FAIL" }).Count
  $skippedCount = @($results | Where-Object { $_.status -eq "SKIP" }).Count
  $manualStepsOk = ($passedCount -eq $checklist.Count) -and ($failedCount -eq 0) -and ($skippedCount -eq 0)
  $postEvidenceOk = (-not [string]::IsNullOrWhiteSpace("$($post.jsonPath)")) -and (-not [string]::IsNullOrWhiteSpace("$($post.hostLogsPath)"))

  $summary = [ordered]@{
    ok = $false
    generatedAt = (Get-Date).ToString("o")
    gate = $Gate
    hostConsole = $hostConsole
    runCardHtml = $runCardHtml
    runCardMarkdown = $runCardMarkdown
    qrCodes = @($qrCodes)
    shortLivedPin = $shortLivedPin
    readyStatusPath = if ($latestReady -and $latestReady.latestReadyStatusPath) { "$($latestReady.latestReadyStatusPath)" } else { "" }
    readyCheckedAt = if ($latestReady -and $latestReady.checkedAt) { "$($latestReady.checkedAt)" } else { "" }
    doNotRefreshAfterProof = $true
    finalizerCommand = "npm run acceptance:finalize"
    phoneUrls = $phoneUrls
    rawPhoneUrls = $rawPhoneUrls
    targetKind = $targetKind
    targetPhoneUrls = $targetPhoneUrls
    rawTargetPhoneUrls = $rawTargetPhoneUrls
    secondaryPhoneUrls = $secondaryPhoneUrls
    phoneUrlSelectionNote = $phoneSelection.note
    preRunBlockers = $preRunBlockers
    preRunBlocked = $false
    preflight = $preflight
    firewall = $firewall
    doctor = $doctor
    doctorReportJson = $doctor.reportJsonPath
    doctorReportMarkdown = $doctor.reportMarkdownPath
    notesPath = $notesPath
    summaryPath = $summaryPath
    preReport = $pre.markdownPath
    preJson = $pre.jsonPath
    postReport = $post.markdownPath
    postJson = $post.jsonPath
    postHostLogs = $post.hostLogsPath
    results = $results
    passed = $passedCount
    failed = $failedCount
    skipped = $skippedCount
    expectedSteps = $checklist.Count
    manualStepsOk = $manualStepsOk
    postEvidenceOk = $postEvidenceOk
    summaryOkRequiresVerifier = $true
  }

  $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
  if (-not $SkipVerifyAfter) {
    $verification = Invoke-AcceptanceVerifier -SelectedGate $Gate -SelectedSummaryPath $summaryPath
    $verificationResult = $verification.result
    $failedChecks = @()
    if ($verificationResult -and $verificationResult.checks) {
      $failedChecks = @($verificationResult.checks | Where-Object { $_.passed -eq $false })
    }

    Write-RunNote -Path $notesPath -Text ""
    Write-RunNote -Path $notesPath -Text "## Saved Verification"
    Write-RunNote -Path $notesPath -Text "- OK: $($verification.ok)"
    Write-RunNote -Path $notesPath -Text "- Exit code: $($verification.exitCode)"
    if ($verificationResult -and $verificationResult.verificationJsonPath) {
      Write-RunNote -Path $notesPath -Text "- Verification JSON: $($verificationResult.verificationJsonPath)"
      Write-RunNote -Path $notesPath -Text "- Latest verification JSON: $($verificationResult.latestVerificationJsonPath)"
    }
    if ($failedChecks.Count -gt 0) {
      foreach ($check in $failedChecks) {
        Write-RunNote -Path $notesPath -Text "- [FAIL] $($check.name) -- $($check.detail)"
      }
    }

    $summary["verificationOk"] = [bool]$verification.ok
    $summary["verificationExitCode"] = $verification.exitCode
    $summary["verification"] = $verificationResult
    $summary["verificationRaw"] = if ($verificationResult) { @() } else { $verification.raw }
    $summary["savedVerificationPath"] = if ($verificationResult -and $verificationResult.verificationJsonPath) { "$($verificationResult.verificationJsonPath)" } else { "" }
    $summary["latestVerificationPath"] = if ($verificationResult -and $verificationResult.latestVerificationJsonPath) { "$($verificationResult.latestVerificationJsonPath)" } else { "" }
    $summary["ok"] = $manualStepsOk -and $postEvidenceOk -and [bool]$verification.ok
    $summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
  } else {
    $summary["verificationSkipped"] = $true
    $summary["ok"] = $false
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
  }
  [pscustomobject]$summary | ConvertTo-Json -Compress
} finally {
  if ($started -and -not $started.HasExited) {
    Stop-Process -Id $started.Id -Force
  }
}
