param(
  [ValidateSet("same-wifi", "tailscale")]
  [string]$Gate = "same-wifi",
  [string]$OutputDir = "output\acceptance",
  [switch]$NoOpen,
  [switch]$NoClipboard,
  [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$ResolvedOutputDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $Root $OutputDir }

function Read-JsonFile {
  param([string]$PathValue)
  if (-not $PathValue -or -not (Test-Path -LiteralPath $PathValue -PathType Leaf)) { return $null }
  try {
    return Get-Content -Raw -LiteralPath $PathValue | ConvertFrom-Json
  } catch {
    return $null
  }
}

function Get-GateRecord {
  param(
    [object]$Runbook,
    [string]$SelectedGate
  )
  if (-not $Runbook -or -not $Runbook.gates) { return $null }
  return @($Runbook.gates | Where-Object { "$($_.gate)" -eq $SelectedGate } | Select-Object -First 1)
}

function ConvertTo-StringArray {
  param([object]$Value)
  if ($null -eq $Value) { return @() }
  if ($Value -is [string]) { return @($Value) }
  return @($Value | ForEach-Object { "$_" })
}

function Get-FirstUrl {
  param([string[]]$Values)
  foreach ($value in @($Values)) {
    if ([string]::IsNullOrWhiteSpace($value)) { continue }
    $match = [regex]::Match($value, "https?://[^\s,;`"')]+")
    if ($match.Success) { return $match.Value.TrimEnd(".") }
  }
  return ""
}

function Get-SetupUrl {
  param([object]$GateRecord)
  if (-not $GateRecord) { return "" }
  $candidates = [System.Collections.Generic.List[string]]::new()
  foreach ($action in @(ConvertTo-StringArray $GateRecord.actions)) {
    $candidates.Add($action) | Out-Null
  }
  foreach ($check in @($GateRecord.failedChecks)) {
    if ($check.nextAction) { $candidates.Add("$($check.nextAction)") | Out-Null }
    if ($check.detail) { $candidates.Add("$($check.detail)") | Out-Null }
  }
  foreach ($warning in @($GateRecord.warnings)) {
    if ($warning.nextAction) { $candidates.Add("$($warning.nextAction)") | Out-Null }
  }
  return Get-FirstUrl -Values @($candidates)
}

function Get-LatestReadyStatus {
  param([string]$SelectedGate)
  $path = Join-Path $ResolvedOutputDir "phone-acceptance-ready-$SelectedGate-latest.json"
  return Read-JsonFile $path
}

function Get-HostKeyFromConsoleUrl {
  param([string]$HostConsole)
  if ([string]::IsNullOrWhiteSpace($HostConsole)) { return "" }
  try {
    $uri = [uri]$HostConsole
    if ($uri.Host -notin @("127.0.0.1", "localhost", "::1")) { return "" }
    foreach ($pair in $uri.Query.TrimStart("?").Split("&", [System.StringSplitOptions]::RemoveEmptyEntries)) {
      $parts = $pair.Split("=", 2)
      $name = [uri]::UnescapeDataString($parts[0])
      if ($name -ne "key") { continue }
      if ($parts.Count -lt 2) { return "" }
      return [uri]::UnescapeDataString($parts[1].Replace("+", " "))
    }
    return ""
  } catch {
    return ""
  }
}

function Get-LocalBaseUrlFromConsoleUrl {
  param([string]$HostConsole)
  if ([string]::IsNullOrWhiteSpace($HostConsole)) { return "" }
  try {
    $uri = [uri]$HostConsole
    if ($uri.Host -notin @("127.0.0.1", "localhost", "::1")) { return "" }
    return "$($uri.Scheme)://$($uri.Authority)"
  } catch {
    return ""
  }
}

function Get-FreshGateRecordPin {
  param([object]$GateRecord)
  if (-not $GateRecord -or -not $GateRecord.currentPin) { return $null }
  $pin = $GateRecord.currentPin
  if ($pin.available -ne $true -or "$($pin.pin)" -notmatch '^[0-9]{6}$') { return $null }
  if ([string]::IsNullOrWhiteSpace("$($pin.refreshedAt)")) { return $null }
  $refreshedAt = $null
  try {
    $refreshedAt = [datetime]::Parse("$($pin.refreshedAt)")
  } catch {
    return $null
  }
  $elapsedSeconds = [math]::Max(0, [int]((Get-Date) - $refreshedAt).TotalSeconds)
  $recordedRemaining = if ($null -ne $pin.secondsRemaining) { [int]$pin.secondsRemaining } else { 0 }
  $remaining = [math]::Max(0, $recordedRemaining - $elapsedSeconds)
  if ($remaining -lt 45) { return $null }
  return [pscustomobject]@{
    available = $true
    pin = "$($pin.pin)"
    secondsRemaining = $remaining
    refreshedAt = "$($pin.refreshedAt)"
    source = if ([string]::IsNullOrWhiteSpace("$($pin.source)")) { "runbook-current" } else { "$($pin.source)" }
    hostConsole = if (-not [string]::IsNullOrWhiteSpace("$($pin.hostConsole)")) { "$($pin.hostConsole)" } elseif ($GateRecord.hostConsole) { "$($GateRecord.hostConsole)" } else { "" }
    error = ""
  }
}

function Get-ShortLivedPin {
  param(
    [string]$SelectedGate,
    [object]$GateRecord
  )

  $freshGatePin = Get-FreshGateRecordPin -GateRecord $GateRecord
  if ($freshGatePin) { return $freshGatePin }

  $ready = Get-LatestReadyStatus -SelectedGate $SelectedGate
  $hostConsole = if ($ready -and $ready.hostConsole) {
    "$($ready.hostConsole)"
  } elseif ($GateRecord -and $GateRecord.hostConsole) {
    "$($GateRecord.hostConsole)"
  } else {
    ""
  }
  $hostKey = Get-HostKeyFromConsoleUrl -HostConsole $hostConsole
  $baseUrl = Get-LocalBaseUrlFromConsoleUrl -HostConsole $hostConsole
  if ([string]::IsNullOrWhiteSpace($hostKey)) {
    return [pscustomobject]@{
      available = $false
      pin = ""
      secondsRemaining = 0
      refreshedAt = ""
      source = "unavailable"
      hostConsole = $hostConsole
      error = "No local host key was available from the latest readiness artifact."
    }
  }
  if ([string]::IsNullOrWhiteSpace($baseUrl)) {
    return [pscustomobject]@{
      available = $false
      pin = ""
      secondsRemaining = 0
      refreshedAt = ""
      source = "unavailable"
      hostConsole = $hostConsole
      error = "No local host console base URL was available for PIN refresh."
    }
  }

  try {
    $pin = Invoke-RestMethod `
      -Uri "$baseUrl/api/refresh-pin" `
      -Method Post `
      -Headers @{ "x-host-key" = $hostKey } `
      -Body "{}" `
      -ContentType "application/json" `
      -TimeoutSec 6
    return [pscustomobject]@{
      available = $true
      pin = "$($pin.pin)"
      secondsRemaining = if ($null -ne $pin.secondsRemaining) { [int]$pin.secondsRemaining } else { 0 }
      refreshedAt = (Get-Date).ToString("o")
      source = "host-refresh"
      hostConsole = $hostConsole
      error = ""
    }
  } catch {
    return [pscustomobject]@{
      available = $false
      pin = ""
      secondsRemaining = 0
      refreshedAt = ""
      source = "host-refresh-failed"
      hostConsole = $hostConsole
      error = $_.Exception.Message
    }
  }
}

function Invoke-OpenTarget {
  param([string]$Target)
  if ([string]::IsNullOrWhiteSpace($Target)) { return }
  Start-Process -FilePath "explorer.exe" -ArgumentList @($Target) | Out-Null
}

function New-LaunchArtifact {
  param(
    [object]$Launch,
    [string]$SelectedOutputDir
  )

  New-Item -ItemType Directory -Path $SelectedOutputDir -Force | Out-Null
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $jsonPath = Join-Path $SelectedOutputDir "physical-proof-launch-$($Launch.gate)-$timestamp.json"
  $mdPath = Join-Path $SelectedOutputDir "physical-proof-launch-$($Launch.gate)-$timestamp.md"
  $latestJsonPath = Join-Path $SelectedOutputDir "physical-proof-launch-$($Launch.gate)-latest.json"
  $latestMdPath = Join-Path $SelectedOutputDir "physical-proof-launch-$($Launch.gate)-latest.md"
  $Launch | Add-Member -NotePropertyName launchJsonPath -NotePropertyValue $jsonPath -Force
  $Launch | Add-Member -NotePropertyName launchMarkdownPath -NotePropertyValue $mdPath -Force
  $Launch | Add-Member -NotePropertyName latestLaunchJsonPath -NotePropertyValue $latestJsonPath -Force
  $Launch | Add-Member -NotePropertyName latestLaunchMarkdownPath -NotePropertyValue $latestMdPath -Force
  $Launch | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  $Launch | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $latestJsonPath -Encoding UTF8

  $qrRows = if ($Launch.qrCodes -and @($Launch.qrCodes).Count -gt 0) {
    (@($Launch.qrCodes) | ForEach-Object { "- $($_.path) (exists=$($_.exists))" }) -join [Environment]::NewLine
  } else {
    "- none"
  }
  $openedRows = if ($Launch.openedPaths -and @($Launch.openedPaths).Count -gt 0) {
    (@($Launch.openedPaths) | ForEach-Object { "- $_" }) -join [Environment]::NewLine
  } else {
    "- none"
  }
  $actionRows = if ($Launch.actions -and @($Launch.actions).Count -gt 0) {
    $index = 1
    (@($Launch.actions) | ForEach-Object {
      $line = "$index. $_"
      $index += 1
      $line
    }) -join [Environment]::NewLine
  } else {
    "1. $($Launch.nextCommand)"
  }
  $failedRows = if ($Launch.failedChecks -and @($Launch.failedChecks).Count -gt 0) {
    (@($Launch.failedChecks) | ForEach-Object {
      $next = if (-not [string]::IsNullOrWhiteSpace("$($_.nextAction)")) { " Next: $($_.nextAction)" } else { "" }
      "- $($_.name): $($_.detail)$next"
    }) -join [Environment]::NewLine
  } else {
    "- none"
  }
  $warningRows = if ($Launch.warnings -and @($Launch.warnings).Count -gt 0) {
    (@($Launch.warnings) | ForEach-Object {
      $next = if (-not [string]::IsNullOrWhiteSpace("$($_.nextAction)")) { " Next: $($_.nextAction)" } else { "" }
      "- $($_.name): $($_.detail)$next"
    }) -join [Environment]::NewLine
  } else {
    "- none"
  }
  $copyTarget = if ($Launch.clipboardValue) { $Launch.clipboardValue } else { "" }
  $setupUrl = if ($Launch.setupUrl) { $Launch.setupUrl } else { "" }
  $pinRows = if ($Launch.currentPin -and $Launch.currentPin.available) {
    "- Host console: $($Launch.hostConsole)`n- PIN: $($Launch.currentPin.pin)`n- Source: $($Launch.currentPin.source)`n- Refreshed: $($Launch.currentPin.refreshedAt)`n- Expires in about: $($Launch.currentPin.secondsRemaining) seconds"
  } elseif ($Launch.currentPin) {
    "- Host console: $($Launch.hostConsole)`n- unavailable: $($Launch.currentPin.error)`n- Source: $($Launch.currentPin.source)"
  } else {
    "- unavailable"
  }

  $markdown = @"
# Physical Proof Launch

Generated: $($Launch.generatedAt)
Gate: $($Launch.gate)
Status: $($Launch.status)

This launch helper opens local operator artifacts and can copy the current phone URL. It does not run the phone checklist, mark proof, save verifier evidence, install software, change firewall rules, or complete the goal.

PINs are short-lived. If this card is more than about one minute old, rerun this launch command so the phone uses a fresh PIN:

~~~powershell
npm run acceptance:launch -- -Gate $($Launch.gate)
~~~

## Phone URL

$($Launch.primaryPhoneUrl)

## Current PIN

$pinRows

## Setup URL

$setupUrl

Clipboard copied: $($Launch.clipboardCopied)
Clipboard skipped: $($Launch.clipboardSkipped)
Clipboard kind: $($Launch.clipboardKind)
Clipboard value: $copyTarget

## Opened Paths

$openedRows

## QR Files

$qrRows

## Run Actions

$actionRows

## Current Blockers

$failedRows

## Warnings

$warningRows

## Next Command

~~~powershell
$($Launch.nextCommand)
~~~
"@

  $markdown | Set-Content -LiteralPath $mdPath -Encoding UTF8
  $markdown | Set-Content -LiteralPath $latestMdPath -Encoding UTF8
  return $Launch
}

function Invoke-PhysicalProofLaunch {
  param(
    [string]$SelectedGate,
    [bool]$SkipOpen,
    [bool]$SkipClipboard
  )

  $runbookPath = Join-Path $ResolvedOutputDir "physical-proof-runbook-latest.json"
  $runbookMarkdownPath = Join-Path $ResolvedOutputDir "physical-proof-runbook-latest.md"
  $runbook = Read-JsonFile $runbookPath
  $gateRecord = Get-GateRecord -Runbook $runbook -SelectedGate $SelectedGate
  if (-not $gateRecord) {
    throw "No $SelectedGate gate record found. Run npm run acceptance:runbook first."
  }

  $primaryPhoneUrl = "$($gateRecord.primaryPhoneUrl)"
  $setupUrl = if ([string]::IsNullOrWhiteSpace($primaryPhoneUrl)) { Get-SetupUrl -GateRecord $gateRecord } else { "" }
  $shortLivedPin = Get-ShortLivedPin -SelectedGate $SelectedGate -GateRecord $gateRecord
  $clipboardKind = ""
  $clipboardValue = ""
  if (-not [string]::IsNullOrWhiteSpace($primaryPhoneUrl)) {
    $clipboardKind = "phone-url"
    $clipboardValue = $primaryPhoneUrl
  } elseif (-not [string]::IsNullOrWhiteSpace($setupUrl)) {
    $clipboardKind = "setup-url"
    $clipboardValue = $setupUrl
  }

  $opened = [System.Collections.Generic.List[string]]::new()
  $openErrors = [System.Collections.Generic.List[string]]::new()
  foreach ($target in @("$($gateRecord.runCardHtml)", "$($shortLivedPin.hostConsole)", $runbookMarkdownPath)) {
    if ([string]::IsNullOrWhiteSpace($target)) { continue }
    if ($SkipOpen) { continue }
    $isUrl = "$target" -match "^https?://"
    if (-not $isUrl -and -not (Test-Path -LiteralPath $target -PathType Leaf)) {
      $openErrors.Add("Missing path: $target") | Out-Null
      continue
    }
    try {
      Invoke-OpenTarget -Target $target
      $opened.Add($target) | Out-Null
    } catch {
      $openErrors.Add("Could not open $target`: $($_.Exception.Message)") | Out-Null
    }
  }
  if (-not $SkipOpen -and [string]::IsNullOrWhiteSpace($primaryPhoneUrl) -and -not [string]::IsNullOrWhiteSpace($setupUrl)) {
    try {
      Invoke-OpenTarget -Target $setupUrl
      $opened.Add($setupUrl) | Out-Null
    } catch {
      $openErrors.Add("Could not open $setupUrl`: $($_.Exception.Message)") | Out-Null
    }
  }

  $clipboardCopied = $false
  $clipboardError = ""
  if (-not $SkipClipboard -and -not [string]::IsNullOrWhiteSpace($clipboardValue)) {
    try {
      Set-Clipboard -Value $clipboardValue
      $clipboardCopied = $true
    } catch {
      $clipboardError = "$($_.Exception.Message)"
    }
  }

  $launch = [pscustomobject]@{
    ok = $true
    generatedAt = (Get-Date).ToString("o")
    gate = $SelectedGate
    status = "$($gateRecord.status)"
    outputDir = "$ResolvedOutputDir"
    runbookJsonPath = $runbookPath
    runbookMarkdownPath = $runbookMarkdownPath
    runCardHtml = "$($gateRecord.runCardHtml)"
    hostConsole = "$($shortLivedPin.hostConsole)"
    primaryPhoneUrl = $primaryPhoneUrl
    setupUrl = $setupUrl
    shortLivedPin = $shortLivedPin
    currentPin = $shortLivedPin
    pinFreshnessWarning = "PINs are short-lived. If this launch card is more than about one minute old, rerun npm run acceptance:launch -- -Gate $SelectedGate."
    qrCodes = @($gateRecord.qrCodes)
    actions = @($gateRecord.actions)
    failedChecks = @($gateRecord.failedChecks)
    warnings = @($gateRecord.warnings)
    nextCommand = if ($SelectedGate -eq "same-wifi" -and "$($gateRecord.status)" -eq "ready-for-phone") { "npm run acceptance:phone -- -Gate same-wifi -SkipStart -RequireReady" } elseif ($SelectedGate -eq "tailscale" -and "$($gateRecord.status)" -eq "ready-for-phone") { "npm run acceptance:phone -- -Gate tailscale -SkipStart -RequireReady" } else { "npm run acceptance:ready -- -Gate $SelectedGate" }
    openedPaths = @($opened)
    openSkipped = $SkipOpen
    openErrors = @($openErrors)
    clipboardCopied = $clipboardCopied
    clipboardSkipped = $SkipClipboard
    clipboardKind = $clipboardKind
    clipboardValue = $clipboardValue
    clipboardError = $clipboardError
    doesNotReplaceVerifier = $true
    doesNotMarkPhysicalGate = $true
  }
  return New-LaunchArtifact -Launch $launch -SelectedOutputDir $ResolvedOutputDir
}

if ($SelfTest) {
  $tempOutput = Join-Path ([System.IO.Path]::GetTempPath()) "remote-physical-proof-launch-$([guid]::NewGuid().ToString('N'))"
  New-Item -ItemType Directory -Path $tempOutput -Force | Out-Null
  $oldOutput = $script:ResolvedOutputDir
  $script:ResolvedOutputDir = $tempOutput
  try {
    $runCard = Join-Path $tempOutput "same.html"
    $qr = Join-Path $tempOutput "same.svg"
    "<!doctype html><title>same</title>" | Set-Content -LiteralPath $runCard -Encoding UTF8
    $tailRunCard = Join-Path $tempOutput "tailscale.html"
    "<!doctype html><title>tailscale</title>" | Set-Content -LiteralPath $tailRunCard -Encoding UTF8
    "<svg xmlns=""http://www.w3.org/2000/svg""></svg>" | Set-Content -LiteralPath $qr -Encoding UTF8
    "runbook" | Set-Content -LiteralPath (Join-Path $tempOutput "physical-proof-runbook-latest.md") -Encoding UTF8
    [pscustomobject]@{
      ok = $true
      gates = @(
        [pscustomobject]@{
          gate = "same-wifi"
          status = "ready-for-phone"
          primaryPhoneUrl = "http://192.168.1.20:4317?acceptance=1&gate=same-wifi&step=physical-phone-proof"
          runCardHtml = $runCard
          qrCodes = @([pscustomobject]@{ url = "http://192.168.1.20:4317?acceptance=1&gate=same-wifi&step=physical-phone-proof"; path = $qr; exists = $true })
          actions = @("Open the same-Wi-Fi phone URL and run the proof checklist.")
          failedChecks = @([pscustomobject]@{ name = "phone proof log exists"; detail = "event=acceptance.phoneMark"; nextAction = "Open the same-wifi proof URL on the phone, complete the proof checklist, tap Mark Proof, then complete npm run acceptance:phone -- -Gate same-wifi -SkipStart -RequireReady." })
          warnings = @()
        },
        [pscustomobject]@{
          gate = "tailscale"
          status = "setup-needed"
          primaryPhoneUrl = ""
          runCardHtml = $tailRunCard
          qrCodes = @()
          actions = @("Open https://login.tailscale.com/a/selftest, sign in, then run npm run acceptance:ready -- -Gate tailscale.")
          failedChecks = @([pscustomobject]@{ name = "prepare: tailscale CLI"; detail = "NeedsLogin"; nextAction = "Open https://login.tailscale.com/a/selftest, sign in, then run npm run acceptance:ready -- -Gate tailscale." })
        }
      )
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempOutput "physical-proof-runbook-latest.json") -Encoding UTF8
    $launch = Invoke-PhysicalProofLaunch -SelectedGate "same-wifi" -SkipOpen $true -SkipClipboard $true
    $tailLaunch = Invoke-PhysicalProofLaunch -SelectedGate "tailscale" -SkipOpen $true -SkipClipboard $true
    $markdown = Get-Content -Raw -LiteralPath $launch.launchMarkdownPath
    $scriptText = Get-Content -Raw -LiteralPath $PSCommandPath
    $ok = $launch.ok -and
      "$($launch.primaryPhoneUrl)" -like "*gate=same-wifi*" -and
      "$($launch.nextCommand)" -eq "npm run acceptance:phone -- -Gate same-wifi -SkipStart -RequireReady" -and
      $launch.openSkipped -eq $true -and
      $launch.clipboardSkipped -eq $true -and
      $launch.doesNotReplaceVerifier -eq $true -and
      $launch.doesNotMarkPhysicalGate -eq $true -and
      @($launch.failedChecks).Count -eq 1 -and
      @($launch.qrCodes).Count -eq 1 -and
      (Test-Path -LiteralPath $launch.launchJsonPath) -and
      (Test-Path -LiteralPath $launch.launchMarkdownPath) -and
      $tailLaunch.ok -and
      $launch.shortLivedPin.available -eq $false -and
      "$($tailLaunch.setupUrl)" -eq "https://login.tailscale.com/a/selftest" -and
      "$($tailLaunch.clipboardKind)" -eq "setup-url" -and
      "$($tailLaunch.nextCommand)" -eq "npm run acceptance:ready -- -Gate tailscale" -and
      $markdown -match "does not run the phone checklist" -and
      $markdown -match "PINs are short-lived" -and
      $markdown -match "npm run acceptance:launch -- -Gate same-wifi" -and
      $markdown -match "Current PIN" -and
      $markdown -match "Current Blockers" -and
      $markdown -match "Next: Open the same-wifi proof URL" -and
      $scriptText -like "*Set-Clipboard*" -and
      $scriptText -like "*Start-Process*"
    [pscustomobject]@{
      ok = $ok
      gate = $launch.gate
      nextCommand = $launch.nextCommand
      tailscaleSetupUrl = $tailLaunch.setupUrl
      tailscaleClipboardKind = $tailLaunch.clipboardKind
      writesJsonAndMarkdown = (Test-Path -LiteralPath $launch.launchJsonPath) -and (Test-Path -LiteralPath $launch.launchMarkdownPath)
      clipboardSkipped = $launch.clipboardSkipped
      openSkipped = $launch.openSkipped
    } | ConvertTo-Json -Compress
    if (-not $ok) { exit 1 }
    exit 0
  } finally {
    $script:ResolvedOutputDir = $oldOutput
  }
}

$result = Invoke-PhysicalProofLaunch -SelectedGate $Gate -SkipOpen ([bool]$NoOpen) -SkipClipboard ([bool]$NoClipboard)
$result | ConvertTo-Json -Depth 8 -Compress
