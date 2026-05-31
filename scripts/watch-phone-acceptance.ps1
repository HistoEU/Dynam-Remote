param(
  [ValidateSet("same-wifi", "tailscale")]
  [string]$Gate = "same-wifi",
  [string]$HostKey = "dev-host-key",
  [string]$OutputDir = "output\acceptance",
  [int]$TimeoutSeconds = 900,
  [int]$PollSeconds = 5,
  [switch]$Once,
  [switch]$Save,
  [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$ResolvedOutputDir = Join-Path $Root $OutputDir
$Verifier = Join-Path $PSScriptRoot "verify-phone-acceptance.ps1"
$PrepareScript = Join-Path $PSScriptRoot "prepare-phone-acceptance.ps1"

function Resolve-ArtifactPath {
  param([string]$PathValue)
  if (-not $PathValue) { return "" }
  if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
  return Join-Path $Root $PathValue
}

function Read-JsonFile {
  param([string]$PathValue)
  if (-not $PathValue -or -not (Test-Path -LiteralPath $PathValue)) { return $null }
  return Get-Content -Raw -LiteralPath $PathValue | ConvertFrom-Json
}

function Get-LatestReadyPath {
  param([string]$SelectedGate)

  $latest = Join-Path $ResolvedOutputDir "phone-acceptance-ready-$SelectedGate-latest.json"
  if (Test-Path -LiteralPath $latest) { return $latest }
  return ""
}

function ConvertTo-StringArray {
  param([object]$Values)
  if ($null -eq $Values) { return @() }
  return @($Values | Where-Object { $null -ne $_ } | ForEach-Object { "$_" })
}

function Write-WatchMarkdown {
  param(
    [object]$Snapshot,
    [string]$Path
  )

  $phoneRows = if ($Snapshot.phoneUrls -and @($Snapshot.phoneUrls).Count -gt 0) {
    (@($Snapshot.phoneUrls) | ForEach-Object { "- $_" }) -join [Environment]::NewLine
  } else {
    "- none"
  }
  $secondaryRows = if ($Snapshot.secondaryPhoneUrls -and @($Snapshot.secondaryPhoneUrls).Count -gt 0) {
    (@($Snapshot.secondaryPhoneUrls) | ForEach-Object { "- $_" }) -join [Environment]::NewLine
  } else {
    "- none"
  }
  $failedRows = if ($Snapshot.failedChecks -and @($Snapshot.failedChecks).Count -gt 0) {
    (@($Snapshot.failedChecks) | ForEach-Object {
      $next = if (-not [string]::IsNullOrWhiteSpace("$($_.nextAction)")) { " Next: $($_.nextAction)" } else { "" }
      "- $($_.name): $($_.detail)$next"
    }) -join [Environment]::NewLine
  } else {
    "- none"
  }
  $proof = $Snapshot.hostPhoneProof
  $hostHealth = $Snapshot.hostHealth
  $markdown = @"
# Phone Acceptance Watch

Generated: $($Snapshot.checkedAt)
Gate: $($Snapshot.gate)
Verifier OK: $($Snapshot.ok)
Readiness: $($Snapshot.readinessStatus)
Setup blockers: $($Snapshot.setupBlockerCount)
Physical blockers: $($Snapshot.physicalBlockerCount)

## Current Phone Proof Seen By Host

- Present: $($proof.present)
- Gate: $($proof.gate)
- Origin: $($proof.origin)
- Checklist: $($proof.checklistPassed) / $($proof.checklistRequired)
- Checklist complete: $($proof.checklistComplete)
- Monitor: $($proof.monitor)
- Frame: $($proof.frameId)
- Viewport: $($proof.viewport)
- Detail: $($proof.detail)

## Host

- Reachable: $($hostHealth.reachable)
- Mode: $($hostHealth.appMode)
- Same-Wi-Fi: $($hostHealth.sameWifiStatus)
- Tailscale: $($hostHealth.tailscaleStatus)

## Phone URLs

Primary: $($Snapshot.primaryPhoneUrl)

$phoneRows

Secondary:

$secondaryRows

## Operator Files

- Run card HTML: $($Snapshot.runCardHtml)
- Run card Markdown: $($Snapshot.runCardMarkdown)
- Latest manual summary: $($Snapshot.latestManualSummaryPath)
- Ready JSON: $($Snapshot.readyPath)

## Current Failed Verifier Checks

$failedRows

## Commands

~~~powershell
$($Snapshot.nextCommand)
npm run acceptance:verify:save -- -Gate $($Snapshot.gate)
npm run acceptance:finalize
~~~

Do not run ``npm run acceptance:refresh`` after both gates pass; use ``npm run acceptance:finalize`` so new readiness artifacts do not make the proof stale.
"@

  $markdown | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Save-WatchSnapshot {
  param(
    [string]$SelectedGate,
    [object]$Snapshot
  )

  New-Item -ItemType Directory -Path $ResolvedOutputDir -Force | Out-Null
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $path = Join-Path $ResolvedOutputDir "phone-acceptance-watch-$SelectedGate-$timestamp.json"
  $latestPath = Join-Path $ResolvedOutputDir "phone-acceptance-watch-$SelectedGate-latest.json"
  $markdownPath = Join-Path $ResolvedOutputDir "phone-acceptance-watch-$SelectedGate-$timestamp.md"
  $latestMarkdownPath = Join-Path $ResolvedOutputDir "phone-acceptance-watch-$SelectedGate-latest.md"
  $Snapshot | Add-Member -NotePropertyName watchJsonPath -NotePropertyValue $path -Force
  $Snapshot | Add-Member -NotePropertyName latestWatchJsonPath -NotePropertyValue $latestPath -Force
  $Snapshot | Add-Member -NotePropertyName watchMarkdownPath -NotePropertyValue $markdownPath -Force
  $Snapshot | Add-Member -NotePropertyName latestWatchMarkdownPath -NotePropertyValue $latestMarkdownPath -Force
  $Snapshot | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding UTF8
  $Snapshot | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $latestPath -Encoding UTF8
  Write-WatchMarkdown -Snapshot $Snapshot -Path $markdownPath
  Write-WatchMarkdown -Snapshot $Snapshot -Path $latestMarkdownPath
}

function Get-LatestPreparedSessionPath {
  param([string]$SelectedGate)

  $latest = Join-Path $ResolvedOutputDir "phone-acceptance-session-$SelectedGate-latest.json"
  if (Test-Path -LiteralPath $latest) { return $latest }

  $file = Get-ChildItem -LiteralPath $ResolvedOutputDir -Filter "phone-acceptance-session-$SelectedGate-*.json" -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike "*-latest.json" } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if ($file) { return $file.FullName }
  return ""
}

function Get-LatestManualSummaryPath {
  param([string]$SelectedGate)

  $file = Get-ChildItem -LiteralPath $ResolvedOutputDir -Filter "manual-phone-run-$SelectedGate-*.json" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if ($file) { return $file.FullName }
  return ""
}

function Invoke-Verifier {
  param([string]$SelectedGate)

  $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $Verifier -Gate $SelectedGate -OutputDir $OutputDir 2>&1
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

function Get-FailedVerifierChecks {
  param([object]$VerifierResult)

  $result = $VerifierResult.result
  if ($result -and $result.checks) {
    return @($result.checks | Where-Object { $_.passed -eq $false } | ForEach-Object {
      [pscustomobject]@{
        name = "$($_.name)"
        detail = "$($_.detail)"
        nextAction = "$($_.nextAction)"
      }
    })
  }

  if ($result -and $result.error) {
    return @([pscustomobject]@{
      name = "verifier error"
      detail = "$($result.error)"
      nextAction = "Open the latest verifier JSON, fix the verifier error, then rerun npm run acceptance:watch -- -Gate $Gate -Once -Save."
    })
  }

  return @([pscustomobject]@{
    name = "verifier output"
    detail = (($VerifierResult.raw -join " ") -replace "\s+", " ").Trim()
    nextAction = "Rerun npm run acceptance:watch -- -Gate $Gate -Once -Save and inspect the raw verifier output if this repeats."
  })
}

function Get-HostHealth {
  param([int]$Port)

  try {
    $health = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/api/health" -TimeoutSec 3
    return [pscustomobject]@{
      reachable = $true
      appMode = "$($health.state.app.mode)"
      sameWifiStatus = "$($health.state.connectionSetup.sameWifi.status)"
      tailscaleStatus = "$($health.state.connectionSetup.tailscale.status)"
    }
  } catch {
    return [pscustomobject]@{
      reachable = $false
      error = $_.Exception.Message
    }
  }
}

function Get-LatestHostPhoneProof {
  param([int]$Port)

  try {
    $state = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/api/host?key=$([uri]::EscapeDataString($HostKey))" -TimeoutSec 3
    $proofLog = @($state.logs | Where-Object { $_.event -eq "acceptance.phoneMark" } | Select-Object -First 1)
    if (-not $proofLog) {
      return [pscustomobject]@{
        present = $false
        gate = ""
        origin = ""
        checklistComplete = $false
        checklistPassed = 0
        checklistRequired = 0
        monitor = ""
        frameId = 0
        detail = "No acceptance.phoneMark event is visible in the current host log window."
      }
    }

    $proof = $proofLog.detail.proof
    $checklist = $proof.checklist
    return [pscustomobject]@{
      present = $true
      loggedAt = if ($proofLog.at) { "$($proofLog.at)" } else { "" }
      gate = "$($proof.gate)"
      origin = "$($proof.urlOrigin)"
      checklistComplete = $checklist -and $checklist.complete -eq $true
      checklistPassed = if ($checklist -and $null -ne $checklist.passedCount) { [int]$checklist.passedCount } else { 0 }
      checklistRequired = if ($checklist -and $null -ne $checklist.requiredCount) { [int]$checklist.requiredCount } else { 0 }
      monitor = "$($proof.diagnostics.monitor)"
      frameId = if ($proof.diagnostics -and $null -ne $proof.diagnostics.frameId) { [int]$proof.diagnostics.frameId } else { 0 }
      viewport = if ($proof.viewport) { "$($proof.viewport.width)x$($proof.viewport.height)" } else { "" }
      detail = "Latest phone proof marker is $($proof.gate) from $($proof.urlOrigin); checklist $($checklist.passedCount)/$($checklist.requiredCount)."
    }
  } catch {
    return [pscustomobject]@{
      present = $false
      gate = ""
      origin = ""
      checklistComplete = $false
      checklistPassed = 0
      checklistRequired = 0
      monitor = ""
      frameId = 0
      detail = "Could not read current host proof logs: $($_.Exception.Message)"
    }
  }
}

function New-WatchSnapshot {
  param([string]$SelectedGate)

  $preparedPath = Get-LatestPreparedSessionPath -SelectedGate $SelectedGate
  $prepared = Read-JsonFile -PathValue $preparedPath
  $readyPath = Get-LatestReadyPath -SelectedGate $SelectedGate
  $ready = Read-JsonFile -PathValue $readyPath
  $summaryPath = Get-LatestManualSummaryPath -SelectedGate $SelectedGate
  $verification = Invoke-Verifier -SelectedGate $SelectedGate
  $port = if ($prepared -and $prepared.port) { [int]$prepared.port } else { 4317 }
  $health = Get-HostHealth -Port $port
  $hostPhoneProof = Get-LatestHostPhoneProof -Port $port
  $verifierFailedCount = if ($verification.result -and $verification.result.checks) {
    @($verification.result.checks | Where-Object { $_.passed -eq $false }).Count
  } elseif ($verification.ok) {
    0
  } else {
    1
  }
  $readyPhysicalBlockers = if ($ready -and $null -ne $ready.physicalBlockerCount) { [int]$ready.physicalBlockerCount } else { 0 }
  $readyPhoneUrls = if ($ready) { @(ConvertTo-StringArray $ready.phoneUrls) } else { @() }
  $preparedPhoneUrls = if ($prepared) { @(ConvertTo-StringArray $prepared.phoneUrls) } else { @() }
  $phoneUrls = if ($readyPhoneUrls.Count -gt 0) { $readyPhoneUrls } else { $preparedPhoneUrls }
  $primaryPhoneUrl = if ($ready -and -not [string]::IsNullOrWhiteSpace("$($ready.primaryPhoneUrl)")) {
    "$($ready.primaryPhoneUrl)"
  } elseif ($phoneUrls.Count -gt 0) {
    "$($phoneUrls[0])"
  } else {
    ""
  }

  return [pscustomobject]@{
    ok = $verification.ok
    gate = $SelectedGate
    checkedAt = (Get-Date).ToString("o")
    readinessStatus = if ($ready -and $ready.status) { "$($ready.status)" } elseif ($prepared) { "prepared" } else { "needs-readiness" }
    readyPath = $readyPath
    primaryPhoneUrl = $primaryPhoneUrl
    setupBlockerCount = if ($ready -and $null -ne $ready.setupBlockerCount) { [int]$ready.setupBlockerCount } else { 0 }
    physicalBlockerCount = [Math]::Max($readyPhysicalBlockers, $verifierFailedCount)
    preparedSessionPath = $preparedPath
    prepared = [bool]$prepared
    hostHealth = $health
    hostPhoneProof = $hostPhoneProof
    runCardHtml = if ($prepared) { Resolve-ArtifactPath "$($prepared.runCardHtml)" } else { "" }
    runCardMarkdown = if ($prepared) { Resolve-ArtifactPath "$($prepared.runCardMarkdown)" } else { "" }
    phoneUrls = [string[]]$phoneUrls
    secondaryPhoneUrls = [string[]]$(if ($prepared) { @(ConvertTo-StringArray $prepared.secondaryPhoneUrls) } else { @() })
    nextCommand = if ($prepared) { "$($prepared.nextCommand)" } else { "npm run acceptance:prepare -- -Gate $SelectedGate" }
    stopCommand = if ($prepared) { "$($prepared.stopCommand)" } else { "npm run acceptance:stop -- -Gate $SelectedGate" }
    latestManualSummaryPath = $summaryPath
    verifierExitCode = $verification.exitCode
    failedChecks = @(Get-FailedVerifierChecks -VerifierResult $verification)
  }
}

if ($SelfTest) {
  $verifierSelfTestRaw = & powershell -NoProfile -ExecutionPolicy Bypass -File $Verifier -SelfTest
  $verifierSelfTest = ($verifierSelfTestRaw | Where-Object { "$_".Trim().StartsWith("{") } | Select-Object -Last 1) | ConvertFrom-Json
  $tempMarkdown = Join-Path ([System.IO.Path]::GetTempPath()) "remote-watch-selftest-$([guid]::NewGuid().ToString('N')).md"
  $markdownWritten = $false
  try {
    Write-WatchMarkdown -Path $tempMarkdown -Snapshot ([pscustomobject]@{
      checkedAt = (Get-Date).ToString("o")
      gate = $Gate
      ok = $false
      readinessStatus = "ready-for-phone"
      setupBlockerCount = 0
      physicalBlockerCount = 3
      hostPhoneProof = [pscustomobject]@{ present = $false; gate = ""; origin = ""; checklistPassed = 0; checklistRequired = 0; checklistComplete = $false; monitor = ""; frameId = 0; viewport = ""; detail = "No acceptance.phoneMark event is visible." }
      hostHealth = [pscustomobject]@{ reachable = $true; appMode = "milestone-2-screen-capture"; sameWifiStatus = "ready"; tailscaleStatus = "ready" }
      primaryPhoneUrl = "http://192.168.1.10:4317?acceptance=1&gate=$Gate&step=physical-phone-proof"
      phoneUrls = @("http://192.168.1.10:4317?acceptance=1&gate=$Gate&step=physical-phone-proof")
      secondaryPhoneUrls = @()
      runCardHtml = "C:\fake\run-card.html"
      runCardMarkdown = "C:\fake\run-card.md"
      latestManualSummaryPath = ""
      readyPath = "C:\fake\ready.json"
      failedChecks = @([pscustomobject]@{ name = "phone proof log exists"; detail = "event=acceptance.phoneMark"; nextAction = "Open the proof URL on the phone, finish the checklist, and tap Mark Proof." })
      nextCommand = "npm run acceptance:phone -- -Gate $Gate -SkipStart -RequireReady"
    })
    $markdownText = if (Test-Path -LiteralPath $tempMarkdown) { Get-Content -Raw -LiteralPath $tempMarkdown } else { "" }
    $markdownWritten = ($markdownText -match "Phone Acceptance Watch") -and ($markdownText -match "Next: Open the proof URL")
  } finally {
    Remove-Item -LiteralPath $tempMarkdown -Force -ErrorAction SilentlyContinue
  }
  $ok = (Test-Path -LiteralPath $Verifier) -and (Test-Path -LiteralPath $PrepareScript) -and $verifierSelfTest.ok -eq $true -and $markdownWritten
  [pscustomobject]@{
    ok = $ok
    gate = $Gate
    verifierExists = Test-Path -LiteralPath $Verifier
    prepareExists = Test-Path -LiteralPath $PrepareScript
    verifierSelfTestOk = $verifierSelfTest.ok
    defaultTimeoutSeconds = $TimeoutSeconds
    defaultPollSeconds = $PollSeconds
    supportsSave = $true
    includesReadinessStatus = $true
    includesPrimaryPhoneUrl = $true
    includesHostPhoneProofSummary = $true
    writesMarkdownReport = $markdownWritten
  } | ConvertTo-Json -Compress
  if (-not $ok) { exit 1 }
  exit 0
}

if ($PollSeconds -lt 1) { $PollSeconds = 1 }
if ($TimeoutSeconds -lt 0) { $TimeoutSeconds = 0 }

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$lastSnapshot = $null
do {
  $lastSnapshot = New-WatchSnapshot -SelectedGate $Gate
  if ($lastSnapshot.ok) {
    if ($Save) { Save-WatchSnapshot -SelectedGate $Gate -Snapshot $lastSnapshot }
    $lastSnapshot | ConvertTo-Json -Depth 8 -Compress
    exit 0
  }

  if ($Once -or (Get-Date) -ge $deadline) { break }
  $failedNames = (@($lastSnapshot.failedChecks) | Select-Object -First 3 | ForEach-Object { $_.name }) -join ", "
  Write-Host "Waiting for $Gate phone evidence. Current blockers: $failedNames"
  Start-Sleep -Seconds $PollSeconds
} while ($true)

if ($Save) { Save-WatchSnapshot -SelectedGate $Gate -Snapshot $lastSnapshot }
$lastSnapshot | ConvertTo-Json -Depth 8 -Compress
exit 1
