param(
  [ValidateSet("same-wifi", "tailscale")]
  [string]$Gate = "same-wifi",
  [string]$SummaryPath = "",
  [string]$OutputDir = "output\acceptance",
  [switch]$Save,
  [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$ResolvedOutputDir = Join-Path $Root $OutputDir

function Resolve-ArtifactPath {
  param([string]$PathValue)
  if (-not $PathValue) { return "" }
  if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
  return Join-Path $Root $PathValue
}

function Get-LatestSummaryPath {
  param([string]$SelectedGate)
  $file = Get-ChildItem -LiteralPath $ResolvedOutputDir -Filter "manual-phone-run-$SelectedGate-*.json" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if (-not $file) { return "" }
  return $file.FullName
}

function Get-LatestReadyStatusPath {
  param([string]$SelectedGate)
  $file = Get-ChildItem -LiteralPath $ResolvedOutputDir -Filter "phone-acceptance-ready-$SelectedGate-*.json" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if (-not $file) { return "" }
  return $file.FullName
}

function Add-Check {
  param(
    [System.Collections.Generic.List[object]]$Checks,
    [string]$Name,
    [bool]$Passed,
    [string]$Detail,
    [string]$NextAction = ""
  )
  $Checks.Add([pscustomobject]@{
    name = $Name
    passed = $Passed
    detail = $Detail
    nextAction = $NextAction
  }) | Out-Null
}

function Write-VerificationArtifact {
  param(
    [object]$Verification,
    [string]$SelectedGate,
    [string]$SelectedOutputDir
  )

  $resolved = Resolve-ArtifactPath $SelectedOutputDir
  New-Item -ItemType Directory -Path $resolved -Force | Out-Null
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $path = Join-Path $resolved "phone-acceptance-verification-$SelectedGate-$timestamp.json"
  $latestPath = Join-Path $resolved "phone-acceptance-verification-$SelectedGate-latest.json"
  $Verification | Add-Member -NotePropertyName verificationJsonPath -NotePropertyValue $path -Force
  $Verification | Add-Member -NotePropertyName latestVerificationJsonPath -NotePropertyValue $latestPath -Force
  $Verification | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding UTF8
  $Verification | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $latestPath -Encoding UTF8
  return $path
}

function Read-JsonFile {
  param([string]$PathValue)
  if ([string]::IsNullOrWhiteSpace($PathValue)) { return $null }
  if (-not (Test-Path -LiteralPath $PathValue)) { return $null }
  return Get-Content -Raw -LiteralPath $PathValue | ConvertFrom-Json
}

function Test-ArtifactPath {
  param([string]$PathValue)
  return -not [string]::IsNullOrWhiteSpace($PathValue) -and (Test-Path -LiteralPath $PathValue)
}

function Test-SummaryFreshness {
  param(
    [string]$SelectedGate,
    [object]$Summary
  )

  $readyPath = Get-LatestReadyStatusPath -SelectedGate $SelectedGate
  if ([string]::IsNullOrWhiteSpace($readyPath)) {
    return [pscustomobject]@{
      passed = $true
      detail = "No latest ready artifact exists for $SelectedGate; freshness check skipped."
    }
  }

  $ready = Read-JsonFile -PathValue $readyPath
  if (-not $ready -or [string]::IsNullOrWhiteSpace("$($ready.checkedAt)") -or [string]::IsNullOrWhiteSpace("$($Summary.generatedAt)")) {
    return [pscustomobject]@{
      passed = $false
      detail = "summary generatedAt=$($Summary.generatedAt), ready checkedAt=$($ready.checkedAt), ready=$readyPath"
    }
  }

  try {
    $summaryAt = [datetime]::Parse("$($Summary.generatedAt)")
    $readyAt = [datetime]::Parse("$($ready.checkedAt)")
    return [pscustomobject]@{
      passed = $summaryAt -ge $readyAt
      detail = "summary generatedAt=$($summaryAt.ToString('o')), latest ready checkedAt=$($readyAt.ToString('o')), ready=$readyPath"
    }
  } catch {
    return [pscustomobject]@{
      passed = $false
      detail = "Could not parse summary/ready timestamps: $($_.Exception.Message)"
    }
  }
}

function Find-PhoneMark {
  param(
    [object]$HostLogs,
    [string]$SelectedGate = ""
  )
  if (-not $HostLogs -or -not $HostLogs.logs) { return $null }
  $marks = @($HostLogs.logs | Where-Object { $_.event -eq "acceptance.phoneMark" -and $_.detail -and $_.detail.proof })
  if ($marks.Count -eq 0) { return $null }
  if ([string]::IsNullOrWhiteSpace($SelectedGate)) { return $marks | Select-Object -First 1 }

  $physicalMarks = @($marks | Where-Object {
    "$($_.detail.proof.gate)" -eq $SelectedGate -and
    "$($_.detail.proof.step)" -eq "physical-phone-proof"
  })
  if ($physicalMarks.Count -gt 0) { return $physicalMarks | Select-Object -First 1 }
  return $null
}

function Test-NetworkPath {
  param(
    [string]$SelectedGate,
    [object]$PhoneMark,
    [object]$HostLogs
  )

  $origin = "$($PhoneMark.detail.proof.urlOrigin)"
  $addresses = @($HostLogs.state.addresses)
  if ($SelectedGate -eq "same-wifi") {
    $lan = @($addresses | Where-Object { $_.kind -eq "lan" -and $origin -eq ([uri]$_.url).GetLeftPart([System.UriPartial]::Authority) })
    return @{
      passed = $lan.Count -gt 0
      detail = if ($lan.Count -gt 0) { "Phone proof origin matched LAN address $origin." } else { "Phone proof origin '$origin' did not match an exported LAN URL." }
    }
  }

  $tailscale = @($addresses | Where-Object { $_.kind -eq "tailscale" -and $origin -eq ([uri]$_.url).GetLeftPart([System.UriPartial]::Authority) })
  return @{
    passed = $tailscale.Count -gt 0
    detail = if ($tailscale.Count -gt 0) { "Phone proof origin matched Tailscale address $origin." } else { "Phone proof origin '$origin' did not match an exported Tailscale URL." }
  }
}

function Get-ExpectedChecklistCount {
  param([string]$SelectedGate)
  if ($SelectedGate -eq "same-wifi") { return 13 }
  return 9
}

function Get-ManualRunCommand {
  param([string]$SelectedGate)
  return "npm run acceptance:phone -- -Gate $SelectedGate -SkipStart -RequireReady"
}

function Get-PhysicalProofNextAction {
  param(
    [string]$SelectedGate,
    [string]$CheckName
  )

  $manualCommand = Get-ManualRunCommand -SelectedGate $SelectedGate
  switch ($CheckName) {
    "summary exists" { return "Run $manualCommand, follow every prompt on the real phone, then rerun npm run acceptance:verify -- -Gate $SelectedGate -Save." }
    "manual summary is current for latest ready run" { return "Run $manualCommand again after the latest readiness refresh so the manual proof is newer than the current ready artifact." }
    "all manual steps passed" { return "Run $manualCommand and mark every required manual phone step PASS only after confirming it on the physical phone." }
    "selected-gate URL preflight exists" { return "Run $manualCommand from the current ready URL so the selected $SelectedGate phone URL preflight is captured." }
    "selected-gate URL preflight passed" { return "Run $manualCommand from the current ready URL so the phone-run preflight is captured; if that current preflight fails, fix the advertised URL, host listener, firewall, or Tailscale setup." }
    "doctor had no failures" { return "Run npm run acceptance:doctor -- -Gate $SelectedGate for current setup status, then rerun $manualCommand so the manual evidence no longer points at stale doctor results." }
    "post-report JSON exists" { return "Complete $manualCommand through its post-run report step; do not stop after the pre-run checklist." }
    "post host logs exist" { return "Complete $manualCommand through host-log export so the verifier can inspect the phone proof marker." }
    "post report is post phase" { return "Complete $manualCommand through the post phase after the phone test, then rerun verification." }
    "post report gate matches" { return "Run the manual acceptance command for the same gate being verified: $manualCommand." }
    "post report reached host" { return "Keep the host running and reachable, then complete $manualCommand through the post-run report." }
    "post report exported host logs" { return "Complete $manualCommand without skipping host log export." }
    "phone proof log exists" { return "Open the $SelectedGate proof URL on the phone, complete the proof checklist, tap Mark Proof, then complete $manualCommand." }
    "phone proof checklist exists" { return "Open the controller in proof mode, complete the on-phone checklist, tap Mark Proof, then rerun verification." }
    "phone proof checklist complete" { return "Check every required on-phone proof item before tapping Mark Proof." }
    "phone proof checklist count matches gate" { return "Refresh the phone on the current proof URL and mark proof again so the checklist matches the selected gate." }
    "phone proof checklist all items checked" { return "Check every required on-phone proof item before tapping Mark Proof." }
    "phone proof network path matches gate" { return "Use the matching proof URL for this gate: LAN URL for same-wifi, Tailscale URL for tailscale." }
    default { return "" }
  }
}

function Test-AcceptanceEvidence {
  param(
    [string]$SelectedGate,
    [string]$SelectedSummaryPath
  )

  $checks = [System.Collections.Generic.List[object]]::new()
  $summary = Read-JsonFile -PathValue $SelectedSummaryPath
  Add-Check $checks "summary exists" ($null -ne $summary) $SelectedSummaryPath (Get-PhysicalProofNextAction -SelectedGate $SelectedGate -CheckName "summary exists")
  if (-not $summary) {
    return [pscustomobject]@{ ok = $false; gate = $SelectedGate; summaryPath = $SelectedSummaryPath; checks = $checks }
  }

  Add-Check $checks "summary gate matches" ($summary.gate -eq $SelectedGate) "summary gate=$($summary.gate)"
  $freshness = Test-SummaryFreshness -SelectedGate $SelectedGate -Summary $summary
  Add-Check $checks "manual summary is current for latest ready run" ([bool]$freshness.passed) $freshness.detail (Get-PhysicalProofNextAction -SelectedGate $SelectedGate -CheckName "manual summary is current for latest ready run")
  Add-Check $checks "all manual steps passed" (($summary.failed -eq 0) -and ($summary.skipped -eq 0) -and ($summary.passed -gt 0)) "passed=$($summary.passed), failed=$($summary.failed), skipped=$($summary.skipped)" (Get-PhysicalProofNextAction -SelectedGate $SelectedGate -CheckName "all manual steps passed")
  Add-Check $checks "firewall status captured" ($null -ne $summary.firewall) "firewall ready=$($summary.firewall.ready)"
  $preflight = @($summary.preflight)
  $passingPreflight = @($preflight | Where-Object { $_.ok -eq $true })
  Add-Check $checks "selected-gate URL preflight exists" ($preflight.Count -gt 0) "preflight checks=$($preflight.Count)" (Get-PhysicalProofNextAction -SelectedGate $SelectedGate -CheckName "selected-gate URL preflight exists")
  Add-Check $checks "selected-gate URL preflight passed" ($passingPreflight.Count -gt 0) "passing preflight checks=$($passingPreflight.Count)" (Get-PhysicalProofNextAction -SelectedGate $SelectedGate -CheckName "selected-gate URL preflight passed")

  $notesPath = Resolve-ArtifactPath "$($summary.notesPath)"
  $doctorJsonPath = Resolve-ArtifactPath "$($summary.doctorReportJson)"
  $doctorMarkdownPath = Resolve-ArtifactPath "$($summary.doctorReportMarkdown)"
  $preJsonPath = Resolve-ArtifactPath "$($summary.preJson)"
  $postJsonPath = Resolve-ArtifactPath "$($summary.postJson)"
  $hostLogsPath = Resolve-ArtifactPath "$($summary.postHostLogs)"

  Add-Check $checks "notes file exists" (Test-ArtifactPath $notesPath) $notesPath
  Add-Check $checks "doctor JSON exists" (Test-ArtifactPath $doctorJsonPath) $doctorJsonPath
  Add-Check $checks "doctor Markdown exists" (Test-ArtifactPath $doctorMarkdownPath) $doctorMarkdownPath
  $doctorReport = Read-JsonFile -PathValue $doctorJsonPath
  Add-Check $checks "doctor gate matches" ($doctorReport -and $doctorReport.gate -eq $SelectedGate) "doctor gate=$($doctorReport.gate)"
  Add-Check $checks "doctor had no failures" ($doctorReport -and $doctorReport.failureCount -eq 0) "failureCount=$($doctorReport.failureCount)" (Get-PhysicalProofNextAction -SelectedGate $SelectedGate -CheckName "doctor had no failures")
  Add-Check $checks "pre-report JSON exists" (Test-ArtifactPath $preJsonPath) $preJsonPath
  Add-Check $checks "post-report JSON exists" (Test-ArtifactPath $postJsonPath) $postJsonPath (Get-PhysicalProofNextAction -SelectedGate $SelectedGate -CheckName "post-report JSON exists")
  Add-Check $checks "post host logs exist" (Test-ArtifactPath $hostLogsPath) $hostLogsPath (Get-PhysicalProofNextAction -SelectedGate $SelectedGate -CheckName "post host logs exist")

  $postReport = Read-JsonFile -PathValue $postJsonPath
  Add-Check $checks "post report is post phase" ($postReport -and $postReport.phase -eq "post") "phase=$($postReport.phase)" (Get-PhysicalProofNextAction -SelectedGate $SelectedGate -CheckName "post report is post phase")
  Add-Check $checks "post report gate matches" ($postReport -and $postReport.gate -eq $SelectedGate) "gate=$($postReport.gate)" (Get-PhysicalProofNextAction -SelectedGate $SelectedGate -CheckName "post report gate matches")
  Add-Check $checks "post report reached host" ($postReport -and $postReport.hostReachable -eq $true) "hostReachable=$($postReport.hostReachable)" (Get-PhysicalProofNextAction -SelectedGate $SelectedGate -CheckName "post report reached host")
  Add-Check $checks "post report exported host logs" ($postReport -and $postReport.hostLogsExported -eq $true) "hostLogsExported=$($postReport.hostLogsExported)" (Get-PhysicalProofNextAction -SelectedGate $SelectedGate -CheckName "post report exported host logs")

  $hostLogs = Read-JsonFile -PathValue $hostLogsPath
  $phoneMark = Find-PhoneMark -HostLogs $hostLogs -SelectedGate $SelectedGate
  Add-Check $checks "phone proof log exists" ($null -ne $phoneMark) "event=acceptance.phoneMark" (Get-PhysicalProofNextAction -SelectedGate $SelectedGate -CheckName "phone proof log exists")
  if ($phoneMark) {
    $proof = $phoneMark.detail.proof
    Add-Check $checks "phone proof has viewport" (($proof.viewport.width -gt 0) -and ($proof.viewport.height -gt 0)) "viewport=$($proof.viewport.width)x$($proof.viewport.height)"
    Add-Check $checks "phone proof has URL origin" (-not [string]::IsNullOrWhiteSpace("$($proof.urlOrigin)")) "urlOrigin=$($proof.urlOrigin)"
    Add-Check $checks "phone proof gate matches" ("$($proof.gate)" -eq $SelectedGate) "proof gate=$($proof.gate), selected gate=$SelectedGate"
    Add-Check $checks "phone proof has touch/PWA flags" ($null -ne $proof.features.touch -and $null -ne $proof.features.serviceWorker) "touch=$($proof.features.touch), serviceWorker=$($proof.features.serviceWorker)"
    Add-Check $checks "phone proof has diagnostics" (($proof.diagnostics.frameId -ge 0) -and -not [string]::IsNullOrWhiteSpace("$($proof.diagnostics.monitor)")) "frameId=$($proof.diagnostics.frameId), monitor=$($proof.diagnostics.monitor)"
    $checklist = $proof.checklist
    $checklistItems = @($checklist.items)
    $expectedChecklistCount = Get-ExpectedChecklistCount -SelectedGate $SelectedGate
    Add-Check $checks "phone proof checklist exists" ($null -ne $checklist) "checklist present=$($null -ne $checklist)" (Get-PhysicalProofNextAction -SelectedGate $SelectedGate -CheckName "phone proof checklist exists")
    Add-Check $checks "phone proof checklist gate matches" ($checklist -and "$($checklist.gate)" -eq $SelectedGate) "checklist gate=$($checklist.gate), selected gate=$SelectedGate"
    Add-Check $checks "phone proof checklist complete" ($checklist -and $checklist.complete -eq $true) "complete=$($checklist.complete)" (Get-PhysicalProofNextAction -SelectedGate $SelectedGate -CheckName "phone proof checklist complete")
    Add-Check $checks "phone proof checklist count matches gate" ($checklist -and [int]$checklist.requiredCount -eq $expectedChecklistCount -and $checklistItems.Count -eq $expectedChecklistCount) "required=$($checklist.requiredCount), items=$($checklistItems.Count), expected=$expectedChecklistCount" (Get-PhysicalProofNextAction -SelectedGate $SelectedGate -CheckName "phone proof checklist count matches gate")
    Add-Check $checks "phone proof checklist all items checked" ($checklist -and [int]$checklist.passedCount -eq $expectedChecklistCount -and @($checklistItems | Where-Object { $_.checked -ne $true }).Count -eq 0) "passed=$($checklist.passedCount), unchecked=$(@($checklistItems | Where-Object { $_.checked -ne $true }).Count)" (Get-PhysicalProofNextAction -SelectedGate $SelectedGate -CheckName "phone proof checklist all items checked")
    $networkPath = Test-NetworkPath -SelectedGate $SelectedGate -PhoneMark $phoneMark -HostLogs $hostLogs
    Add-Check $checks "phone proof network path matches gate" ([bool]$networkPath.passed) $networkPath.detail (Get-PhysicalProofNextAction -SelectedGate $SelectedGate -CheckName "phone proof network path matches gate")
  }

  $ok = -not @($checks | Where-Object { -not $_.passed }).Count
  return [pscustomobject]@{
    ok = $ok
    gate = $SelectedGate
    summaryPath = $SelectedSummaryPath
    notesPath = $notesPath
    postJson = $postJsonPath
    postHostLogs = $hostLogsPath
    checks = $checks
  }
}

function New-SelfTestArtifacts {
  $temp = Join-Path ([System.IO.Path]::GetTempPath()) "remote-phone-evidence-$([guid]::NewGuid().ToString('N'))"
  New-Item -ItemType Directory -Path $temp -Force | Out-Null

  $hostLogsPath = Join-Path $temp "manual-acceptance-same-wifi-post-host-logs.json"
  $postJsonPath = Join-Path $temp "manual-acceptance-same-wifi-post.json"
  $preJsonPath = Join-Path $temp "manual-acceptance-same-wifi-pre.json"
  $notesPath = Join-Path $temp "manual-phone-run-same-wifi.md"
  $doctorJsonPath = Join-Path $temp "acceptance-doctor-same-wifi.json"
  $doctorMarkdownPath = Join-Path $temp "acceptance-doctor-same-wifi.md"
  $summaryPath = Join-Path $temp "manual-phone-run-same-wifi.json"

  "- [PASS] sample" | Set-Content -LiteralPath $notesPath -Encoding UTF8
  "# Doctor" | Set-Content -LiteralPath $doctorMarkdownPath -Encoding UTF8
  @{ ok = $true; gate = "same-wifi"; status = "ready-with-possible-warnings"; failureCount = 0; warningCount = 0 } | ConvertTo-Json | Set-Content -LiteralPath $doctorJsonPath -Encoding UTF8
  @{ gate = "same-wifi"; phase = "pre"; hostReachable = $true } | ConvertTo-Json | Set-Content -LiteralPath $preJsonPath -Encoding UTF8
  @{ gate = "same-wifi"; phase = "post"; hostReachable = $true; hostLogsExported = $true } | ConvertTo-Json | Set-Content -LiteralPath $postJsonPath -Encoding UTF8
  $checklistItems = 1..13 | ForEach-Object {
    @{
      id = "same-wifi-$_"
      label = "Checklist item $_"
      checked = $true
    }
  }
  @{
    state = @{
      addresses = @(@{ kind = "lan"; url = "http://192.168.0.7:4317" })
    }
    logs = @(@{
      event = "acceptance.phoneMark"
      detail = @{
        proof = @{
          urlOrigin = "http://192.168.0.7:4317"
          urlPath = "/"
          gate = "same-wifi"
          step = "physical-phone-proof"
          viewport = @{ width = 390; height = 844 }
          features = @{ touch = $true; serviceWorker = $true; standalone = $false }
          diagnostics = @{ frameId = 2; monitor = "display-1"; quality = "fast" }
          checklist = @{
            source = "phone-ui"
            gate = "same-wifi"
            requiredCount = 13
            passedCount = 13
            complete = $true
            items = $checklistItems
          }
        }
      }
    })
  } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $hostLogsPath -Encoding UTF8
  @{
    ok = $true
    generatedAt = (Get-Date).ToString("o")
    gate = "same-wifi"
    notesPath = $notesPath
    doctorReportJson = $doctorJsonPath
    doctorReportMarkdown = $doctorMarkdownPath
    preJson = $preJsonPath
    postJson = $postJsonPath
    postHostLogs = $hostLogsPath
    firewall = @{ ready = $true; ruleName = "Remote Controller Host 4317"; port = 4317 }
    targetKind = "lan"
    targetPhoneUrls = @("http://192.168.0.7:4317?acceptance=1&gate=same-wifi&step=physical-phone-proof")
    rawTargetPhoneUrls = @("http://192.168.0.7:4317")
    preflight = @(@{ url = "http://192.168.0.7:4317?acceptance=1&gate=same-wifi&step=physical-phone-proof"; healthUrl = "http://192.168.0.7:4317/api/health"; ok = $true; statusCode = 200; error = "" })
    passed = 1
    failed = 0
    skipped = 0
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

  return $summaryPath
}

if ($SelfTest) {
  $sampleSummary = New-SelfTestArtifacts
  $result = Test-AcceptanceEvidence -SelectedGate "same-wifi" -SelectedSummaryPath $sampleSummary
  if (-not $result.ok) {
    $result | ConvertTo-Json -Depth 8 -Compress
    exit 1
  }
  $selfTestSaveDir = Join-Path ([System.IO.Path]::GetDirectoryName($sampleSummary)) "verification-output"
  $savedPath = Write-VerificationArtifact -Verification $result -SelectedGate "same-wifi" -SelectedOutputDir $selfTestSaveDir
  $saveArtifactOk = (Test-Path -LiteralPath $savedPath) -and (Test-Path -LiteralPath $result.latestVerificationJsonPath)
  [pscustomobject]@{
    ok = $saveArtifactOk
    gate = "same-wifi"
    checks = $result.checks.Count
    requiresChecklist = @($result.checks | Where-Object { "$($_.name)" -eq "phone proof checklist complete" -and $_.passed -eq $true }).Count -eq 1
    summaryPath = $sampleSummary
    savedVerificationPath = $savedPath
    saveArtifactOk = $saveArtifactOk
  } | ConvertTo-Json -Compress
  if (-not $saveArtifactOk) { exit 1 }
  exit 0
}

$resolvedSummaryPath = if ($SummaryPath) { Resolve-ArtifactPath $SummaryPath } else { Get-LatestSummaryPath -SelectedGate $Gate }
if (-not $resolvedSummaryPath) {
  $missingResult = [pscustomobject]@{
    ok = $false
    gate = $Gate
    error = "No manual phone acceptance summary JSON was found for gate '$Gate'. Run npm run acceptance:phone -- -Gate $Gate first."
  }
  if ($Save) {
    Write-VerificationArtifact -Verification $missingResult -SelectedGate $Gate -SelectedOutputDir $OutputDir | Out-Null
  }
  $missingResult | ConvertTo-Json -Compress
  exit 1
}

$verification = Test-AcceptanceEvidence -SelectedGate $Gate -SelectedSummaryPath $resolvedSummaryPath
if ($Save) {
  Write-VerificationArtifact -Verification $verification -SelectedGate $Gate -SelectedOutputDir $OutputDir | Out-Null
}
$verification | ConvertTo-Json -Depth 8 -Compress
if (-not $verification.ok) { exit 1 }
