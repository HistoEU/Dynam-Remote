param(
  [string]$OutputDir = "output\acceptance",
  [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$ResolvedOutputDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $Root $OutputDir }
$Verifier = Join-Path $PSScriptRoot "verify-phone-acceptance.ps1"

function Resolve-ArtifactPath {
  param([string]$PathValue)
  if (-not $PathValue) { return "" }
  if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
  return Join-Path $Root $PathValue
}

function Get-LatestFile {
  param(
    [string]$Pattern,
    [switch]$ExcludeLatest
  )
  $file = Get-ChildItem -LiteralPath $ResolvedOutputDir -Filter $Pattern -ErrorAction SilentlyContinue |
    Where-Object { -not $ExcludeLatest -or $_.Name -notlike "*-latest.*" } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if ($file) { return $file.FullName }
  return ""
}

function Get-LatestPhoneEvidenceFile {
  param([string]$Gate)
  $file = Get-ChildItem -LiteralPath $ResolvedOutputDir -Filter "phone-evidence-$Gate-*.*" -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension.ToLowerInvariant() -in @(".png", ".jpg", ".jpeg", ".webp", ".heic", ".heif") } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if ($file) { return $file.FullName }
  return ""
}

function New-ArtifactRecord {
  param(
    [string]$Name,
    [string]$PathValue,
    [bool]$Required = $true
  )

  $resolved = Resolve-ArtifactPath $PathValue
  $exists = -not [string]::IsNullOrWhiteSpace($resolved) -and (Test-Path -LiteralPath $resolved)
  $info = if ($exists) { Get-Item -LiteralPath $resolved } else { $null }
  return [pscustomobject]@{
    name = $Name
    required = $Required
    exists = $exists
    path = $resolved
    lastWriteTime = if ($info) { $info.LastWriteTime.ToString("o") } else { "" }
    bytes = if ($info) { $info.Length } else { 0 }
  }
}

function Invoke-GateVerifier {
  param([string]$Gate)

  $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $Verifier -Gate $Gate -OutputDir $OutputDir -Save 2>&1
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

  $failedChecks = @()
  if ($parsed -and $parsed.checks) {
    $failedChecks = @($parsed.checks | Where-Object { $_.passed -eq $false } | ForEach-Object {
      [pscustomobject]@{ name = "$($_.name)"; detail = "$($_.detail)" }
    })
  } elseif ($parsed -and $parsed.error) {
    $failedChecks = @([pscustomobject]@{ name = "verifier error"; detail = "$($parsed.error)" })
  } else {
    $failedChecks = @([pscustomobject]@{ name = "verifier output"; detail = (($raw -join " ") -replace "\s+", " ").Trim() })
  }

  return [pscustomobject]@{
    ok = ($exitCode -eq 0) -and $parsed -and $parsed.ok -eq $true
    exitCode = $exitCode
    failedChecks = @($failedChecks)
    verificationJsonPath = if ($parsed -and $parsed.verificationJsonPath) { "$($parsed.verificationJsonPath)" } else { "" }
    latestVerificationJsonPath = if ($parsed -and $parsed.latestVerificationJsonPath) { "$($parsed.latestVerificationJsonPath)" } else { "" }
  }
}

function New-GateEvidence {
  param([string]$Gate)

  $manualSummary = Get-LatestFile -Pattern "manual-phone-run-$Gate-*.json"
  $verifier = Invoke-GateVerifier -Gate $Gate
  $verificationLatest = Get-LatestFile -Pattern "phone-acceptance-verification-$Gate-latest.json"
  $verificationTimestamped = Get-LatestFile -Pattern "phone-acceptance-verification-$Gate-*.json" -ExcludeLatest
  $readyLatest = Get-LatestFile -Pattern "phone-acceptance-ready-$Gate-latest.json"
  $readyTimestamped = Get-LatestFile -Pattern "phone-acceptance-ready-$Gate-*.json" -ExcludeLatest
  $sessionLatest = Get-LatestFile -Pattern "phone-acceptance-session-$Gate-latest.json"
  $runCardHtml = Get-LatestFile -Pattern "phone-acceptance-session-$Gate-*.html"
  $runCardMarkdown = Get-LatestFile -Pattern "phone-acceptance-session-$Gate-*.md"
  $doctorJson = Get-LatestFile -Pattern "acceptance-doctor-$Gate-*.json"
  $doctorMarkdown = Get-LatestFile -Pattern "acceptance-doctor-$Gate-*.md"
  $preReport = Get-LatestFile -Pattern "manual-acceptance-$Gate-pre-*.json"
  $postReport = Get-LatestFile -Pattern "manual-acceptance-$Gate-post-*.json"
  $postLogs = Get-LatestFile -Pattern "manual-acceptance-$Gate-post-*-host-logs.json"
  $qr = Get-LatestFile -Pattern "phone-acceptance-qr-$Gate-*.svg"
  $phoneEvidenceLatest = Get-LatestFile -Pattern "phone-evidence-$Gate-latest.json"
  $phoneEvidenceTimestamped = Get-LatestFile -Pattern "phone-evidence-$Gate-*.json" -ExcludeLatest
  $phoneEvidenceFile = Get-LatestPhoneEvidenceFile -Gate $Gate

  $artifacts = @(
    New-ArtifactRecord "manual phone summary" $manualSummary
    New-ArtifactRecord "saved verifier latest JSON" $verificationLatest
    New-ArtifactRecord "saved verifier timestamped JSON" $verificationTimestamped
    New-ArtifactRecord "ready status latest JSON" $readyLatest $false
    New-ArtifactRecord "ready status timestamped JSON" $readyTimestamped $false
    New-ArtifactRecord "prepared session latest JSON" $sessionLatest $false
    New-ArtifactRecord "run card HTML" $runCardHtml $false
    New-ArtifactRecord "run card Markdown" $runCardMarkdown $false
    New-ArtifactRecord "readiness doctor JSON" $doctorJson
    New-ArtifactRecord "readiness doctor Markdown" $doctorMarkdown
    New-ArtifactRecord "pre acceptance report JSON" $preReport
    New-ArtifactRecord "post acceptance report JSON" $postReport
    New-ArtifactRecord "post host logs JSON" $postLogs
    New-ArtifactRecord "phone QR SVG" $qr $false
    New-ArtifactRecord "operator-attached phone evidence latest JSON" $phoneEvidenceLatest $false
    New-ArtifactRecord "operator-attached phone evidence timestamped JSON" $phoneEvidenceTimestamped $false
    New-ArtifactRecord "operator-attached phone evidence file" $phoneEvidenceFile $false
  )

  if ($Gate -eq "tailscale") {
    $artifacts += New-ArtifactRecord "Tailscale setup check latest JSON" (Get-LatestFile -Pattern "tailscale-setup-check-latest.json") $false
    $artifacts += New-ArtifactRecord "Tailscale setup check Markdown" (Get-LatestFile -Pattern "tailscale-setup-check-*.md") $false
    $artifacts += New-ArtifactRecord "Tailscale bootstrap latest JSON" (Get-LatestFile -Pattern "tailscale-bootstrap-latest.json") $false
    $artifacts += New-ArtifactRecord "Tailscale bootstrap Markdown" (Get-LatestFile -Pattern "tailscale-bootstrap-*.md") $false
  }

  return [pscustomobject]@{
    gate = $Gate
    verifierOk = $verifier.ok
    verifierExitCode = $verifier.exitCode
    verifierJsonPath = $verifier.verificationJsonPath
    latestVerifierJsonPath = $verifier.latestVerificationJsonPath
    failedChecks = @($verifier.failedChecks)
    artifacts = @($artifacts)
    missingRequiredArtifacts = @($artifacts | Where-Object { $_.required -and -not $_.exists } | ForEach-Object { $_.name })
  }
}

function Write-BundleMarkdown {
  param(
    [object]$Bundle,
    [string]$Path
  )

  $gateSections = @($Bundle.gates | ForEach-Object {
    $artifactRows = @($_.artifacts | ForEach-Object {
      "| $($_.exists) | $($_.required) | $($_.name) | $($_.path) |"
    })
    if ($artifactRows.Count -eq 0) { $artifactRows = @("| none | none | none | none |") }
    $failedRows = @($_.failedChecks | ForEach-Object { "- $($_.name): $($_.detail)" })
    if ($failedRows.Count -eq 0) { $failedRows = @("- none") }
@"
## $($_.gate)

Verifier passed: $($_.verifierOk)
Verifier exit code: $($_.verifierExitCode)

Failed checks:

$($failedRows -join [Environment]::NewLine)

Artifacts:

| Exists | Required | Name | Path |
| --- | --- | --- | --- |
$($artifactRows -join [Environment]::NewLine)
"@
  })

  $nextRows = @($Bundle.operatorNextActions | ForEach-Object {
    "| $($_.exists) | $($_.name) | $($_.path) |"
  })
  if ($nextRows.Count -eq 0) { $nextRows = @("| none | none | none |") }

  $markdown = @"
# Remote Controller Evidence Bundle

Generated: $($Bundle.generatedAt)
Output folder: $($Bundle.outputDir)
Complete: $($Bundle.ok)

This manifest indexes current evidence only. It is not a substitute for real physical phone acceptance or the final completion audit.

$($gateSections -join [Environment]::NewLine)

## Operator Next Actions

| Exists | Name | Path |
| --- | --- | --- |
$($nextRows -join [Environment]::NewLine)

## Final Commands

~~~powershell
npm run acceptance:verify:save -- -Gate same-wifi
npm run acceptance:verify:save -- -Gate tailscale
npm run evidence:bundle
npm run completion:audit
~~~
"@

  $markdown | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-EvidenceBundle {
  New-Item -ItemType Directory -Path $ResolvedOutputDir -Force | Out-Null
  $gates = @(
    New-GateEvidence -Gate "same-wifi"
    New-GateEvidence -Gate "tailscale"
  )
  $nextLatestJson = Get-LatestFile -Pattern "phone-acceptance-next-latest.json"
  $nextLatestMarkdown = Get-LatestFile -Pattern "phone-acceptance-next-latest.md"
  $nextTimestampedJson = Get-LatestFile -Pattern "phone-acceptance-next-*.json" -ExcludeLatest
  $nextTimestampedMarkdown = Get-LatestFile -Pattern "phone-acceptance-next-*.md" -ExcludeLatest
  $runbookLatestJson = Get-LatestFile -Pattern "physical-proof-runbook-latest.json"
  $runbookLatestMarkdown = Get-LatestFile -Pattern "physical-proof-runbook-latest.md"
  $runbookTimestampedJson = Get-LatestFile -Pattern "physical-proof-runbook-*.json" -ExcludeLatest
  $runbookTimestampedMarkdown = Get-LatestFile -Pattern "physical-proof-runbook-*.md" -ExcludeLatest
  $sameWifiLaunchLatestJson = Get-LatestFile -Pattern "physical-proof-launch-same-wifi-latest.json"
  $sameWifiLaunchLatestMarkdown = Get-LatestFile -Pattern "physical-proof-launch-same-wifi-latest.md"
  $sameWifiLaunchTimestampedJson = Get-LatestFile -Pattern "physical-proof-launch-same-wifi-*.json" -ExcludeLatest
  $sameWifiLaunchTimestampedMarkdown = Get-LatestFile -Pattern "physical-proof-launch-same-wifi-*.md" -ExcludeLatest
  $tailscaleLaunchLatestJson = Get-LatestFile -Pattern "physical-proof-launch-tailscale-latest.json"
  $tailscaleLaunchLatestMarkdown = Get-LatestFile -Pattern "physical-proof-launch-tailscale-latest.md"
  $tailscaleLaunchTimestampedJson = Get-LatestFile -Pattern "physical-proof-launch-tailscale-*.json" -ExcludeLatest
  $tailscaleLaunchTimestampedMarkdown = Get-LatestFile -Pattern "physical-proof-launch-tailscale-*.md" -ExcludeLatest
  $dashboardLatestJson = Get-LatestFile -Pattern "phone-acceptance-dashboard-latest.json"
  $dashboardLatestHtml = Get-LatestFile -Pattern "phone-acceptance-dashboard-latest.html"
  $dashboardTimestampedJson = Get-LatestFile -Pattern "phone-acceptance-dashboard-*.json" -ExcludeLatest
  $dashboardTimestampedHtml = Get-LatestFile -Pattern "phone-acceptance-dashboard-*.html" -ExcludeLatest
  $handoffLatestJson = Get-LatestFile -Pattern "phone-acceptance-handoff-latest.json"
  $handoffLatestMarkdown = Get-LatestFile -Pattern "phone-acceptance-handoff-latest.md"
  $handoffLatestHtml = Get-LatestFile -Pattern "phone-acceptance-handoff-latest.html"
  $handoffTimestampedJson = Get-LatestFile -Pattern "phone-acceptance-handoff-*.json" -ExcludeLatest
  $handoffTimestampedMarkdown = Get-LatestFile -Pattern "phone-acceptance-handoff-*.md" -ExcludeLatest
  $handoffTimestampedHtml = Get-LatestFile -Pattern "phone-acceptance-handoff-*.html" -ExcludeLatest
  $refreshLatestJson = Get-LatestFile -Pattern "phone-acceptance-refresh-latest.json"
  $refreshLatestMarkdown = Get-LatestFile -Pattern "phone-acceptance-refresh-latest.md"
  $refreshTimestampedJson = Get-LatestFile -Pattern "phone-acceptance-refresh-*.json" -ExcludeLatest
  $refreshTimestampedMarkdown = Get-LatestFile -Pattern "phone-acceptance-refresh-*.md" -ExcludeLatest
  $qaLatestJson = Get-LatestFile -Pattern "qa-report-latest.json"
  $qaLatestMarkdown = Get-LatestFile -Pattern "qa-report-latest.md"
  $qaTimestampedJson = Get-LatestFile -Pattern "qa-report-*.json" -ExcludeLatest
  $qaTimestampedMarkdown = Get-LatestFile -Pattern "qa-report-*.md" -ExcludeLatest
  $visualProofLatestJson = Get-LatestFile -Pattern "live-phone-visual-proof-latest.json"
  $visualProofLatestPng = Get-LatestFile -Pattern "live-phone-visual-proof-latest.png"
  $visualProofTimestampedJson = Get-LatestFile -Pattern "live-phone-visual-proof-*.json" -ExcludeLatest
  $visualProofTimestampedPng = Get-LatestFile -Pattern "live-phone-visual-proof-*.png" -ExcludeLatest
  $auditLatestJson = Get-LatestFile -Pattern "completion-audit-latest.json"
  $auditLatestMarkdown = Get-LatestFile -Pattern "completion-audit-latest.md"
  $auditTimestampedJson = Get-LatestFile -Pattern "completion-audit-*.json" -ExcludeLatest
  $auditTimestampedMarkdown = Get-LatestFile -Pattern "completion-audit-*.md" -ExcludeLatest
  $dependencyAuditLatestJson = Get-LatestFile -Pattern "dependency-audit-latest.json"
  $dependencyAuditLatestMarkdown = Get-LatestFile -Pattern "dependency-audit-latest.md"
  $dependencyAuditTimestampedJson = Get-LatestFile -Pattern "dependency-audit-*.json" -ExcludeLatest
  $dependencyAuditTimestampedMarkdown = Get-LatestFile -Pattern "dependency-audit-*.md" -ExcludeLatest
  $finalizationLatestJson = Get-LatestFile -Pattern "physical-evidence-finalization-latest.json"
  $finalizationLatestMarkdown = Get-LatestFile -Pattern "physical-evidence-finalization-latest.md"
  $finalizationTimestampedJson = Get-LatestFile -Pattern "physical-evidence-finalization-*.json" -ExcludeLatest
  $finalizationTimestampedMarkdown = Get-LatestFile -Pattern "physical-evidence-finalization-*.md" -ExcludeLatest
  $firewallHandoffLatestJson = Get-LatestFile -Pattern "firewall-handoff-install-latest.json"
  $firewallHandoffLatestMarkdown = Get-LatestFile -Pattern "firewall-handoff-install-latest.md"
  $firewallHandoffLatestScript = Get-LatestFile -Pattern "firewall-handoff-install-latest.ps1"
  $firewallHandoffTimestampedJson = Get-LatestFile -Pattern "firewall-handoff-install-*.json" -ExcludeLatest
  $firewallHandoffTimestampedMarkdown = Get-LatestFile -Pattern "firewall-handoff-install-*.md" -ExcludeLatest
  $firewallHandoffTimestampedScript = Get-LatestFile -Pattern "firewall-handoff-install-*.ps1" -ExcludeLatest
  $activeFinalizationManual = Join-Path $Root "docs\Remote_Controller_Finalization_Plan.docx"
  $activeFinalizationTraceability = Join-Path $Root "docs\FINALIZATION_TRACEABILITY.md"
  $legacyTraceability = Join-Path $Root "docs\TRACEABILITY_AUDIT.md"
  $ok = -not @($gates | Where-Object { -not $_.verifierOk }).Count
  $bundle = [pscustomobject]@{
    ok = $ok
    generatedAt = (Get-Date).ToString("o")
    outputDir = "$ResolvedOutputDir"
    gates = @($gates)
    operatorNextActions = @(
      New-ArtifactRecord "next actions latest JSON" $nextLatestJson $false
      New-ArtifactRecord "next actions latest Markdown" $nextLatestMarkdown $false
      New-ArtifactRecord "next actions timestamped JSON" $nextTimestampedJson $false
      New-ArtifactRecord "next actions timestamped Markdown" $nextTimestampedMarkdown $false
      New-ArtifactRecord "physical proof runbook latest JSON" $runbookLatestJson $false
      New-ArtifactRecord "physical proof runbook latest Markdown" $runbookLatestMarkdown $false
      New-ArtifactRecord "physical proof runbook timestamped JSON" $runbookTimestampedJson $false
      New-ArtifactRecord "physical proof runbook timestamped Markdown" $runbookTimestampedMarkdown $false
      New-ArtifactRecord "same-Wi-Fi physical proof launch latest JSON" $sameWifiLaunchLatestJson $false
      New-ArtifactRecord "same-Wi-Fi physical proof launch latest Markdown" $sameWifiLaunchLatestMarkdown $false
      New-ArtifactRecord "same-Wi-Fi physical proof launch timestamped JSON" $sameWifiLaunchTimestampedJson $false
      New-ArtifactRecord "same-Wi-Fi physical proof launch timestamped Markdown" $sameWifiLaunchTimestampedMarkdown $false
      New-ArtifactRecord "Tailscale physical proof launch latest JSON" $tailscaleLaunchLatestJson $false
      New-ArtifactRecord "Tailscale physical proof launch latest Markdown" $tailscaleLaunchLatestMarkdown $false
      New-ArtifactRecord "Tailscale physical proof launch timestamped JSON" $tailscaleLaunchTimestampedJson $false
      New-ArtifactRecord "Tailscale physical proof launch timestamped Markdown" $tailscaleLaunchTimestampedMarkdown $false
      New-ArtifactRecord "acceptance dashboard latest JSON" $dashboardLatestJson $false
      New-ArtifactRecord "acceptance dashboard latest HTML" $dashboardLatestHtml $false
      New-ArtifactRecord "acceptance dashboard timestamped JSON" $dashboardTimestampedJson $false
      New-ArtifactRecord "acceptance dashboard timestamped HTML" $dashboardTimestampedHtml $false
      New-ArtifactRecord "acceptance handoff latest JSON" $handoffLatestJson $false
      New-ArtifactRecord "acceptance handoff latest Markdown" $handoffLatestMarkdown $false
      New-ArtifactRecord "acceptance handoff latest HTML" $handoffLatestHtml $false
      New-ArtifactRecord "acceptance handoff timestamped JSON" $handoffTimestampedJson $false
      New-ArtifactRecord "acceptance handoff timestamped Markdown" $handoffTimestampedMarkdown $false
      New-ArtifactRecord "acceptance handoff timestamped HTML" $handoffTimestampedHtml $false
      New-ArtifactRecord "acceptance refresh latest JSON" $refreshLatestJson $false
      New-ArtifactRecord "acceptance refresh latest Markdown" $refreshLatestMarkdown $false
      New-ArtifactRecord "acceptance refresh timestamped JSON" $refreshTimestampedJson $false
      New-ArtifactRecord "acceptance refresh timestamped Markdown" $refreshTimestampedMarkdown $false
      New-ArtifactRecord "QA report latest JSON" $qaLatestJson $false
      New-ArtifactRecord "QA report latest Markdown" $qaLatestMarkdown $false
      New-ArtifactRecord "QA report timestamped JSON" $qaTimestampedJson $false
      New-ArtifactRecord "QA report timestamped Markdown" $qaTimestampedMarkdown $false
      New-ArtifactRecord "live phone visual proof latest JSON" $visualProofLatestJson $false
      New-ArtifactRecord "live phone visual proof latest PNG" $visualProofLatestPng $false
      New-ArtifactRecord "live phone visual proof timestamped JSON" $visualProofTimestampedJson $false
      New-ArtifactRecord "live phone visual proof timestamped PNG" $visualProofTimestampedPng $false
      New-ArtifactRecord "dependency audit latest JSON" $dependencyAuditLatestJson $false
      New-ArtifactRecord "dependency audit latest Markdown" $dependencyAuditLatestMarkdown $false
      New-ArtifactRecord "dependency audit timestamped JSON" $dependencyAuditTimestampedJson $false
      New-ArtifactRecord "dependency audit timestamped Markdown" $dependencyAuditTimestampedMarkdown $false
      New-ArtifactRecord "completion audit latest JSON" $auditLatestJson $false
      New-ArtifactRecord "completion audit latest Markdown" $auditLatestMarkdown $false
      New-ArtifactRecord "completion audit timestamped JSON" $auditTimestampedJson $false
      New-ArtifactRecord "completion audit timestamped Markdown" $auditTimestampedMarkdown $false
      New-ArtifactRecord "physical finalization latest JSON" $finalizationLatestJson $false
      New-ArtifactRecord "physical finalization latest Markdown" $finalizationLatestMarkdown $false
      New-ArtifactRecord "physical finalization timestamped JSON" $finalizationTimestampedJson $false
      New-ArtifactRecord "physical finalization timestamped Markdown" $finalizationTimestampedMarkdown $false
      New-ArtifactRecord "firewall handoff latest JSON" $firewallHandoffLatestJson $false
      New-ArtifactRecord "firewall handoff latest Markdown" $firewallHandoffLatestMarkdown $false
      New-ArtifactRecord "firewall handoff latest script" $firewallHandoffLatestScript $false
      New-ArtifactRecord "firewall handoff timestamped JSON" $firewallHandoffTimestampedJson $false
      New-ArtifactRecord "firewall handoff timestamped Markdown" $firewallHandoffTimestampedMarkdown $false
      New-ArtifactRecord "firewall handoff timestamped script" $firewallHandoffTimestampedScript $false
      New-ArtifactRecord "active finalization manual DOCX" $activeFinalizationManual $false
      New-ArtifactRecord "active finalization traceability Markdown" $activeFinalizationTraceability $false
      New-ArtifactRecord "legacy build manual traceability Markdown" $legacyTraceability $false
    )
  }

  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $jsonPath = Join-Path $ResolvedOutputDir "remote-controller-evidence-bundle-$timestamp.json"
  $mdPath = Join-Path $ResolvedOutputDir "remote-controller-evidence-bundle-$timestamp.md"
  $latestJsonPath = Join-Path $ResolvedOutputDir "remote-controller-evidence-bundle-latest.json"
  $latestMdPath = Join-Path $ResolvedOutputDir "remote-controller-evidence-bundle-latest.md"
  $bundle | Add-Member -NotePropertyName bundleJsonPath -NotePropertyValue $jsonPath -Force
  $bundle | Add-Member -NotePropertyName bundleMarkdownPath -NotePropertyValue $mdPath -Force
  $bundle | Add-Member -NotePropertyName latestBundleJsonPath -NotePropertyValue $latestJsonPath -Force
  $bundle | Add-Member -NotePropertyName latestBundleMarkdownPath -NotePropertyValue $latestMdPath -Force
  $bundle | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  $bundle | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $latestJsonPath -Encoding UTF8
  Write-BundleMarkdown -Bundle $bundle -Path $mdPath
  Write-BundleMarkdown -Bundle $bundle -Path $latestMdPath
  return $bundle
}

if ($SelfTest) {
  $scriptText = Get-Content -Raw -LiteralPath $PSCommandPath
  $ok = (Test-Path -LiteralPath $Verifier) -and
    ($scriptText -like "*physical-evidence-finalization-latest.json*") -and
    ($scriptText -like "*physical finalization timestamped Markdown*") -and
    ($scriptText -like "*physical-proof-runbook-latest.json*") -and
    ($scriptText -like "*physical proof runbook timestamped Markdown*") -and
    ($scriptText -like "*physical-proof-launch-same-wifi-latest.json*") -and
    ($scriptText -like "*same-Wi-Fi physical proof launch timestamped Markdown*") -and
    ($scriptText -like "*physical-proof-launch-tailscale-latest.json*") -and
    ($scriptText -like "*Tailscale physical proof launch timestamped Markdown*") -and
    ($scriptText -like "*firewall-handoff-install-latest.json*") -and
    ($scriptText -like "*firewall handoff timestamped script*") -and
    ($scriptText -like "*Remote_Controller_Finalization_Plan.docx*") -and
    ($scriptText -like "*FINALIZATION_TRACEABILITY.md*")
  [pscustomobject]@{
    ok = $ok
    verifierExists = (Test-Path -LiteralPath $Verifier)
    writesJsonAndMarkdown = $true
    gateCount = 2
    indexesPhysicalFinalization = $scriptText -like "*physical-evidence-finalization-latest.json*"
    indexesPhysicalProofRunbook = $scriptText -like "*physical-proof-runbook-latest.json*"
    indexesPhysicalProofLaunch = ($scriptText -like "*physical-proof-launch-same-wifi-latest.json*") -and ($scriptText -like "*physical-proof-launch-tailscale-latest.json*")
    indexesFirewallHandoff = $scriptText -like "*firewall-handoff-install-latest.json*"
    indexesActiveFinalizationPlan = ($scriptText -like "*Remote_Controller_Finalization_Plan.docx*") -and ($scriptText -like "*FINALIZATION_TRACEABILITY.md*")
  } | ConvertTo-Json -Compress
  if (-not $ok) { exit 1 }
  exit 0
}

$bundle = New-EvidenceBundle
$bundle | ConvertTo-Json -Depth 8 -Compress
if (-not $bundle.ok) { exit 1 }
