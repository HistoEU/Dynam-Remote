param(
  [string]$OutputDir = "output\acceptance",
  [switch]$Save,
  [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$Verifier = Join-Path $PSScriptRoot "verify-phone-acceptance.ps1"

function Resolve-RootPath {
  param([string]$PathValue)
  if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
  return Join-Path $Root $PathValue
}

function Add-Requirement {
  param(
    [System.Collections.Generic.List[object]]$Requirements,
    [string]$Id,
    [string]$Requirement,
    [string]$Evidence,
    [bool]$Passed,
    [string]$Detail
  )

  $Requirements.Add([pscustomobject]@{
    id = $Id
    requirement = $Requirement
    evidence = $Evidence
    passed = $Passed
    detail = $Detail
  }) | Out-Null
}

function Read-PackageJson {
  $path = Join-Path $Root "package.json"
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  return Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
}

function Read-JsonFile {
  param([string]$PathValue)
  if (-not $PathValue -or -not (Test-Path -LiteralPath $PathValue -PathType Leaf)) { return $null }
  try {
    return Get-Content -Raw -LiteralPath $PathValue | ConvertFrom-Json
  } catch {
    return $null
  }
}

function Get-PhoneAppVersion {
  $serviceWorkerPath = Join-Path $Root "public\sw.js"
  if (-not (Test-Path -LiteralPath $serviceWorkerPath -PathType Leaf)) { return "" }
  $source = Get-Content -Raw -LiteralPath $serviceWorkerPath
  $match = [regex]::Match($source, 'remote-controller-shell-v(?<version>[0-9]+)')
  if (-not $match.Success) { return "" }
  return "$($match.Groups["version"].Value)"
}

function Read-TextFile {
  param([string]$PathValue)
  if (-not $PathValue -or -not (Test-Path -LiteralPath $PathValue -PathType Leaf)) { return "" }
  try {
    return Get-Content -Raw -LiteralPath $PathValue
  } catch {
    return ""
  }
}

function ConvertTo-StringArray {
  param([object]$Values)
  if ($null -eq $Values) { return @() }
  return @($Values | Where-Object { $null -ne $_ } | ForEach-Object { "$_" })
}

function Test-PackageScript {
  param(
    [object]$Package,
    [string]$ScriptName
  )

  if (-not $Package -or -not $Package.scripts) { return $false }
  return [bool]($Package.scripts.PSObject.Properties.Name -contains $ScriptName)
}

function Get-PackageScriptValue {
  param(
    [object]$Package,
    [string]$ScriptName
  )

  if (-not (Test-PackageScript -Package $Package -ScriptName $ScriptName)) { return "" }
  return "$($Package.scripts.$ScriptName)"
}

function Test-PackageScriptContains {
  param(
    [object]$Package,
    [string]$ScriptName,
    [string[]]$Fragments
  )

  $value = Get-PackageScriptValue -Package $Package -ScriptName $ScriptName
  if ([string]::IsNullOrWhiteSpace($value)) { return $false }
  foreach ($fragment in @($Fragments)) {
    if ($value -notlike "*$fragment*") { return $false }
  }
  return $true
}

function Test-NonEmptyFile {
  param([string]$PathValue)
  if (-not $PathValue -or -not (Test-Path -LiteralPath $PathValue -PathType Leaf)) { return $false }
  $item = Get-Item -LiteralPath $PathValue -ErrorAction SilentlyContinue
  return $item -and $item.Length -gt 0
}

function Get-DocxPlainText {
  param([string]$PathValue)

  if (-not $PathValue -or -not (Test-Path -LiteralPath $PathValue -PathType Leaf)) { return "" }
  try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $zip = [System.IO.Compression.ZipFile]::OpenRead($PathValue)
    try {
      $entry = $zip.GetEntry("word/document.xml")
      if (-not $entry) { return "" }
      $stream = $entry.Open()
      try {
        $reader = [System.IO.StreamReader]::new($stream)
        try {
          $xmlText = $reader.ReadToEnd()
        } finally {
          $reader.Dispose()
        }
      } finally {
        $stream.Dispose()
      }

      [xml]$xml = $xmlText
      $ns = [System.Xml.XmlNamespaceManager]::new($xml.NameTable)
      $ns.AddNamespace("w", "http://schemas.openxmlformats.org/wordprocessingml/2006/main")
      $paragraphs = @()
      foreach ($paragraph in $xml.SelectNodes("//w:p", $ns)) {
        $texts = @()
        foreach ($textNode in $paragraph.SelectNodes(".//w:t", $ns)) {
          $texts += $textNode.InnerText
        }
        $line = ($texts -join "")
        if (-not [string]::IsNullOrWhiteSpace($line)) {
          $paragraphs += $line
        }
      }
      return ($paragraphs -join "`n")
    } finally {
      $zip.Dispose()
    }
  } catch {
    return ""
  }
}

function Add-ArtifactRequirement {
  param(
    [System.Collections.Generic.List[object]]$Requirements,
    [string]$Id,
    [string]$Requirement,
    [string]$RelativePath,
    [string]$SelectedOutputDir
  )

  $resolved = Join-Path (Resolve-RootPath $SelectedOutputDir) $RelativePath
  Add-Requirement $Requirements $Id $Requirement $RelativePath (Test-NonEmptyFile $resolved) $resolved
}

function Get-GateRecord {
  param(
    [object]$Container,
    [string]$Gate
  )
  if (-not $Container -or -not $Container.gates) { return $null }
  return @($Container.gates | Where-Object { "$($_.gate)" -eq $Gate } | Select-Object -First 1)
}

function Test-AnyStringContains {
  param(
    [object]$Values,
    [string]$Pattern
  )
  return @((ConvertTo-StringArray $Values) | Where-Object { $_ -like "*$Pattern*" }).Count -gt 0
}

function Get-OptionalPhoneEvidenceValidation {
  param(
    [string]$Gate,
    [string]$SelectedOutputDir
  )

  $artifactRoot = Resolve-RootPath $SelectedOutputDir
  $recordPath = Join-Path $artifactRoot "phone-evidence-$Gate-latest.json"
  if (-not (Test-Path -LiteralPath $recordPath -PathType Leaf)) {
    return [pscustomobject]@{
      passed = $true
      detail = "no optional $Gate phone screenshot/photo attached"
    }
  }

  $record = Read-JsonFile $recordPath
  if (-not $record) {
    return [pscustomobject]@{
      passed = $false
      detail = "$recordPath is missing or invalid JSON"
    }
  }

  $allowedExtensions = @(".png", ".jpg", ".jpeg", ".webp", ".heic", ".heif")
  $copiedPath = "$($record.copiedPath)"
  $copiedExists = -not [string]::IsNullOrWhiteSpace($copiedPath) -and (Test-Path -LiteralPath $copiedPath -PathType Leaf)
  $actualHash = ""
  if ($copiedExists) {
    try {
      $actualHash = (Get-FileHash -LiteralPath $copiedPath -Algorithm SHA256).Hash
    } catch {
      $actualHash = ""
    }
  }

  $passed = "$($record.gate)" -eq $Gate -and
    "$($record.capturedBy)" -eq "operator-attached" -and
    $record.doesNotReplaceVerifier -eq $true -and
    $allowedExtensions -contains "$($record.extension)".ToLowerInvariant() -and
    $copiedExists -and
    -not [string]::IsNullOrWhiteSpace("$($record.sha256)") -and
    $actualHash -eq "$($record.sha256)" -and
    "$($record.verifierReminder)" -like "*acceptance:verify*Gate $Gate*"

  return [pscustomobject]@{
    passed = $passed
    detail = "gate=$($record.gate), copiedExists=$copiedExists, extension=$($record.extension), supportingOnly=$($record.doesNotReplaceVerifier), hashMatches=$($actualHash -eq "$($record.sha256)")"
  }
}

function Get-QaFreshnessValidation {
  param([object]$QaReport)

  if (-not $QaReport -or [string]::IsNullOrWhiteSpace("$($QaReport.generatedAt)")) {
    return [pscustomobject]@{
      passed = $false
      detail = "missing qa generatedAt"
    }
  }

  $qaGeneratedAt = $null
  try {
    $qaGeneratedAt = [datetime]::Parse("$($QaReport.generatedAt)")
  } catch {
    return [pscustomobject]@{
      passed = $false
      detail = "invalid qa generatedAt=$($QaReport.generatedAt)"
    }
  }

  $sourceFiles = @()
  foreach ($relativeDir in @("src", "public", "test", "scripts")) {
    $dir = Join-Path $Root $relativeDir
    if (Test-Path -LiteralPath $dir -PathType Container) {
      $sourceFiles += @(Get-ChildItem -LiteralPath $dir -Recurse -File -ErrorAction SilentlyContinue)
    }
  }
  foreach ($relativeFile in @("package.json", "package-lock.json")) {
    $path = Join-Path $Root $relativeFile
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      $sourceFiles += @(Get-Item -LiteralPath $path)
    }
  }

  $latestSource = @($sourceFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
  if ($latestSource.Count -eq 0) {
    return [pscustomobject]@{
      passed = $false
      detail = "no implementation files found"
    }
  }

  $latest = $latestSource[0]
  $threshold = $latest.LastWriteTime.AddSeconds(-5)
  $passed = $qaGeneratedAt -ge $threshold
  return [pscustomobject]@{
    passed = $passed
    detail = "qaGeneratedAt=$($qaGeneratedAt.ToString("o")), latestImplementationFile=$($latest.FullName), latestImplementationWrite=$($latest.LastWriteTime.ToString("o"))"
  }
}

function Add-ContentRequirement {
  param(
    [System.Collections.Generic.List[object]]$Requirements,
    [string]$Id,
    [string]$Requirement,
    [string]$Evidence,
    [bool]$Passed,
    [string]$Detail
  )
  Add-Requirement $Requirements $Id $Requirement $Evidence $Passed $Detail
}

function Invoke-GateVerification {
  param(
    [string]$Gate,
    [string]$SelectedOutputDir
  )

  $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $Verifier -Gate $Gate -OutputDir $SelectedOutputDir 2>&1
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
    gate = $Gate
    ok = ($exitCode -eq 0) -and $parsed -and $parsed.ok -eq $true
    exitCode = $exitCode
    result = $parsed
    raw = @($raw | ForEach-Object { "$_" })
  }
}

function Limit-DetailText {
  param(
    [string]$Text,
    [int]$MaxLength = 1200
  )

  if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
  $normalized = ($Text -replace "\s+", " ").Trim()
  if ($normalized.Length -le $MaxLength) { return $normalized }
  return "$($normalized.Substring(0, $MaxLength - 3))..."
}

function Format-GateVerificationDetail {
  param(
    [object]$GateResult
  )

  if ($GateResult.ok) { return "$($GateResult.gate) verifier passed" }

  $result = $GateResult.result
  if ($result -and $result.error) {
    return Limit-DetailText -Text "$($result.error)"
  }

  if ($result -and $result.checks) {
    $failedChecks = @($result.checks | Where-Object { $_.passed -eq $false })
    if ($failedChecks.Count -gt 0) {
      $parts = @($failedChecks | ForEach-Object {
        $detail = if ($_.detail) { " ($($_.detail))" } else { "" }
        "$($_.name)$detail"
      })
      $nextActions = @($failedChecks |
        Where-Object { -not [string]::IsNullOrWhiteSpace("$($_.nextAction)") } |
        ForEach-Object { "$($_.nextAction)" } |
        Select-Object -Unique)
      $next = if ($nextActions.Count -gt 0) { " Next actions: $($nextActions -join '; ')" } else { "" }
      return Limit-DetailText -Text "Failed checks: $($parts -join '; ').$next" -MaxLength 5000
    }
  }

  return Limit-DetailText -Text ($GateResult.raw -join " ")
}

function Write-AuditMarkdown {
  param(
    [object]$Audit,
    [string]$Path
  )

  $failedRows = @($Audit.requirements | Where-Object { $_.passed -eq $false } | ForEach-Object {
    "- $($_.id): $($_.requirement) - $($_.detail)"
  })
  if ($failedRows.Count -eq 0) { $failedRows = @("- none") }

  $requirementRows = @($Audit.requirements | ForEach-Object {
    "| $($_.passed) | $($_.id) | $($_.requirement) | $($_.evidence) | $($_.detail) |"
  })
  if ($requirementRows.Count -eq 0) { $requirementRows = @("| none | none | none | none | none |") }

  $markdown = @"
# Completion Audit

Generated: $($Audit.generatedAt)
Status: $($Audit.status)
Complete: $($Audit.ok)
Source document: $($Audit.sourceDoc)
Finalization document: $($Audit.finalizationDoc)
Output folder: $($Audit.outputDir)
Requirement count: $($Audit.requirementCount)
Failed count: $($Audit.failedCount)
Same-Wi-Fi gate: $($Audit.gates.sameWifi)
Tailscale gate: $($Audit.gates.tailscale)

This audit is the whole-manual completion check. It can only pass after both real physical phone evidence verifiers pass.

## Failed Requirements

$($failedRows -join [Environment]::NewLine)

## Requirement Table

| Passed | ID | Requirement | Evidence | Detail |
| --- | --- | --- | --- | --- |
$($requirementRows -join [Environment]::NewLine)

## Final Commands

~~~powershell
npm run acceptance:verify:save -- -Gate same-wifi
npm run acceptance:verify:save -- -Gate tailscale
npm run evidence:bundle
npm run completion:audit:save
~~~
"@

  $markdown | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Save-CompletionAudit {
  param(
    [object]$Audit,
    [string]$SelectedOutputDir
  )

  $resolvedOutputDir = Resolve-RootPath $SelectedOutputDir
  New-Item -ItemType Directory -Path $resolvedOutputDir -Force | Out-Null
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $jsonPath = Join-Path $resolvedOutputDir "completion-audit-$timestamp.json"
  $mdPath = Join-Path $resolvedOutputDir "completion-audit-$timestamp.md"
  $latestJsonPath = Join-Path $resolvedOutputDir "completion-audit-latest.json"
  $latestMdPath = Join-Path $resolvedOutputDir "completion-audit-latest.md"
  $Audit | Add-Member -NotePropertyName auditJsonPath -NotePropertyValue $jsonPath -Force
  $Audit | Add-Member -NotePropertyName auditMarkdownPath -NotePropertyValue $mdPath -Force
  $Audit | Add-Member -NotePropertyName latestAuditJsonPath -NotePropertyValue $latestJsonPath -Force
  $Audit | Add-Member -NotePropertyName latestAuditMarkdownPath -NotePropertyValue $latestMdPath -Force
  $Audit | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  $Audit | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $latestJsonPath -Encoding UTF8
  Write-AuditMarkdown -Audit $Audit -Path $mdPath
  Write-AuditMarkdown -Audit $Audit -Path $latestMdPath
  return $Audit
}

function Invoke-CompletionAudit {
  param([string]$SelectedOutputDir)

  $requirements = [System.Collections.Generic.List[object]]::new()
  $package = Read-PackageJson
  $sourceDoc = "C:\RemoteDesktopControllerPlan\Free_Remote_Desktop_Controller_15_Page_Build_Plan.docx"
  $finalizationDoc = Join-Path $Root "docs\Remote_Controller_Finalization_Plan.docx"
  $resolvedOutputDir = Resolve-RootPath $SelectedOutputDir

  Add-Requirement $requirements "DOC-001" "The original 15-page build manual exists and remains the source of truth." $sourceDoc (Test-Path -LiteralPath $sourceDoc) $sourceDoc
  Add-Requirement $requirements "DOC-002" "The extracted plan text is available for requirement inspection." "output\build-plan-extracted.txt" (Test-Path -LiteralPath (Join-Path $Root "output\build-plan-extracted.txt")) "output\build-plan-extracted.txt"
  Add-Requirement $requirements "DOC-003" "Every manual page is mapped to implementation evidence and remaining gates." "docs\TRACEABILITY_AUDIT.md" (Test-Path -LiteralPath (Join-Path $Root "docs\TRACEABILITY_AUDIT.md")) "docs\TRACEABILITY_AUDIT.md"
  Add-Requirement $requirements "DOC-004" "Manual and automated acceptance gates are documented." "docs\ACCEPTANCE_TESTS.md" (Test-Path -LiteralPath (Join-Path $Root "docs\ACCEPTANCE_TESTS.md")) "docs\ACCEPTANCE_TESTS.md"
  Add-Requirement $requirements "DOC-005" "The free different-Wi-Fi Tailscale path is documented." "docs\TAILSCALE_VALIDATION.md" (Test-Path -LiteralPath (Join-Path $Root "docs\TAILSCALE_VALIDATION.md")) "docs\TAILSCALE_VALIDATION.md"
  Add-Requirement $requirements "DOC-006" "Daily-use packaging notes are documented." "docs\PACKAGING_NOTES.md" (Test-Path -LiteralPath (Join-Path $Root "docs\PACKAGING_NOTES.md")) "docs\PACKAGING_NOTES.md"
  Add-Requirement $requirements "DOC-010" "The active 10-page remote controller finalization manual exists." "docs\Remote_Controller_Finalization_Plan.docx" (Test-NonEmptyFile $finalizationDoc) $finalizationDoc
  $manualExtractPath = Join-Path $Root "output\build-plan-extracted.txt"
  $manualExtractText = if (Test-Path -LiteralPath $manualExtractPath -PathType Leaf) { Get-Content -Raw -LiteralPath $manualExtractPath } else { "" }
  $manualExtractMarkers = @(
    "01 Product Contract And Non-Negotiables",
    "02 System Architecture",
    "03 Free Remote Networking Plan",
    "04 Host Capture And Streaming",
    "05 Phone Control Model",
    "06 Input Injection Engine",
    "07 Monitor Selection And Coordinate Mapping",
    "08 Keyboard, Shortcuts, And Command Bar",
    "09 Security, Pairing, And Session Control",
    "10 Performance And Clean Optimization",
    "11 Visual Design System",
    "12 Testing, QA, And Safety Checks",
    "13 Packaging, Install, And Daily Use",
    "14 Build Execution Roadmap",
    "15 Master Goal List For The Whole Build",
    "Completion goals for this page",
    "Non-skippable build goals"
  )
  $missingManualExtractMarkers = @($manualExtractMarkers | Where-Object { $manualExtractText -notlike "*$_*" })
  Add-Requirement $requirements "DOC-007" "Extracted manual text contains all 15 page headings, page completion goal markers, and non-skippable build goals." "output\build-plan-extracted.txt" (
    $missingManualExtractMarkers.Count -eq 0
  ) $(if ($missingManualExtractMarkers.Count -eq 0) { "all required extracted manual markers present" } else { "missing markers: $($missingManualExtractMarkers -join ', ')" })
  $traceabilityPath = Join-Path $Root "docs\TRACEABILITY_AUDIT.md"
  $traceabilityText = if (Test-Path -LiteralPath $traceabilityPath -PathType Leaf) { Get-Content -Raw -LiteralPath $traceabilityPath } else { "" }
  $traceabilityMarkers = @(
    1..15 | ForEach-Object { "## Page {0:D2}" -f $_ }
  ) + @(
    "## Non-Skippable Final Gate Checklist",
    "Page completion goals:",
    "Same-Wi-Fi physical phone run must pass",
    "Tailscale/different-Wi-Fi physical phone run must pass"
  )
  $missingTraceabilityMarkers = @($traceabilityMarkers | Where-Object { $traceabilityText -notlike "*$_*" })
  Add-Requirement $requirements "DOC-008" "Traceability audit covers all 15 manual pages, page completion goals, and the non-skippable final physical gate checklist." "docs\TRACEABILITY_AUDIT.md" (
    $missingTraceabilityMarkers.Count -eq 0
  ) $(if ($missingTraceabilityMarkers.Count -eq 0) { "all required traceability markers present" } else { "missing markers: $($missingTraceabilityMarkers -join ', ')" })
  $nonSkippableTraceabilityMarkers = @(
    "Host scaffold with served PWA",
    "Pairing PIN, session token, laptop approval",
    "Monitor enumeration, selected-monitor capture",
    "Pointer, click, right click, drag lock",
    "Full-screen phone stream, top status strip",
    "Coordinate mapping tests cover the required monitor layouts",
    "Tailscale usage path is documented and implemented",
    "Visual QA, performance logs, reconnect behavior, idle throttling, and emergency disconnect"
  )
  $missingNonSkippableTraceabilityMarkers = @($nonSkippableTraceabilityMarkers | Where-Object { $traceabilityText -notlike "*$_*" })
  Add-Requirement $requirements "DOC-009" "Traceability audit explicitly maps the manual's eight non-skippable build goals to implemented evidence." "docs\TRACEABILITY_AUDIT.md" (
    $missingNonSkippableTraceabilityMarkers.Count -eq 0
  ) $(if ($missingNonSkippableTraceabilityMarkers.Count -eq 0) { "all non-skippable build goal markers present" } else { "missing markers: $($missingNonSkippableTraceabilityMarkers -join ', ')" })

  $finalizationText = Get-DocxPlainText $finalizationDoc
  $finalizationMarkers = @(
    "Remote Desktop Controller Finalization Manual",
    "Page 1 - Final Product Mission, Failure List, and Release Bar",
    "Page 2 - Coordinate Truth Layer and Bottom-Cursor Defect Fix",
    "Page 3 - Multi-Monitor Selection, Resolution Accuracy, and Calibration",
    "Page 4 - Zoom, Mouse-Follow, Edge Pan, and Cursor Magnification",
    "Page 5 - Touchpad, Mouse Speed, Gestures, and Dragging",
    "Page 6 - Keyboard, Scrolling, Text Entry, and Daily-Use Controls",
    "Page 7 - Streaming Speed, Latency, and Rendering Optimization",
    "Page 8 - Premium Mobile UI, Layout Polish, and Usability",
    "Page 9 - Security, Pairing, Authenticator Codes, and Packaging",
    "Page 10 - Execution Order, Acceptance Checklist, and Done Definition",
    "Completion goals for this page",
    "coordinateSpace",
    "mapHostCursorToFrame",
    "cursor lens",
    "Single tap sends a left click",
    "Double tap sends a right click",
    "double tap",
    "press and hold",
    "binary frame transport",
    "black and gold",
    "TOTP",
    "package should launch from a zip",
    "done only when"
  )
  $missingFinalizationMarkers = @($finalizationMarkers | Where-Object { $finalizationText -notlike "*$_*" })
  Add-Requirement $requirements "DOC-011" "The active finalization manual text is readable and contains all 10 page headings, page completion goals, and core release requirements." "docs\Remote_Controller_Finalization_Plan.docx" (
    $missingFinalizationMarkers.Count -eq 0
  ) $(if ($missingFinalizationMarkers.Count -eq 0) { "all required finalization-plan markers present" } else { "missing markers: $($missingFinalizationMarkers -join ', ')" })

  $finalizationTraceabilityPath = Join-Path $Root "docs\FINALIZATION_TRACEABILITY.md"
  $finalizationTraceabilityText = if (Test-Path -LiteralPath $finalizationTraceabilityPath -PathType Leaf) { Get-Content -Raw -LiteralPath $finalizationTraceabilityPath } else { "" }
  $finalizationTraceabilityMarkers = @(
    "C:\RemoteDesktopControllerPlan\remote-control-mvp\docs\Remote_Controller_Finalization_Plan.docx",
    "## Page 01 - Final Product Mission, Failure List, and Release Bar",
    "## Page 02 - Coordinate Truth Layer and Bottom-Cursor Defect Fix",
    "## Page 03 - Multi-Monitor Selection, Resolution Accuracy, and Calibration",
    "## Page 04 - Zoom, Mouse-Follow, Edge Pan, and Cursor Magnification",
    "## Page 05 - Touchpad, Mouse Speed, Gestures, and Dragging",
    "## Page 06 - Keyboard, Scrolling, Text Entry, and Daily-Use Controls",
    "## Page 07 - Streaming Speed, Latency, and Rendering Optimization",
    "## Page 08 - Premium Mobile UI, Layout Polish, and Usability",
    "## Page 09 - Security, Pairing, Authenticator Codes, and Packaging",
    "## Page 10 - Execution Order, Acceptance Checklist, and Done Definition",
    "## Remaining Final Gate",
    "npm run acceptance:verify:save -- -Gate same-wifi",
    "npm run acceptance:verify:save -- -Gate tailscale"
  )
  $missingFinalizationTraceabilityMarkers = @($finalizationTraceabilityMarkers | Where-Object { $finalizationTraceabilityText -notlike "*$_*" })
  Add-Requirement $requirements "DOC-012" "Finalization traceability maps every active 10-page manual page to implementation evidence and the remaining physical gates." "docs\FINALIZATION_TRACEABILITY.md" (
    $missingFinalizationTraceabilityMarkers.Count -eq 0
  ) $(if ($missingFinalizationTraceabilityMarkers.Count -eq 0) { "all required finalization traceability markers present" } else { "missing markers: $($missingFinalizationTraceabilityMarkers -join ', ')" })

  foreach ($scriptPath in @(
    "scripts\run-qa.ps1",
    "scripts\acceptance-report.ps1",
    "scripts\manual-phone-acceptance.ps1",
    "scripts\acceptance-doctor.ps1",
    "scripts\prepare-phone-acceptance.ps1",
    "scripts\acceptance-ready.ps1",
    "scripts\acceptance-next.ps1",
    "scripts\physical-proof-runbook.ps1",
    "scripts\physical-proof-launch.ps1",
    "scripts\acceptance-dashboard.ps1",
    "scripts\acceptance-handoff.ps1",
    "scripts\acceptance-refresh.ps1",
    "scripts\finalize-physical-evidence.ps1",
    "scripts\attach-phone-evidence.ps1",
    "scripts\stop-phone-acceptance.ps1",
    "scripts\verify-phone-acceptance.ps1",
    "scripts\watch-phone-acceptance.ps1",
    "scripts\tailscale-setup-check.ps1",
    "scripts\tailscale-bootstrap.ps1",
    "scripts\evidence-bundle.ps1",
    "scripts\firewall-rule.ps1",
    "scripts\firewall-handoff.ps1",
    "scripts\tray-host.ps1",
    "scripts\install-shortcut.ps1",
    "scripts\install-autostart.ps1",
    "scripts\uninstall-autostart.ps1",
    "scripts\dependency-audit.ps1"
  )) {
    Add-Requirement $requirements "SCRIPT" "Required execution script exists: $scriptPath" $scriptPath (Test-Path -LiteralPath (Join-Path $Root $scriptPath)) $scriptPath
  }

  foreach ($scriptName in @(
    "qa",
    "acceptance:report",
    "acceptance:selftest",
    "acceptance:phone",
    "acceptance:phone:selftest",
    "acceptance:doctor",
    "acceptance:doctor:selftest",
    "acceptance:prepare",
    "acceptance:prepare:selftest",
    "acceptance:ready",
    "acceptance:ready:selftest",
    "acceptance:next",
    "acceptance:next:selftest",
    "acceptance:runbook",
    "acceptance:runbook:selftest",
    "acceptance:launch",
    "acceptance:launch:selftest",
    "acceptance:dashboard",
    "acceptance:dashboard:selftest",
    "acceptance:handoff",
    "acceptance:handoff:selftest",
    "acceptance:refresh",
    "acceptance:refresh:selftest",
    "acceptance:finalize",
    "acceptance:finalize:selftest",
    "acceptance:attach",
    "acceptance:attach:selftest",
    "acceptance:stop",
    "acceptance:stop:selftest",
    "acceptance:verify",
    "acceptance:verify:save",
    "acceptance:verify:selftest",
    "acceptance:watch",
    "acceptance:watch:selftest",
    "tailscale:check",
    "tailscale:check:save",
    "tailscale:check:selftest",
    "tailscale:bootstrap",
    "tailscale:bootstrap:save",
    "tailscale:bootstrap:selftest",
    "firewall:status",
    "firewall:install",
    "firewall:remove",
    "firewall:handoff",
    "firewall:handoff:selftest",
    "firewall:selftest",
    "tray",
    "shortcut:install",
    "shortcut:selftest",
    "autostart:install",
    "autostart:uninstall",
    "autostart:selftest",
    "dependency:audit",
    "dependency:audit:save",
    "dependency:audit:selftest",
    "completion:audit",
    "completion:audit:save",
    "completion:audit:selftest",
    "evidence:bundle",
    "evidence:bundle:selftest"
  )) {
    Add-Requirement $requirements "PKG" "Package script is exposed: $scriptName" "package.json scripts.$scriptName" (Test-PackageScript -Package $package -ScriptName $scriptName) "package.json"
  }

  $packageCommandTargets = @(
    [pscustomobject]@{ name = "start"; fragments = @("CAPTURE_MODE=screen", "REAL_INPUT=1", "QUALITY_DEFAULT=fast", "node src/server.js") },
    [pscustomobject]@{ name = "start:screen"; fragments = @("CAPTURE_MODE=screen", "REAL_INPUT=1", "QUALITY_DEFAULT=fast", "node src/server.js") },
    [pscustomobject]@{ name = "start:fake"; fragments = @("CAPTURE_MODE=fake", "node src/server.js") },
    [pscustomobject]@{ name = "test"; fragments = @("node --test") },
    [pscustomobject]@{ name = "qa"; fragments = @("scripts/run-qa.ps1", "-Save") },
    [pscustomobject]@{ name = "tray"; fragments = @("scripts/tray-host.ps1") },
    [pscustomobject]@{ name = "acceptance:report"; fragments = @("scripts/acceptance-report.ps1") },
    [pscustomobject]@{ name = "acceptance:selftest"; fragments = @("scripts/acceptance-report.ps1", "-SelfTest") },
    [pscustomobject]@{ name = "acceptance:phone"; fragments = @("scripts/manual-phone-acceptance.ps1") },
    [pscustomobject]@{ name = "acceptance:phone:selftest"; fragments = @("scripts/manual-phone-acceptance.ps1", "-SelfTest") },
    [pscustomobject]@{ name = "acceptance:doctor"; fragments = @("scripts/acceptance-doctor.ps1") },
    [pscustomobject]@{ name = "acceptance:doctor:selftest"; fragments = @("scripts/acceptance-doctor.ps1", "-SelfTest") },
    [pscustomobject]@{ name = "acceptance:prepare"; fragments = @("scripts/prepare-phone-acceptance.ps1") },
    [pscustomobject]@{ name = "acceptance:prepare:selftest"; fragments = @("scripts/prepare-phone-acceptance.ps1", "-SelfTest") },
    [pscustomobject]@{ name = "acceptance:ready"; fragments = @("scripts/acceptance-ready.ps1") },
    [pscustomobject]@{ name = "acceptance:ready:selftest"; fragments = @("scripts/acceptance-ready.ps1", "-SelfTest") },
    [pscustomobject]@{ name = "acceptance:next"; fragments = @("scripts/acceptance-next.ps1") },
    [pscustomobject]@{ name = "acceptance:next:selftest"; fragments = @("scripts/acceptance-next.ps1", "-SelfTest") },
    [pscustomobject]@{ name = "acceptance:runbook"; fragments = @("scripts/physical-proof-runbook.ps1") },
    [pscustomobject]@{ name = "acceptance:runbook:selftest"; fragments = @("scripts/physical-proof-runbook.ps1", "-SelfTest") },
    [pscustomobject]@{ name = "acceptance:launch"; fragments = @("scripts/physical-proof-launch.ps1") },
    [pscustomobject]@{ name = "acceptance:launch:selftest"; fragments = @("scripts/physical-proof-launch.ps1", "-SelfTest") },
    [pscustomobject]@{ name = "acceptance:dashboard"; fragments = @("scripts/acceptance-dashboard.ps1") },
    [pscustomobject]@{ name = "acceptance:dashboard:selftest"; fragments = @("scripts/acceptance-dashboard.ps1", "-SelfTest") },
    [pscustomobject]@{ name = "acceptance:handoff"; fragments = @("scripts/acceptance-handoff.ps1") },
    [pscustomobject]@{ name = "acceptance:handoff:selftest"; fragments = @("scripts/acceptance-handoff.ps1", "-SelfTest") },
    [pscustomobject]@{ name = "acceptance:refresh"; fragments = @("scripts/acceptance-refresh.ps1") },
    [pscustomobject]@{ name = "acceptance:refresh:selftest"; fragments = @("scripts/acceptance-refresh.ps1", "-SelfTest") },
    [pscustomobject]@{ name = "acceptance:finalize"; fragments = @("scripts/finalize-physical-evidence.ps1") },
    [pscustomobject]@{ name = "acceptance:finalize:selftest"; fragments = @("scripts/finalize-physical-evidence.ps1", "-SelfTest") },
    [pscustomobject]@{ name = "acceptance:attach"; fragments = @("scripts/attach-phone-evidence.ps1") },
    [pscustomobject]@{ name = "acceptance:attach:selftest"; fragments = @("scripts/attach-phone-evidence.ps1", "-SelfTest") },
    [pscustomobject]@{ name = "acceptance:stop"; fragments = @("scripts/stop-phone-acceptance.ps1") },
    [pscustomobject]@{ name = "acceptance:stop:selftest"; fragments = @("scripts/stop-phone-acceptance.ps1", "-SelfTest") },
    [pscustomobject]@{ name = "acceptance:verify"; fragments = @("scripts/verify-phone-acceptance.ps1") },
    [pscustomobject]@{ name = "acceptance:verify:save"; fragments = @("scripts/verify-phone-acceptance.ps1", "-Save") },
    [pscustomobject]@{ name = "acceptance:verify:selftest"; fragments = @("scripts/verify-phone-acceptance.ps1", "-SelfTest") },
    [pscustomobject]@{ name = "acceptance:watch"; fragments = @("scripts/watch-phone-acceptance.ps1") },
    [pscustomobject]@{ name = "acceptance:watch:selftest"; fragments = @("scripts/watch-phone-acceptance.ps1", "-SelfTest") },
    [pscustomobject]@{ name = "tailscale:check"; fragments = @("scripts/tailscale-setup-check.ps1") },
    [pscustomobject]@{ name = "tailscale:check:save"; fragments = @("scripts/tailscale-setup-check.ps1", "-Save") },
    [pscustomobject]@{ name = "tailscale:check:selftest"; fragments = @("scripts/tailscale-setup-check.ps1", "-SelfTest") },
    [pscustomobject]@{ name = "tailscale:bootstrap"; fragments = @("scripts/tailscale-bootstrap.ps1") },
    [pscustomobject]@{ name = "tailscale:bootstrap:save"; fragments = @("scripts/tailscale-bootstrap.ps1", "-Save") },
    [pscustomobject]@{ name = "tailscale:bootstrap:selftest"; fragments = @("scripts/tailscale-bootstrap.ps1", "-SelfTest") },
    [pscustomobject]@{ name = "firewall:status"; fragments = @("scripts/firewall-rule.ps1", "-Action status") },
    [pscustomobject]@{ name = "firewall:install"; fragments = @("scripts/firewall-rule.ps1", "-Action install") },
    [pscustomobject]@{ name = "firewall:remove"; fragments = @("scripts/firewall-rule.ps1", "-Action remove") },
    [pscustomobject]@{ name = "firewall:handoff"; fragments = @("scripts/firewall-handoff.ps1") },
    [pscustomobject]@{ name = "firewall:handoff:selftest"; fragments = @("scripts/firewall-handoff.ps1", "-SelfTest") },
    [pscustomobject]@{ name = "firewall:selftest"; fragments = @("scripts/firewall-rule.ps1", "-SelfTest") },
    [pscustomobject]@{ name = "shortcut:install"; fragments = @("scripts/install-shortcut.ps1") },
    [pscustomobject]@{ name = "shortcut:selftest"; fragments = @("scripts/install-shortcut.ps1", "-SelfTest") },
    [pscustomobject]@{ name = "dependency:audit"; fragments = @("scripts/dependency-audit.ps1") },
    [pscustomobject]@{ name = "dependency:audit:save"; fragments = @("scripts/dependency-audit.ps1", "-Save") },
    [pscustomobject]@{ name = "dependency:audit:selftest"; fragments = @("scripts/dependency-audit.ps1", "-SelfTest") },
    [pscustomobject]@{ name = "completion:audit"; fragments = @("scripts/completion-audit.ps1") },
    [pscustomobject]@{ name = "completion:audit:save"; fragments = @("scripts/completion-audit.ps1", "-Save") },
    [pscustomobject]@{ name = "completion:audit:selftest"; fragments = @("scripts/completion-audit.ps1", "-SelfTest") },
    [pscustomobject]@{ name = "evidence:bundle"; fragments = @("scripts/evidence-bundle.ps1") },
    [pscustomobject]@{ name = "evidence:bundle:selftest"; fragments = @("scripts/evidence-bundle.ps1", "-SelfTest") },
    [pscustomobject]@{ name = "autostart:install"; fragments = @("scripts/install-autostart.ps1") },
    [pscustomobject]@{ name = "autostart:uninstall"; fragments = @("scripts/uninstall-autostart.ps1") },
    [pscustomobject]@{ name = "autostart:selftest"; fragments = @("scripts/install-autostart.ps1", "-SelfTest") }
  )
  $wrongPackageCommandTargets = @($packageCommandTargets | Where-Object {
    -not (Test-PackageScriptContains -Package $package -ScriptName $_.name -Fragments $_.fragments)
  })
  Add-Requirement $requirements "PKG-CMD-001" "Required package scripts invoke the expected implementation files and critical flags." "package.json scripts" (
    $wrongPackageCommandTargets.Count -eq 0
  ) $(if ($wrongPackageCommandTargets.Count -eq 0) { "all checked package scripts point at expected targets" } else { "wrong targets: $(@($wrongPackageCommandTargets | ForEach-Object { $_.name }) -join ', ')" })

  foreach ($artifact in @(
    [pscustomobject]@{ id = "ARTIFACT-001"; requirement = "Latest same-Wi-Fi readiness JSON exists and is non-empty."; path = "phone-acceptance-ready-same-wifi-latest.json" },
    [pscustomobject]@{ id = "ARTIFACT-002"; requirement = "Latest Tailscale readiness JSON exists and is non-empty."; path = "phone-acceptance-ready-tailscale-latest.json" },
    [pscustomobject]@{ id = "ARTIFACT-003"; requirement = "Latest physical next-action Markdown exists and is non-empty."; path = "phone-acceptance-next-latest.md" },
    [pscustomobject]@{ id = "ARTIFACT-004"; requirement = "Latest physical next-action JSON exists and is non-empty."; path = "phone-acceptance-next-latest.json" },
    [pscustomobject]@{ id = "ARTIFACT-026"; requirement = "Latest physical proof runbook Markdown exists and is non-empty."; path = "physical-proof-runbook-latest.md" },
    [pscustomobject]@{ id = "ARTIFACT-027"; requirement = "Latest physical proof runbook JSON exists and is non-empty."; path = "physical-proof-runbook-latest.json" },
    [pscustomobject]@{ id = "ARTIFACT-028"; requirement = "Latest same-Wi-Fi physical proof launch Markdown exists and is non-empty."; path = "physical-proof-launch-same-wifi-latest.md" },
    [pscustomobject]@{ id = "ARTIFACT-029"; requirement = "Latest same-Wi-Fi physical proof launch JSON exists and is non-empty."; path = "physical-proof-launch-same-wifi-latest.json" },
    [pscustomobject]@{ id = "ARTIFACT-030"; requirement = "Latest Tailscale physical proof launch Markdown exists and is non-empty."; path = "physical-proof-launch-tailscale-latest.md" },
    [pscustomobject]@{ id = "ARTIFACT-031"; requirement = "Latest Tailscale physical proof launch JSON exists and is non-empty."; path = "physical-proof-launch-tailscale-latest.json" },
    [pscustomobject]@{ id = "ARTIFACT-005"; requirement = "Latest physical dashboard HTML exists and is non-empty."; path = "phone-acceptance-dashboard-latest.html" },
    [pscustomobject]@{ id = "ARTIFACT-006"; requirement = "Latest physical dashboard JSON exists and is non-empty."; path = "phone-acceptance-dashboard-latest.json" },
    [pscustomobject]@{ id = "ARTIFACT-007"; requirement = "Latest physical phone handoff HTML exists and is non-empty."; path = "phone-acceptance-handoff-latest.html" },
    [pscustomobject]@{ id = "ARTIFACT-008"; requirement = "Latest physical phone handoff Markdown exists and is non-empty."; path = "phone-acceptance-handoff-latest.md" },
    [pscustomobject]@{ id = "ARTIFACT-009"; requirement = "Latest physical phone handoff JSON exists and is non-empty."; path = "phone-acceptance-handoff-latest.json" },
    [pscustomobject]@{ id = "ARTIFACT-010"; requirement = "Latest evidence bundle Markdown exists and is non-empty."; path = "remote-controller-evidence-bundle-latest.md" },
    [pscustomobject]@{ id = "ARTIFACT-011"; requirement = "Latest evidence bundle JSON exists and is non-empty."; path = "remote-controller-evidence-bundle-latest.json" },
    [pscustomobject]@{ id = "ARTIFACT-012"; requirement = "Latest same-Wi-Fi verifier JSON exists and is non-empty."; path = "phone-acceptance-verification-same-wifi-latest.json" },
    [pscustomobject]@{ id = "ARTIFACT-013"; requirement = "Latest Tailscale verifier JSON exists and is non-empty."; path = "phone-acceptance-verification-tailscale-latest.json" },
    [pscustomobject]@{ id = "ARTIFACT-014"; requirement = "Latest acceptance refresh Markdown exists and is non-empty."; path = "phone-acceptance-refresh-latest.md" },
    [pscustomobject]@{ id = "ARTIFACT-015"; requirement = "Latest acceptance refresh JSON exists and is non-empty."; path = "phone-acceptance-refresh-latest.json" },
    [pscustomobject]@{ id = "ARTIFACT-016"; requirement = "Latest Tailscale bootstrap Markdown exists and is non-empty."; path = "tailscale-bootstrap-latest.md" },
    [pscustomobject]@{ id = "ARTIFACT-017"; requirement = "Latest Tailscale bootstrap JSON exists and is non-empty."; path = "tailscale-bootstrap-latest.json" },
    [pscustomobject]@{ id = "ARTIFACT-018"; requirement = "Latest QA report Markdown exists and is non-empty."; path = "qa-report-latest.md" },
    [pscustomobject]@{ id = "ARTIFACT-019"; requirement = "Latest QA report JSON exists and is non-empty."; path = "qa-report-latest.json" },
    [pscustomobject]@{ id = "ARTIFACT-020"; requirement = "Latest same-Wi-Fi physical watcher JSON exists and is non-empty."; path = "phone-acceptance-watch-same-wifi-latest.json" },
    [pscustomobject]@{ id = "ARTIFACT-021"; requirement = "Latest Tailscale physical watcher JSON exists and is non-empty."; path = "phone-acceptance-watch-tailscale-latest.json" },
    [pscustomobject]@{ id = "ARTIFACT-022"; requirement = "Latest dependency audit JSON exists and is non-empty."; path = "dependency-audit-latest.json" },
    [pscustomobject]@{ id = "ARTIFACT-023"; requirement = "Latest dependency audit Markdown exists and is non-empty."; path = "dependency-audit-latest.md" },
    [pscustomobject]@{ id = "ARTIFACT-024"; requirement = "Latest physical evidence finalization JSON exists and is non-empty when finalization has been run."; path = "physical-evidence-finalization-latest.json" },
    [pscustomobject]@{ id = "ARTIFACT-025"; requirement = "Latest physical evidence finalization Markdown exists and is non-empty when finalization has been run."; path = "physical-evidence-finalization-latest.md" },
    [pscustomobject]@{ id = "ARTIFACT-032"; requirement = "Latest local-Wi-Fi package smoke JSON exists and is non-empty."; path = "package-smoke-latest.json" }
  )) {
    Add-ArtifactRequirement $requirements $artifact.id $artifact.requirement $artifact.path $SelectedOutputDir
  }

  $artifactRoot = Resolve-RootPath $SelectedOutputDir
  $sameReady = Read-JsonFile (Join-Path $artifactRoot "phone-acceptance-ready-same-wifi-latest.json")
  $tailscaleReady = Read-JsonFile (Join-Path $artifactRoot "phone-acceptance-ready-tailscale-latest.json")
  $sameWatch = Read-JsonFile (Join-Path $artifactRoot "phone-acceptance-watch-same-wifi-latest.json")
  $tailscaleWatch = Read-JsonFile (Join-Path $artifactRoot "phone-acceptance-watch-tailscale-latest.json")
  $next = Read-JsonFile (Join-Path $artifactRoot "phone-acceptance-next-latest.json")
  $runbook = Read-JsonFile (Join-Path $artifactRoot "physical-proof-runbook-latest.json")
  $runbookMarkdownPath = Join-Path $artifactRoot "physical-proof-runbook-latest.md"
  $runbookMarkdown = if (Test-Path -LiteralPath $runbookMarkdownPath -PathType Leaf) { Get-Content -Raw -LiteralPath $runbookMarkdownPath } else { "" }
  $handoff = Read-JsonFile (Join-Path $artifactRoot "phone-acceptance-handoff-latest.json")
  $dashboard = Read-JsonFile (Join-Path $artifactRoot "phone-acceptance-dashboard-latest.json")
  $bundle = Read-JsonFile (Join-Path $artifactRoot "remote-controller-evidence-bundle-latest.json")
  $refresh = Read-JsonFile (Join-Path $artifactRoot "phone-acceptance-refresh-latest.json")
  $qaReport = Read-JsonFile (Join-Path $artifactRoot "qa-report-latest.json")
  $packageSmoke = Read-JsonFile (Join-Path $artifactRoot "package-smoke-latest.json")
  $visualProof = Read-JsonFile (Join-Path $artifactRoot "live-phone-visual-proof-latest.json")
  $visualProofScreenshotPath = Join-Path $artifactRoot "live-phone-visual-proof-latest.png"
  $dependencyAudit = Read-JsonFile (Join-Path $artifactRoot "dependency-audit-latest.json")
  $tailscaleBootstrap = Read-JsonFile (Join-Path $artifactRoot "tailscale-bootstrap-latest.json")
  $tailscaleSetupCheck = Read-JsonFile (Join-Path $artifactRoot "tailscale-setup-check-latest.json")
  $qaReportMarkdownPath = Join-Path $artifactRoot "qa-report-latest.md"
  $qaReportMarkdown = if (Test-Path -LiteralPath $qaReportMarkdownPath -PathType Leaf) { Get-Content -Raw -LiteralPath $qaReportMarkdownPath } else { "" }
  $handoffMarkdownPath = Join-Path $artifactRoot "phone-acceptance-handoff-latest.md"
  $handoffMarkdown = if (Test-Path -LiteralPath $handoffMarkdownPath -PathType Leaf) { Get-Content -Raw -LiteralPath $handoffMarkdownPath } else { "" }
  $sameLaunchMarkdownPath = Join-Path $artifactRoot "physical-proof-launch-same-wifi-latest.md"
  $sameLaunchMarkdown = if (Test-Path -LiteralPath $sameLaunchMarkdownPath -PathType Leaf) { Get-Content -Raw -LiteralPath $sameLaunchMarkdownPath } else { "" }
  $tailscaleLaunchMarkdownPath = Join-Path $artifactRoot "physical-proof-launch-tailscale-latest.md"
  $tailscaleLaunchMarkdown = if (Test-Path -LiteralPath $tailscaleLaunchMarkdownPath -PathType Leaf) { Get-Content -Raw -LiteralPath $tailscaleLaunchMarkdownPath } else { "" }
  $sameLaunch = Read-JsonFile (Join-Path $artifactRoot "physical-proof-launch-same-wifi-latest.json")
  $tailscaleLaunch = Read-JsonFile (Join-Path $artifactRoot "physical-proof-launch-tailscale-latest.json")
  $phoneAppPath = Join-Path $Root "public\app.js"
  $phoneAppText = if (Test-Path -LiteralPath $phoneAppPath -PathType Leaf) { Get-Content -Raw -LiteralPath $phoneAppPath } else { "" }
  $phoneTestPath = Join-Path $Root "test\phone-connection-help.test.js"
  $phoneTestText = if (Test-Path -LiteralPath $phoneTestPath -PathType Leaf) { Get-Content -Raw -LiteralPath $phoneTestPath } else { "" }
  $hostConsolePath = Join-Path $Root "public\host.js"
  $hostConsoleText = if (Test-Path -LiteralPath $hostConsolePath -PathType Leaf) { Get-Content -Raw -LiteralPath $hostConsolePath } else { "" }
  $hostConsoleTestPath = Join-Path $Root "test\host-console.test.js"
  $hostConsoleTestText = if (Test-Path -LiteralPath $hostConsoleTestPath -PathType Leaf) { Get-Content -Raw -LiteralPath $hostConsoleTestPath } else { "" }
  $phoneVerifierPath = Join-Path $Root "scripts\verify-phone-acceptance.ps1"
  $phoneVerifierText = if (Test-Path -LiteralPath $phoneVerifierPath -PathType Leaf) { Get-Content -Raw -LiteralPath $phoneVerifierPath } else { "" }
  $visualProofScriptPath = Join-Path $Root "scripts\live-phone-visual-proof.js"
  $visualProofScriptText = if (Test-Path -LiteralPath $visualProofScriptPath -PathType Leaf) { Get-Content -Raw -LiteralPath $visualProofScriptPath } else { "" }
  $acceptanceDoctorPath = Join-Path $Root "scripts\acceptance-doctor.ps1"
  $acceptanceDoctorText = if (Test-Path -LiteralPath $acceptanceDoctorPath -PathType Leaf) { Get-Content -Raw -LiteralPath $acceptanceDoctorPath } else { "" }
  $acceptanceReportPath = Join-Path $Root "scripts\acceptance-report.ps1"
  $acceptanceReportText = if (Test-Path -LiteralPath $acceptanceReportPath -PathType Leaf) { Get-Content -Raw -LiteralPath $acceptanceReportPath } else { "" }
  $manualAcceptancePath = Join-Path $Root "scripts\manual-phone-acceptance.ps1"
  $manualAcceptanceText = if (Test-Path -LiteralPath $manualAcceptancePath -PathType Leaf) { Get-Content -Raw -LiteralPath $manualAcceptancePath } else { "" }
  $preparePhonePath = Join-Path $Root "scripts\prepare-phone-acceptance.ps1"
  $preparePhoneText = if (Test-Path -LiteralPath $preparePhonePath -PathType Leaf) { Get-Content -Raw -LiteralPath $preparePhonePath } else { "" }
  $acceptanceReadyPath = Join-Path $Root "scripts\acceptance-ready.ps1"
  $acceptanceReadyText = if (Test-Path -LiteralPath $acceptanceReadyPath -PathType Leaf) { Get-Content -Raw -LiteralPath $acceptanceReadyPath } else { "" }
  $tailscaleBootstrapPath = Join-Path $Root "scripts\tailscale-bootstrap.ps1"
  $tailscaleBootstrapText = if (Test-Path -LiteralPath $tailscaleBootstrapPath -PathType Leaf) { Get-Content -Raw -LiteralPath $tailscaleBootstrapPath } else { "" }
  $tailscaleSetupCheckPath = Join-Path $Root "scripts\tailscale-setup-check.ps1"
  $tailscaleSetupCheckText = if (Test-Path -LiteralPath $tailscaleSetupCheckPath -PathType Leaf) { Get-Content -Raw -LiteralPath $tailscaleSetupCheckPath } else { "" }
  $acceptanceNextPath = Join-Path $Root "scripts\acceptance-next.ps1"
  $acceptanceNextText = if (Test-Path -LiteralPath $acceptanceNextPath -PathType Leaf) { Get-Content -Raw -LiteralPath $acceptanceNextPath } else { "" }
  $physicalRunbookPath = Join-Path $Root "scripts\physical-proof-runbook.ps1"
  $physicalRunbookText = if (Test-Path -LiteralPath $physicalRunbookPath -PathType Leaf) { Get-Content -Raw -LiteralPath $physicalRunbookPath } else { "" }
  $physicalLaunchPath = Join-Path $Root "scripts\physical-proof-launch.ps1"
  $physicalLaunchText = if (Test-Path -LiteralPath $physicalLaunchPath -PathType Leaf) { Get-Content -Raw -LiteralPath $physicalLaunchPath } else { "" }
  $firewallHandoffPath = Join-Path $Root "scripts\firewall-handoff.ps1"
  $firewallHandoffText = if (Test-Path -LiteralPath $firewallHandoffPath -PathType Leaf) { Get-Content -Raw -LiteralPath $firewallHandoffPath } else { "" }
  $installShortcutPath = Join-Path $Root "scripts\install-shortcut.ps1"
  $installShortcutText = if (Test-Path -LiteralPath $installShortcutPath -PathType Leaf) { Get-Content -Raw -LiteralPath $installShortcutPath } else { "" }
  $acceptanceDashboardPath = Join-Path $Root "scripts\acceptance-dashboard.ps1"
  $acceptanceDashboardText = if (Test-Path -LiteralPath $acceptanceDashboardPath -PathType Leaf) { Get-Content -Raw -LiteralPath $acceptanceDashboardPath } else { "" }
  $acceptanceHandoffPath = Join-Path $Root "scripts\acceptance-handoff.ps1"
  $acceptanceHandoffText = if (Test-Path -LiteralPath $acceptanceHandoffPath -PathType Leaf) { Get-Content -Raw -LiteralPath $acceptanceHandoffPath } else { "" }
  $acceptanceRefreshPath = Join-Path $Root "scripts\acceptance-refresh.ps1"
  $acceptanceRefreshText = if (Test-Path -LiteralPath $acceptanceRefreshPath -PathType Leaf) { Get-Content -Raw -LiteralPath $acceptanceRefreshPath } else { "" }
  $physicalFinalizePath = Join-Path $Root "scripts\finalize-physical-evidence.ps1"
  $physicalFinalizeText = if (Test-Path -LiteralPath $physicalFinalizePath -PathType Leaf) { Get-Content -Raw -LiteralPath $physicalFinalizePath } else { "" }
  $evidenceBundlePath = Join-Path $Root "scripts\evidence-bundle.ps1"
  $evidenceBundleText = if (Test-Path -LiteralPath $evidenceBundlePath -PathType Leaf) { Get-Content -Raw -LiteralPath $evidenceBundlePath } else { "" }
  $acceptanceTestsPath = Join-Path $Root "docs\ACCEPTANCE_TESTS.md"
  $acceptanceTestsText = if (Test-Path -LiteralPath $acceptanceTestsPath -PathType Leaf) { Get-Content -Raw -LiteralPath $acceptanceTestsPath } else { "" }
  $packagingNotesPath = Join-Path $Root "docs\PACKAGING_NOTES.md"
  $packagingNotesText = if (Test-Path -LiteralPath $packagingNotesPath -PathType Leaf) { Get-Content -Raw -LiteralPath $packagingNotesPath } else { "" }
  $readmePath = Join-Path $Root "README.md"
  $readmeText = if (Test-Path -LiteralPath $readmePath -PathType Leaf) { Get-Content -Raw -LiteralPath $readmePath } else { "" }
  $sameHandoff = Get-GateRecord $handoff "same-wifi"
  $tailscaleHandoff = Get-GateRecord $handoff "tailscale"
  $sameDashboard = Get-GateRecord $dashboard "same-wifi"
  $tailscaleDashboard = Get-GateRecord $dashboard "tailscale"
  $sameBundle = Get-GateRecord $bundle "same-wifi"
  $tailscaleBundle = Get-GateRecord $bundle "tailscale"

  Add-ContentRequirement $requirements "CONTENT-001" "Latest same-Wi-Fi readiness says the same-Wi-Fi gate is reachable and exposes a gate-aware phone URL." "phone-acceptance-ready-same-wifi-latest.json" (
    $sameReady -and "$($sameReady.gate)" -eq "same-wifi" -and $sameReady.hostHealth -and $sameReady.hostHealth.reachable -eq $true -and (Test-AnyStringContains $sameReady.phoneUrls "gate=same-wifi")
  ) $(if ($sameReady) { "gate=$($sameReady.gate), reachable=$($sameReady.hostHealth.reachable), urls=$((ConvertTo-StringArray $sameReady.phoneUrls) -join ', ')" } else { "missing or invalid JSON" })

  Add-ContentRequirement $requirements "CONTENT-002" "Latest Tailscale readiness is for the Tailscale gate and records either a Tailscale URL or setup actions." "phone-acceptance-ready-tailscale-latest.json" (
    $tailscaleReady -and "$($tailscaleReady.gate)" -eq "tailscale" -and ((Test-AnyStringContains $tailscaleReady.phoneUrls "gate=tailscale") -or @($tailscaleReady.readyActions).Count -gt 0 -or @($tailscaleReady.prepareFailures).Count -gt 0)
  ) $(if ($tailscaleReady) { "gate=$($tailscaleReady.gate), urls=$((ConvertTo-StringArray $tailscaleReady.phoneUrls) -join ', '), readyActions=$(@($tailscaleReady.readyActions).Count), prepareFailures=$(@($tailscaleReady.prepareFailures).Count)" } else { "missing or invalid JSON" })

  $sameReadyStatusAllowed = @("ready-for-phone", "complete")
  $tailscaleReadyStatusAllowed = @("ready-for-phone", "setup-needed", "complete", "needs-attention")
  $sameReadyPhoneUrls = @(ConvertTo-StringArray $sameReady.phoneUrls)
  $sameReadyFirstPhoneUrl = if ($sameReadyPhoneUrls.Count -gt 0) { "$($sameReadyPhoneUrls[0])" } else { "" }
  $tailscaleReadyPhoneUrls = @(ConvertTo-StringArray $tailscaleReady.phoneUrls)
  $sameNext = Get-GateRecord $next "same-wifi"
  $tailscaleNext = Get-GateRecord $next "tailscale"
  Add-ContentRequirement $requirements "CONTENT-023" "Latest readiness artifacts expose normalized status, primary phone URL, and blocker counts for both physical gates." "phone-acceptance-ready-*-latest.json" (
    $sameReady -and
    $tailscaleReady -and
    $sameReadyStatusAllowed -contains "$($sameReady.status)" -and
    (Test-AnyStringContains @($sameReady.primaryPhoneUrl) "gate=same-wifi") -and
    "$($sameReady.primaryPhoneUrl)" -eq $sameReadyFirstPhoneUrl -and
    $null -ne $sameReady.setupBlockerCount -and
    $null -ne $sameReady.physicalBlockerCount -and
    $tailscaleReadyStatusAllowed -contains "$($tailscaleReady.status)" -and
    (
      ($tailscaleReadyPhoneUrls.Count -gt 0 -and (Test-AnyStringContains @($tailscaleReady.primaryPhoneUrl) "gate=tailscale")) -or
      ($tailscaleReadyPhoneUrls.Count -eq 0 -and @($tailscaleReady.readyActions).Count -gt 0)
    ) -and
    $null -ne $tailscaleReady.setupBlockerCount -and
    $null -ne $tailscaleReady.physicalBlockerCount
  ) $(if ($sameReady -and $tailscaleReady) { "sameStatus=$($sameReady.status), samePrimary=$($sameReady.primaryPhoneUrl), tailscaleStatus=$($tailscaleReady.status), tailscalePrimary=$($tailscaleReady.primaryPhoneUrl), tailscaleActions=$(@($tailscaleReady.readyActions).Count)" } else { "missing readiness JSON" })

  Add-ContentRequirement $requirements "CONTENT-024" "Latest next-action, dashboard, and handoff artifacts preserve readiness status and primary phone URL from the source readiness records." "phone-acceptance-next/dashboard/handoff-latest.json" (
    $sameReady -and
    $tailscaleReady -and
    $sameNext -and
    $tailscaleNext -and
    $sameDashboard -and
    $tailscaleDashboard -and
    $sameHandoff -and
    $tailscaleHandoff -and
    "$($sameNext.status)" -eq "$($sameReady.status)" -and
    "$($sameDashboard.status)" -eq "$($sameReady.status)" -and
    "$($sameHandoff.status)" -eq "$($sameReady.status)" -and
    "$($sameNext.primaryPhoneUrl)" -eq "$($sameReady.primaryPhoneUrl)" -and
    "$($sameDashboard.primaryPhoneUrl)" -eq "$($sameReady.primaryPhoneUrl)" -and
    "$($sameHandoff.primaryPhoneUrl)" -eq "$($sameReady.primaryPhoneUrl)" -and
    "$($tailscaleNext.status)" -eq "$($tailscaleReady.status)" -and
    "$($tailscaleDashboard.status)" -eq "$($tailscaleReady.status)" -and
    "$($tailscaleHandoff.status)" -eq "$($tailscaleReady.status)" -and
    "$($tailscaleNext.primaryPhoneUrl)" -eq "$($tailscaleReady.primaryPhoneUrl)" -and
    "$($tailscaleDashboard.primaryPhoneUrl)" -eq "$($tailscaleReady.primaryPhoneUrl)" -and
    "$($tailscaleHandoff.primaryPhoneUrl)" -eq "$($tailscaleReady.primaryPhoneUrl)"
  ) $(if ($sameReady -and $tailscaleReady) { "sameReady=$($sameReady.status)/$($sameReady.primaryPhoneUrl), next=$($sameNext.status)/$($sameNext.primaryPhoneUrl), dashboard=$($sameDashboard.status)/$($sameDashboard.primaryPhoneUrl), handoff=$($sameHandoff.status)/$($sameHandoff.primaryPhoneUrl), tailscaleReady=$($tailscaleReady.status)/$($tailscaleReady.primaryPhoneUrl)" } else { "missing readiness JSON" })

  $sameRunCardHtmlPath = if ($sameReady) { "$($sameReady.runCardHtml)" } else { "" }
  $sameRunCardHtmlText = Read-TextFile $sameRunCardHtmlPath
  $tailscaleRunCardRequired = $tailscaleReady -and @("ready-for-phone", "complete") -contains "$($tailscaleReady.status)"
  $tailscaleRunCardHtmlPath = if ($tailscaleReady) { "$($tailscaleReady.runCardHtml)" } else { "" }
  $tailscaleRunCardHtmlText = Read-TextFile $tailscaleRunCardHtmlPath
  Add-ContentRequirement $requirements "CONTENT-064" "Latest ready physical run cards point at existing HTML files that contain the current gate-aware phone URL before the operator starts manual proof." "phone-acceptance-ready-*-latest.json + phone-acceptance-session-*.html" (
    $sameReady -and
    (Test-NonEmptyFile $sameRunCardHtmlPath) -and
    $sameRunCardHtmlText -like "*Physical Phone Acceptance Session*" -and
    $sameRunCardHtmlText -like "*gate=same-wifi*" -and
    $sameRunCardHtmlText -like "*v=$currentPhoneAppVersion*" -and
    (
      -not $tailscaleRunCardRequired -or
      (
        (Test-NonEmptyFile $tailscaleRunCardHtmlPath) -and
        $tailscaleRunCardHtmlText -like "*Physical Phone Acceptance Session*" -and
        $tailscaleRunCardHtmlText -like "*gate=tailscale*" -and
        $tailscaleRunCardHtmlText -like "*v=$currentPhoneAppVersion*"
      )
    )
  ) "sameRunCard=$sameRunCardHtmlPath exists=$(Test-NonEmptyFile $sameRunCardHtmlPath), tailscaleRequired=$tailscaleRunCardRequired, tailscaleRunCard=$tailscaleRunCardHtmlPath exists=$(Test-NonEmptyFile $tailscaleRunCardHtmlPath), phoneAppVersion=$currentPhoneAppVersion"

  Add-ContentRequirement $requirements "CONTENT-025" "Latest watcher snapshots preserve readiness status, primary phone URL, and current verifier blockers for both physical gates." "phone-acceptance-watch-*-latest.json" (
    $sameReady -and
    $tailscaleReady -and
    $sameWatch -and
    $tailscaleWatch -and
    "$($sameWatch.gate)" -eq "same-wifi" -and
    "$($sameWatch.readinessStatus)" -eq "$($sameReady.status)" -and
    "$($sameWatch.primaryPhoneUrl)" -eq "$($sameReady.primaryPhoneUrl)" -and
    @($sameWatch.failedChecks).Count -gt 0 -and
    "$($tailscaleWatch.gate)" -eq "tailscale" -and
    "$($tailscaleWatch.readinessStatus)" -eq "$($tailscaleReady.status)" -and
    "$($tailscaleWatch.primaryPhoneUrl)" -eq "$($tailscaleReady.primaryPhoneUrl)" -and
    @($tailscaleWatch.failedChecks).Count -gt 0
  ) $(if ($sameWatch -and $tailscaleWatch) { "sameWatch=$($sameWatch.readinessStatus)/$($sameWatch.primaryPhoneUrl)/failed=$(@($sameWatch.failedChecks).Count), tailscaleWatch=$($tailscaleWatch.readinessStatus)/$($tailscaleWatch.primaryPhoneUrl)/failed=$(@($tailscaleWatch.failedChecks).Count)" } else { "missing watcher JSON" })

  Add-ContentRequirement $requirements "CONTENT-026" "Phone proof mode requires a gate-aware checklist before Mark Proof, stores checklist completion in the proof payload, and the verifier requires that checklist evidence." "public\app.js + scripts\verify-phone-acceptance.ps1 + test\phone-connection-help.test.js" (
    $phoneAppText -like "*ACCEPTANCE_CHECKLISTS*" -and
    $phoneAppText -like "*acceptanceChecklistState*" -and
    $phoneAppText -like "*Finish checklist first*" -and
    $phoneAppText -like "*checklist*" -and
    $phoneVerifierText -like "*phone proof checklist complete*" -and
    $phoneVerifierText -like "*phone proof checklist count matches gate*" -and
    $phoneVerifierText -like "*phone proof checklist all items checked*" -and
    $phoneTestText -like "*blocks proof marker until the checklist is complete*" -and
    $phoneTestText -like "*sentChecklistComplete*"
  ) "phoneAppChecklist=$($phoneAppText -like '*ACCEPTANCE_CHECKLISTS*'), verifierChecklist=$($phoneVerifierText -like '*phone proof checklist complete*'), proofBlockTest=$($phoneTestText -like '*blocks proof marker until the checklist is complete*')"

  Add-ContentRequirement $requirements "CONTENT-027" "Host console Latest Phone Proof renders checklist completion from the physical proof payload." "public\host.js + test\host-console.test.js" (
    $hostConsoleText -like "*formatProofChecklist*" -and
    $hostConsoleText -like "*Checked Items*" -and
    (($hostConsoleTestText -like "*13 / 13 complete*") -or ($hostConsoleTestText -like "*13 \/ 13 complete*")) -and
    $hostConsoleTestText -like "*8 / 9 incomplete*"
  ) "hostChecklistFormatter=$($hostConsoleText -like '*formatProofChecklist*'), hostChecklistTest=$(($hostConsoleTestText -like '*13 / 13 complete*') -or ($hostConsoleTestText -like '*13 \/ 13 complete*'))"

  Add-ContentRequirement $requirements "CONTENT-058" "Physical proof verification and host-console proof selection distinguish real physical phone proof from smoke/debug proof markers." "scripts\verify-phone-acceptance.ps1 + public\host.js + test\host-console.test.js" (
    $phoneVerifierText -like "*step*physical-phone-proof*" -and
    $phoneVerifierText -like "*Find-PhoneMark -HostLogs*SelectedGate*" -and
    $hostConsoleText -like "*isPhysicalProofEntry*" -and
    $hostConsoleText -like "*isCompletePhysicalProofEntry*" -and
    $hostConsoleText -like "*not physical*" -and
    $hostConsoleTestText -like "*preferredPhysicalGate*" -and
    $hostConsoleTestText -like "*live-smoke*"
  ) "verifierRequiresPhysicalStep=$($phoneVerifierText -like '*step*physical-phone-proof*'), hostPrefersPhysical=$($hostConsoleText -like '*isCompletePhysicalProofEntry*'), testCoversSmokeFallback=$($hostConsoleTestText -like '*preferredPhysicalGate*')"

  Add-ContentRequirement $requirements "CONTENT-059" "Guided physical phone checklist scoring requires an explicit y/n/s answer so accidental blank or mistyped input cannot silently skip a required proof step." "scripts\manual-phone-acceptance.ps1 + docs\ACCEPTANCE_TESTS.md" (
    $manualAcceptanceText -like "*function Read-ChecklistAnswer*" -and
    $manualAcceptanceText -like "*Please enter y for PASS, n for FAIL, or s for SKIP*" -and
    $manualAcceptanceText -notlike "*if (-not @(`"y`", `"n`", `"s`").Contains(`$answer)) { `$answer = `"s`" }*" -and
    $manualAcceptanceText -like "*requiresExplicitStepAnswer = `$true*" -and
    $acceptanceTestsText -like "*Blank or mistyped input is rejected and re-prompted*"
  ) "explicitAnswerFunction=$($manualAcceptanceText -like '*function Read-ChecklistAnswer*'), noSilentSkip=$($manualAcceptanceText -notlike '*if (-not @(`"y`", `"n`", `"s`").Contains(`$answer)) { `$answer = `"s`" }*'), docs=$($acceptanceTestsText -like '*Blank or mistyped input is rejected and re-prompted*')"

  Add-ContentRequirement $requirements "CONTENT-060" "Guided physical phone summaries report OK only after manual steps, post evidence, and saved selected-gate verification all pass." "scripts\manual-phone-acceptance.ps1 + docs\ACCEPTANCE_TESTS.md" (
    $manualAcceptanceText -like "*manualStepsOk*" -and
    $manualAcceptanceText -like "*postEvidenceOk*" -and
    $manualAcceptanceText -like "*summaryOkRequiresVerifier*" -and
    $manualAcceptanceText.Contains('$summary["ok"] = $manualStepsOk -and $postEvidenceOk -and [bool]$verification.ok') -and
    $manualAcceptanceText.Contains('$summary["ok"] = $false') -and
    $acceptanceTestsText -like "*Guided phone acceptance summaries keep *ok=false*"
  ) "manualStepsOk=$($manualAcceptanceText -like '*manualStepsOk*'), postEvidenceOk=$($manualAcceptanceText -like '*postEvidenceOk*'), verifierControlsOk=$($manualAcceptanceText.Contains('$summary["ok"] = $manualStepsOk -and $postEvidenceOk -and [bool]$verification.ok')), docs=$($acceptanceTestsText -like '*Guided phone acceptance summaries keep *ok=false*')"

  Add-ContentRequirement $requirements "CONTENT-028" "Tailscale acceptance doctor and manual evidence report discover the CLI from common Windows install paths, not PATH only." "scripts\acceptance-doctor.ps1 + scripts\acceptance-report.ps1" (
    $acceptanceDoctorText -like "*C:\Program Files\Tailscale\tailscale.exe*" -and
    $acceptanceDoctorText -like "*common Windows install paths*" -and
    $acceptanceDoctorText -like "*commonInstallPathChecked*" -and
    $acceptanceReportText -like "*C:\Program Files\Tailscale\tailscale.exe*" -and
    $acceptanceReportText -like "*common Windows install paths*" -and
    $acceptanceReportText -like "*commonInstallPathChecked*"
  ) "doctorCommonPath=$($acceptanceDoctorText -like '*C:\Program Files\Tailscale\tailscale.exe*'), reportCommonPath=$($acceptanceReportText -like '*C:\Program Files\Tailscale\tailscale.exe*')"

  $tailscaleReadyMentionsAuth = $tailscaleReady -and (
    (Test-AnyStringContains $tailscaleReady.readyActions "login.tailscale.com") -or
    (Test-AnyStringContains @($tailscaleReady.prepareFailures | ForEach-Object { "$($_.nextAction)" }) "login.tailscale.com") -or
    (Test-AnyStringContains $tailscaleReady.phoneUrls "gate=tailscale")
  )
  $tailscaleBootstrapHasAuthOrIp = $tailscaleBootstrap -and $tailscaleBootstrap.tailscale -and (
    -not [string]::IsNullOrWhiteSpace("$($tailscaleBootstrap.tailscale.statusSnapshot.authUrl)") -or
    $tailscaleBootstrap.tailscale.statusSnapshot.hasTailnetIp -eq $true -or
    @($tailscaleBootstrap.tailscale.ipv4).Count -gt 0 -or
    @($tailscaleBootstrap.tailscale.ipv6).Count -gt 0
  )
  $tailscaleSetupHasAuthOrIp = $tailscaleSetupCheck -and $tailscaleSetupCheck.tailscale -and (
    -not [string]::IsNullOrWhiteSpace("$($tailscaleSetupCheck.tailscale.statusSnapshot.authUrl)") -or
    $tailscaleSetupCheck.tailscale.statusSnapshot.hasTailnetIp -eq $true -or
    @($tailscaleSetupCheck.tailscale.ipv4).Count -gt 0 -or
    @($tailscaleSetupCheck.tailscale.ipv6).Count -gt 0
  )
  Add-ContentRequirement $requirements "CONTENT-042" "Tailscale setup evidence preserves the concrete login handoff when the laptop is installed but not signed in, or the tailnet IP evidence once signed in." "tailscale-bootstrap/setup-check latest JSON + acceptance doctor/ready artifacts" (
    $tailscaleBootstrapText -like "*authUrl*" -and
    $tailscaleSetupCheckText -like "*authUrl*" -and
    $acceptanceDoctorText -like "*authUrl*" -and
    $tailscaleReadyMentionsAuth -and
    $tailscaleBootstrapHasAuthOrIp -and
    $tailscaleSetupHasAuthOrIp
  ) $(if ($tailscaleBootstrap -and $tailscaleSetupCheck -and $tailscaleReady) { "bootstrapBackend=$($tailscaleBootstrap.tailscale.statusSnapshot.backendState), bootstrapAuth=$($tailscaleBootstrap.tailscale.statusSnapshot.authUrl), setupBackend=$($tailscaleSetupCheck.tailscale.statusSnapshot.backendState), setupAuth=$($tailscaleSetupCheck.tailscale.statusSnapshot.authUrl), readyMentionsAuth=$tailscaleReadyMentionsAuth" } else { "missing Tailscale setup artifacts" })

  Add-ContentRequirement $requirements "CONTENT-029" "Dependency audit evidence is saved for packaging and reports no high or critical advisories." "dependency-audit-latest.json" (
    $dependencyAudit -and
    $dependencyAudit.ok -eq $true -and
    [int]$dependencyAudit.highCritical -eq 0 -and
    -not [string]::IsNullOrWhiteSpace("$($dependencyAudit.status)") -and
    "$($dependencyAudit.policy)" -like "*Fail on high/critical*"
  ) $(if ($dependencyAudit) { "status=$($dependencyAudit.status), total=$($dependencyAudit.total), moderate=$($dependencyAudit.moderate), highCritical=$($dependencyAudit.highCritical)" } else { "missing or invalid JSON" })

  $packageSmokeGeneratedAt = [datetime]::MinValue
  $packageSmokeGeneratedAtOk = $packageSmoke -and [datetime]::TryParse("$($packageSmoke.generatedAt)", [ref]$packageSmokeGeneratedAt)
  $packageSourcePaths = @(
    (Join-Path $Root "public"),
    (Join-Path $Root "src"),
    (Join-Path $Root "packaging\local-wifi"),
    (Join-Path $Root "package.json"),
    (Join-Path $Root "package-lock.json")
  )
  $latestPackageSource = $null
  foreach ($packageSourcePath in $packageSourcePaths) {
    if (Test-Path -LiteralPath $packageSourcePath -PathType Container) {
      $items = @(Get-ChildItem -LiteralPath $packageSourcePath -Recurse -File -ErrorAction SilentlyContinue)
    } elseif (Test-Path -LiteralPath $packageSourcePath -PathType Leaf) {
      $items = @(Get-Item -LiteralPath $packageSourcePath -ErrorAction SilentlyContinue)
    } else {
      $items = @()
    }
    foreach ($item in $items) {
      if (-not $latestPackageSource -or $item.LastWriteTime -gt $latestPackageSource.LastWriteTime) {
        $latestPackageSource = $item
      }
    }
  }
  $packageSmokeFresh = $packageSmokeGeneratedAtOk -and $latestPackageSource -and ($packageSmokeGeneratedAt -ge $latestPackageSource.LastWriteTime)
  Add-ContentRequirement $requirements "CONTENT-053" "Latest package smoke proves the extracted local-Wi-Fi zip loads the phone shell, uses the current service-worker app version, exposes versioned host-console phone URLs, ships clear first-run instructions, fails clearly on port conflicts, ignores stale unrelated PID files safely, and was generated after the newest package-affecting file." "package-smoke-latest.json + packaging\local-wifi\smoke-local-wifi.ps1" (
    $packageSmoke -and
    $packageSmoke.ok -eq $true -and
    $packageSmokeFresh -and
    "$($packageSmoke.phoneShell)" -eq "loaded" -and
    "$($packageSmoke.phoneAppVersion)" -match "^[0-9]+$" -and
    "$($packageSmoke.serviceWorker)" -eq "remote-controller-shell-v$($packageSmoke.phoneAppVersion)" -and
    "$($packageSmoke.hostConsolePhoneUrls)" -eq "v$($packageSmoke.phoneAppVersion)" -and
    [int]$packageSmoke.hostConsoleCheckedUrlCount -gt 0 -and
    "$($packageSmoke.transport)" -eq "native-websocket-binary-jpeg" -and
    $packageSmoke.inputEnabled -eq $true -and
    $packageSmoke.packageManifestClean -eq $true -and
    $packageSmoke.readmeFirstClean -eq $true -and
    $packageSmoke.portConflictGuard -eq $true -and
    $packageSmoke.stalePidGuard -eq $true -and
    [int]$packageSmoke.packageManifestScriptCount -eq 3 -and
    "$(@($packageSmoke.packageManifestScripts) -join ',')" -eq "start,stop,smoke" -and
    $packageSmoke.listenerStopped -eq $true
  ) $(if ($packageSmoke) { "phoneAppVersion=$($packageSmoke.phoneAppVersion), serviceWorker=$($packageSmoke.serviceWorker), hostConsolePhoneUrls=$($packageSmoke.hostConsolePhoneUrls), generatedAt=$($packageSmoke.generatedAt), latestPackageSource=$($latestPackageSource.FullName), latestPackageSourceWrite=$($latestPackageSource.LastWriteTime.ToString("o")), fresh=$packageSmokeFresh, checked=$($packageSmoke.hostConsoleCheckedUrlCount), manifestScripts=$(@($packageSmoke.packageManifestScripts) -join ','), readmeFirstClean=$($packageSmoke.readmeFirstClean), portConflictGuard=$($packageSmoke.portConflictGuard), stalePidGuard=$($packageSmoke.stalePidGuard), listenerStopped=$($packageSmoke.listenerStopped)" } else { "missing package-smoke-latest.json" })

  $currentPhoneAppVersion = Get-PhoneAppVersion
  Add-ContentRequirement $requirements "CONTENT-057" "Latest live phone visual proof shows a real connected phone canvas with binary screen frames, nonblank pixels, a bottom-edge cursor overlay, and a centered cursor lens." "scripts\live-phone-visual-proof.js + live-phone-visual-proof-latest.json/.png" (
    (Test-PackageScriptContains -Package $package -ScriptName "visual:phone" -Fragments @("node", "scripts/live-phone-visual-proof.js")) -and
    $visualProofScriptText -like "*activePixelRatio*" -and
    $visualProofScriptText -like "*cursorCenteredInLens*" -and
    $visualProofScriptText -like "*bottomEdgeCursorVisible*" -and
    $visualProofScriptText -like "*visual-bottom-edge-proof*" -and
    $visualProof -and
    $visualProof.ok -eq $true -and
    "$($visualProof.phoneAppVersion)" -eq $currentPhoneAppVersion -and
    "$($visualProof.hostMode)" -eq "milestone-2-screen-capture" -and
    $visualProof.visual.connected -eq $true -and
    $visualProof.visual.binaryTransport -eq $true -and
    $visualProof.visual.frameImageReady -eq $true -and
    [double]$visualProof.visual.activePixelRatio -gt 0.01 -and
    [int]$visualProof.visual.goldPixelSamples -gt 0 -and
    $visualProof.visual.cursorCenteredInLens -eq $true -and
    $visualProof.visual.bottomEdgeCursorVisible -eq $true -and
    $visualProof.visual.bottomEdgeProof.sourceNearBottom -eq $true -and
    $visualProof.visual.bottomEdgeProof.canvasNearBottom -eq $true -and
    (Test-NonEmptyFile $visualProofScreenshotPath)
  ) $(if ($visualProof) { "phoneAppVersion=$($visualProof.phoneAppVersion), activePixelRatio=$($visualProof.visual.activePixelRatio), goldPixels=$($visualProof.visual.goldPixelSamples), centered=$($visualProof.visual.cursorCenteredInLens), bottomEdge=$($visualProof.visual.bottomEdgeCursorVisible), screenshot=$visualProofScreenshotPath" } else { "missing live-phone-visual-proof-latest.json" })

  Add-ContentRequirement $requirements "CONTENT-063" "Phone release gates preserve blank-stream recovery, the compact centered gold cursor lens, and the finalized touchpad gesture checklist." "public\app.js + test\phone-connection-help.test.js + scripts\manual-phone-acceptance.ps1 + scripts\acceptance-report.ps1" (
    $phoneAppText -like "*const FRAME_DECODE_STALL_MS = 1200*" -and
    $phoneAppText -like "*const CURSOR_LENS_MIN_W = 220*" -and
    $phoneAppText -like "*const CURSOR_LENS_VIEWPORT_W = 0.72*" -and
    $phoneAppText -like "*cursorCentered: true*" -and
    $phoneAppText -like "*single-tap left click*" -and
    $phoneAppText -like "*double-tap right click*" -and
    $phoneAppText -like "*double-tap drag a tab/window*" -and
    $phoneTestText -like "*phone recovers when a frame decode gets stuck before loading*" -and
    $phoneTestText -like "*phone watchdog keeps the socket open when the initial screen frame never arrives*" -and
    $phoneTestText -like "*phone resume path wakes a blank visible stream without waiting for user input*" -and
    $phoneTestText -like "*phone cursor lens keeps the real mouse centered inside the zoom box*" -and
    $phoneTestText -like "*phone cursor lens keeps the gold cursor centered at bottom-right frame edge*" -and
    $phoneTestText -like "*single-tap left click*" -and
    $phoneTestText -like "*double-tap right click*" -and
    $phoneTestText -like "*double-tap drag*" -and
    $manualAcceptanceText -like "*single-tap left click*" -and
    $manualAcceptanceText -like "*double-tap right click*" -and
    $manualAcceptanceText -like "*double-tap drag*" -and
    $acceptanceReportText -like "*single-tap left click*" -and
    $acceptanceReportText -like "*double-tap right click*" -and
    $acceptanceReportText -like "*double-tap drag*"
  ) "decodeStallMs=1200, lensMin=220, centeredLensTest=$($phoneTestText -like '*phone cursor lens keeps the real mouse centered inside the zoom box*'), blankRecoveryTests=$($phoneTestText -like '*phone resume path wakes a blank visible stream without waiting for user input*'), gestureChecklist=$($phoneAppText -like '*single-tap left click*')"

  $versionedOperatorArtifactNames = @(
    "phone-acceptance-ready-same-wifi-latest.json",
    "phone-acceptance-ready-tailscale-latest.json",
    "phone-acceptance-next-latest.json",
    "physical-proof-runbook-latest.json",
    "physical-proof-runbook-latest.md",
    "physical-proof-launch-same-wifi-latest.json",
    "physical-proof-launch-same-wifi-latest.md",
    "physical-proof-launch-tailscale-latest.json",
    "physical-proof-launch-tailscale-latest.md",
    "phone-acceptance-dashboard-latest.json",
    "phone-acceptance-handoff-latest.json",
    "phone-acceptance-handoff-latest.md",
    "phone-acceptance-refresh-latest.json"
  )
  $operatorVersionStaleHits = [System.Collections.Generic.List[string]]::new()
  $operatorVersionCurrentHits = 0
  foreach ($artifactName in $versionedOperatorArtifactNames) {
    $artifactPath = Join-Path $artifactRoot $artifactName
    $artifactText = Read-TextFile $artifactPath
    if ([string]::IsNullOrWhiteSpace($artifactText)) {
      $operatorVersionStaleHits.Add("${artifactName}: missing or empty") | Out-Null
      continue
    }
    foreach ($match in [regex]::Matches($artifactText, '(?i)(?:\?|&)v=(?<version>[0-9]+)\b')) {
      $version = "$($match.Groups["version"].Value)"
      if ($version -eq $currentPhoneAppVersion) {
        $operatorVersionCurrentHits += 1
      } else {
        $operatorVersionStaleHits.Add("$artifactName has v=$version") | Out-Null
      }
    }
  }
  Add-ContentRequirement $requirements "CONTENT-056" "Latest operator-facing physical-test links use the current phone app version from the service worker." "public\sw.js + output\acceptance\*-latest.*" (
    -not [string]::IsNullOrWhiteSpace($currentPhoneAppVersion) -and
    $operatorVersionCurrentHits -gt 0 -and
    $operatorVersionStaleHits.Count -eq 0
  ) $(if ($operatorVersionStaleHits.Count -eq 0) { "phoneAppVersion=$currentPhoneAppVersion, versionedLinks=$operatorVersionCurrentHits" } else { "phoneAppVersion=$currentPhoneAppVersion, stale=$($operatorVersionStaleHits -join '; ')" })

  Add-ContentRequirement $requirements "CONTENT-031" "Physical proof verifier rejects stale manual summaries when a newer gate readiness run exists." "scripts\verify-phone-acceptance.ps1" (
    $phoneVerifierText -like "*Get-LatestReadyStatusPath*" -and
    $phoneVerifierText -like "*Test-SummaryFreshness*" -and
    $phoneVerifierText -like "*manual summary is current for latest ready run*"
  ) "staleSummaryCheck=$($phoneVerifierText -like '*manual summary is current for latest ready run*')"

  Add-ContentRequirement $requirements "CONTENT-036" "Physical readiness writes the current readiness artifact before watcher verification so blocker details are fresh for the selected run." "scripts\acceptance-ready.ps1" (
    $acceptanceReadyText -like "*preliminaryStatus*" -and
    $acceptanceReadyText -like '*Save-ReadyStatus -Status $preliminaryStatus*' -and
    $acceptanceReadyText -like '*Invoke-JsonScript -Path $WatchScript*'
  ) "preliminaryReadyBeforeWatch=$($acceptanceReadyText -like '*Save-ReadyStatus -Status $preliminaryStatus*')"

  Add-ContentRequirement $requirements "CONTENT-037" "Operator next-action, dashboard, and handoff surfaces use the no-refresh physical finalizer after both phone gates pass." "scripts\acceptance-next.ps1 + scripts\acceptance-dashboard.ps1 + scripts\acceptance-handoff.ps1" (
    $acceptanceNextText -like "*npm run acceptance:finalize*" -and
    $acceptanceDashboardText -like "*npm run acceptance:finalize*" -and
    $acceptanceHandoffText -like "*npm run acceptance:finalize*" -and
    $acceptanceNextText -notmatch "npm run completion:audit\s*~~~" -and
    $acceptanceHandoffText -notmatch "npm run completion:audit\s*~~~"
  ) "next=$($acceptanceNextText -like '*npm run acceptance:finalize*'), dashboard=$($acceptanceDashboardText -like '*npm run acceptance:finalize*'), handoff=$($acceptanceHandoffText -like '*npm run acceptance:finalize*')"

  Add-ContentRequirement $requirements "CONTENT-038" "Latest next-action artifact exposes an operator Run Now sequence with the first command and no-refresh finalization warning." "phone-acceptance-next-latest.json + scripts\acceptance-next.ps1" (
    $next -and
    $next.operatorRunNow -and
    -not [string]::IsNullOrWhiteSpace("$($next.operatorRunNow.firstCommand)") -and
    "$($next.operatorRunNow.finalCommand)" -eq "npm run acceptance:finalize" -and
    $next.operatorRunNow.doNotRefreshAfterProof -eq $true -and
    @($next.operatorRunNow.steps | Where-Object { "$_" -like "*do not run npm run acceptance:refresh*" }).Count -gt 0 -and
    $acceptanceNextText -like "*New-OperatorRunNow*" -and
    $acceptanceNextText -like "*First command*" -and
    $acceptanceNextText -like "*do not run npm run acceptance:refresh*"
  ) $(if ($next -and $next.operatorRunNow) { "first=$($next.operatorRunNow.firstCommand), final=$($next.operatorRunNow.finalCommand), noRefresh=$($next.operatorRunNow.doNotRefreshAfterProof)" } else { "missing operatorRunNow" })

  Add-ContentRequirement $requirements "CONTENT-061" "Operator-facing guided physical phone commands use RequireReady so stale readiness or selected-gate URL failures stop before manual checklist scoring." "scripts\prepare-phone-acceptance.ps1 + scripts\acceptance-next.ps1 + scripts\physical-proof-launch.ps1 + docs\ACCEPTANCE_TESTS.md" (
    $preparePhoneText -like "*-SkipStart -RequireReady*" -and
    $acceptanceNextText -like "*-SkipStart -RequireReady*" -and
    $physicalLaunchText -like "*-SkipStart -RequireReady*" -and
    $next -and
    $next.operatorRunNow -and
    (
      "$($next.operatorRunNow.firstCommand)" -notlike "*acceptance:phone*" -or
      "$($next.operatorRunNow.firstCommand)" -like "*-RequireReady*"
    ) -and
    (
      @($next.operatorRunNow.steps | Where-Object { "$_" -like "*acceptance:phone*" -and "$_" -notlike "*-RequireReady*" }).Count -eq 0
    ) -and
    $acceptanceTestsText -like "*RequireReady*guided physical phone commands*"
  ) $(if ($next -and $next.operatorRunNow) { "first=$($next.operatorRunNow.firstCommand), phoneStepsWithoutRequireReady=$(@($next.operatorRunNow.steps | Where-Object { "$_" -like "*acceptance:phone*" -and "$_" -notlike "*-RequireReady*" }).Count)" } else { "missing operatorRunNow" })

  $tailscaleNext = Get-GateRecord $next "tailscale"
  $tailscaleSetupNeeded = $tailscaleNext -and "$($tailscaleNext.status)" -eq "setup-needed"
  Add-ContentRequirement $requirements "CONTENT-049" "Next-action and runbook surfaces include the saved Tailscale setup-check report in the setup-needed path." "phone-acceptance-next-latest.json/.md + physical-proof-runbook-latest.md + scripts\acceptance-next.ps1" (
    $tailscaleNext -and
    (
      -not $tailscaleSetupNeeded -or
      (
        (Test-AnyStringContains $tailscaleNext.actions "tailscale-setup-check-latest.md") -and
        (Test-AnyStringContains $next.operatorRunNow.steps "npm run tailscale:check:save") -and
        $acceptanceNextText -like "*tailscale-setup-check-latest.md*" -and
        $acceptanceNextText -like "*npm run tailscale:check:save*" -and
        $runbookMarkdown -like "*tailscale-setup-check-latest.md*" -and
        $runbookMarkdown -like "*npm run tailscale:check:save*"
      )
    )
  ) $(if ($tailscaleNext) { "tailscaleStatus=$($tailscaleNext.status), setupNeeded=$tailscaleSetupNeeded, actionHasSetupCheck=$(Test-AnyStringContains $tailscaleNext.actions 'tailscale-setup-check-latest.md')" } else { "missing tailscale next-action gate" })

  $sameRunbook = Get-GateRecord $runbook "same-wifi"
  $tailscaleRunbook = Get-GateRecord $runbook "tailscale"
  $sameRunbookQrCount = if ($sameRunbook -and $sameRunbook.qrCodes) { @($sameRunbook.qrCodes).Count } else { 0 }
  $sameRunbookExistingQrCount = if ($sameRunbook -and $sameRunbook.qrCodes) { @($sameRunbook.qrCodes | Where-Object { $_.exists -eq $true -and -not [string]::IsNullOrWhiteSpace("$($_.path)") }).Count } else { 0 }
  $sameRunbookHasPin = $sameRunbook -and
    $sameRunbook.hostConsole -match '^https?://' -and
    $sameRunbook.currentPin -and
    $sameRunbook.currentPin.available -eq $true -and
    "$($sameRunbook.currentPin.pin)" -match '^[0-9]{6}$' -and
    [int]($sameRunbook.currentPin.secondsRemaining) -gt 0 -and
    -not [string]::IsNullOrWhiteSpace("$($sameRunbook.currentPin.refreshedAt)") -and
    -not [string]::IsNullOrWhiteSpace("$($sameRunbook.currentPin.source)")
  $tailscaleRunbookNeedsPin = $tailscaleRunbook -and "$($tailscaleRunbook.status)" -eq "ready-for-phone"
  $tailscaleRunbookHasPin = -not $tailscaleRunbookNeedsPin -or (
    $tailscaleRunbook.hostConsole -match '^https?://' -and
    $tailscaleRunbook.currentPin -and
    $tailscaleRunbook.currentPin.available -eq $true -and
    "$($tailscaleRunbook.currentPin.pin)" -match '^[0-9]{6}$' -and
    [int]($tailscaleRunbook.currentPin.secondsRemaining) -gt 0 -and
    -not [string]::IsNullOrWhiteSpace("$($tailscaleRunbook.currentPin.refreshedAt)") -and
    -not [string]::IsNullOrWhiteSpace("$($tailscaleRunbook.currentPin.source)")
  )
  Add-ContentRequirement $requirements "CONTENT-039" "Physical proof runbook consolidates the current first command, both gate states, same-Wi-Fi QR files, current live PIN/host console details, audit blockers, and no-refresh finalizer warning." "physical-proof-runbook-latest.json + scripts\physical-proof-runbook.ps1" (
    $runbook -and
    $runbook.operatorRunNow -and
    -not [string]::IsNullOrWhiteSpace("$($runbook.operatorRunNow.firstCommand)") -and
    "$($runbook.operatorRunNow.finalCommand)" -eq "npm run acceptance:finalize" -and
    $runbook.operatorRunNow.doNotRefreshAfterProof -eq $true -and
    $sameRunbook -and
    $tailscaleRunbook -and
    "$($sameRunbook.status)" -eq "$($sameReady.status)" -and
    "$($sameRunbook.primaryPhoneUrl)" -eq "$($sameReady.primaryPhoneUrl)" -and
    "$($sameRunbook.runCardHtml)" -eq "$($sameReady.runCardHtml)" -and
    $sameRunbookHasPin -and
    $sameRunbookQrCount -gt 0 -and
    $sameRunbookExistingQrCount -gt 0 -and
    "$($tailscaleRunbook.status)" -eq "$($tailscaleReady.status)" -and
    "$($tailscaleRunbook.primaryPhoneUrl)" -eq "$($tailscaleReady.primaryPhoneUrl)" -and
    "$($tailscaleRunbook.runCardHtml)" -eq "$($tailscaleReady.runCardHtml)" -and
    $tailscaleRunbookHasPin -and
    @($runbook.failedAuditIds | Where-Object { "$_" -in @("PHYSICAL-001", "PHYSICAL-002", "PHYSICAL-003") }).Count -eq 3 -and
    $physicalRunbookText -like "*New-PhysicalProofRunbook*" -and
    $physicalRunbookText -like "*Get-GatePinSummary*" -and
    $physicalRunbookText -like "*Current PIN*" -and
    $physicalRunbookText -like "*Host console*" -and
    $physicalRunbookText -like "*acceptance:refresh*" -and
    $physicalRunbookText -like "*npm run acceptance:finalize*" -and
    $physicalRunbookText -like "*QR files*" -and
    $runbookMarkdown -match 'Host console:' -and
    $runbookMarkdown -match 'Current PIN:' -and
    $runbookMarkdown -match '- PIN: [0-9]{6}' -and
    $runbookMarkdown -match '- Source:' -and
    $runbookMarkdown -match '- Refreshed:' -and
    $runbookMarkdown -match '- Expires in about:' -and
    $runbookMarkdown -match 'Do not run `npm run acceptance:refresh`' -and
    $runbookMarkdown -match 'Use `npm run acceptance:finalize`' -and
    $runbookMarkdown -match 'QR files' -and
    $runbookMarkdown -notmatch 'Do not run\s+pm run' -and
    $runbookMarkdown -notmatch 'Use\s+pm run'
  ) $(if ($runbook -and $runbook.operatorRunNow) { "first=$($runbook.operatorRunNow.firstCommand), same=$($sameRunbook.status)/$($sameRunbook.primaryPhoneUrl), samePin=$sameRunbookHasPin/$($sameRunbook.currentPin.source), sameQr=$sameRunbookExistingQrCount/$sameRunbookQrCount, tailscale=$($tailscaleRunbook.status)/$($tailscaleRunbook.primaryPhoneUrl), tailscalePin=$tailscaleRunbookHasPin/$($tailscaleRunbook.currentPin.source), failed=$(@($runbook.failedAuditIds).Count)" } else { "missing physical proof runbook" })

  Add-ContentRequirement $requirements "CONTENT-041" "Physical proof launch helper opens/copies current proof artifacts without marking evidence complete." "scripts\physical-proof-launch.ps1 + package.json" (
    $physicalLaunchText -like "*Set-Clipboard*" -and
    $physicalLaunchText -like "*Start-Process*" -and
    $physicalLaunchText -like "*Get-SetupUrl*" -and
    $physicalLaunchText -like "*setup-url*" -and
    $physicalLaunchText -like "*clipboardKind*" -and
    $physicalLaunchText -like "*doesNotReplaceVerifier*" -and
    $physicalLaunchText -like "*doesNotMarkPhysicalGate*" -and
    $physicalLaunchText -like "*physical-proof-runbook-latest.json*" -and
    $physicalLaunchText -like "*runCardHtml*" -and
    $physicalLaunchText -like "*hostConsole*" -and
    $physicalLaunchText -like "*runbookMarkdownPath*" -and
    $physicalLaunchText -like "*^https?://*" -and
    $physicalLaunchText -like "*NoOpen*" -and
    $physicalLaunchText -like "*NoClipboard*" -and
    (Test-PackageScriptContains -Package $package -ScriptName "acceptance:launch" -Fragments @("scripts/physical-proof-launch.ps1")) -and
    (Test-PackageScriptContains -Package $package -ScriptName "acceptance:launch:selftest" -Fragments @("scripts/physical-proof-launch.ps1", "-SelfTest"))
  ) "launchScript=$($physicalLaunchText -like '*physical-proof-runbook-latest.json*'), setupUrlFallback=$($physicalLaunchText -like '*setup-url*'), packageLaunch=$(Test-PackageScript -Package $package -ScriptName 'acceptance:launch')"

  Add-ContentRequirement $requirements "CONTENT-054" "Latest physical proof launch cards expose run actions, current blockers, warnings, and per-blocker next actions for both gates." "physical-proof-launch-*-latest.md/json + scripts\physical-proof-launch.ps1" (
    $sameLaunch -and
    $tailscaleLaunch -and
    -not [string]::IsNullOrWhiteSpace("$($sameLaunch.hostConsole)") -and
    -not [string]::IsNullOrWhiteSpace("$($tailscaleLaunch.hostConsole)") -and
    $sameLaunch.currentPin -and
    $tailscaleLaunch.currentPin -and
    $sameLaunch.currentPin.available -eq $true -and
    "$($sameLaunch.currentPin.pin)" -match '^[0-9]{6}$' -and
    [int]($sameLaunch.currentPin.secondsRemaining) -gt 0 -and
    -not [string]::IsNullOrWhiteSpace("$($sameLaunch.currentPin.source)") -and
    @($sameLaunch.actions).Count -gt 0 -and
    @($tailscaleLaunch.actions).Count -gt 0 -and
    @($sameLaunch.failedChecks | Where-Object { -not [string]::IsNullOrWhiteSpace("$($_.nextAction)") }).Count -gt 0 -and
    @($tailscaleLaunch.failedChecks | Where-Object { -not [string]::IsNullOrWhiteSpace("$($_.nextAction)") }).Count -gt 0 -and
    -not [string]::IsNullOrWhiteSpace($sameLaunchMarkdown) -and
    -not [string]::IsNullOrWhiteSpace($tailscaleLaunchMarkdown) -and
    $sameLaunchMarkdown -match 'Host console:\s+https?://' -and
    $sameLaunchMarkdown -match 'PIN:\s+[0-9]{6}' -and
    $sameLaunchMarkdown -match 'Source:\s+\S+' -and
    $sameLaunchMarkdown -match 'Expires in about:\s+[0-9]+ seconds' -and
    $tailscaleLaunchMarkdown -match 'Host console:\s+https?://' -and
    $sameLaunchMarkdown -like "*## Run Actions*" -and
    $sameLaunchMarkdown -like "*## Current Blockers*" -and
    $sameLaunchMarkdown -like "*## Warnings*" -and
    $sameLaunchMarkdown -like "*Next: Open the same-wifi proof URL*" -and
    $tailscaleLaunchMarkdown -like "*## Run Actions*" -and
    $tailscaleLaunchMarkdown -like "*## Current Blockers*" -and
    $tailscaleLaunchMarkdown -like "*## Warnings*" -and
    $tailscaleLaunchMarkdown -like "*Next: Open the tailscale proof URL*" -and
    $physicalLaunchText -like "*Get-LocalBaseUrlFromConsoleUrl*" -and
    $physicalLaunchText -like "*Source:*" -and
    $physicalLaunchText -like "*hostConsole*" -and
    $physicalLaunchText -like "*## Current Blockers*" -and
    $physicalLaunchText -like "*nextAction*"
  ) $(if ($sameLaunch -and $tailscaleLaunch) { "sameActions=$(@($sameLaunch.actions).Count), sameFailedWithNext=$(@($sameLaunch.failedChecks | Where-Object { -not [string]::IsNullOrWhiteSpace("$($_.nextAction)") }).Count), samePin=$($sameLaunch.currentPin.available)/$($sameLaunch.currentPin.source), tailscaleActions=$(@($tailscaleLaunch.actions).Count), tailscaleFailedWithNext=$(@($tailscaleLaunch.failedChecks | Where-Object { -not [string]::IsNullOrWhiteSpace("$($_.nextAction)") }).Count), tailscalePinExists=$([bool]$tailscaleLaunch.currentPin), sameMarkdownBytes=$($sameLaunchMarkdown.Length), tailscaleMarkdownBytes=$($tailscaleLaunchMarkdown.Length)" } else { "missing launch JSON" })

  Add-ContentRequirement $requirements "CONTENT-043" "Firewall handoff writes an explicit elevated command and artifacts without mutating firewall state or marking physical proof complete." "scripts\firewall-handoff.ps1 + package.json" (
    $firewallHandoffText -like "*mutatesFirewall = `$false*" -and
    $firewallHandoffText -like "*elevatedScriptWouldMutateFirewall*" -and
    $firewallHandoffText -like "*doesNotInstallFirewall*" -and
    $firewallHandoffText -like "*doesNotMarkPhysicalGate*" -and
    $firewallHandoffText -like "*firewall-rule.ps1*" -and
    $firewallHandoffText -like "*Set-Clipboard*" -and
    $firewallHandoffText -like "*explorer.exe*" -and
    (Test-PackageScriptContains -Package $package -ScriptName "firewall:handoff" -Fragments @("scripts/firewall-handoff.ps1")) -and
    (Test-PackageScriptContains -Package $package -ScriptName "firewall:handoff:selftest" -Fragments @("scripts/firewall-handoff.ps1", "-SelfTest"))
  ) "firewallHandoffScript=$($firewallHandoffText -like '*firewall-rule.ps1*'), packageHandoff=$(Test-PackageScript -Package $package -ScriptName 'firewall:handoff')"

  Add-ContentRequirement $requirements "CONTENT-052" "Daily-use shortcut installer creates a normal Windows shortcut to the tray host without changing firewall, autostart, or physical proof state." "scripts\install-shortcut.ps1 + package.json" (
    $installShortcutText -like "*CreateShortcut*" -and
    $installShortcutText -like "*tray-host.ps1*" -and
    $installShortcutText -like "*WorkingDirectory*" -and
    $installShortcutText -like "*Desktop*" -and
    $installShortcutText -like "*StartMenu*" -and
    $installShortcutText -notmatch "Register-ScheduledTask|New-NetFirewallRule|acceptance.phoneMark" -and
    (Test-PackageScriptContains -Package $package -ScriptName "shortcut:install" -Fragments @("scripts/install-shortcut.ps1")) -and
    (Test-PackageScriptContains -Package $package -ScriptName "shortcut:selftest" -Fragments @("scripts/install-shortcut.ps1", "-SelfTest"))
  ) "shortcutScript=$($installShortcutText -like '*CreateShortcut*'), packageShortcut=$(Test-PackageScript -Package $package -ScriptName 'shortcut:install')"

  Add-ContentRequirement $requirements "CONTENT-052" "Daily-use packaging docs expose the shortcut install path as the non-elevated no-terminal launch option." "README.md + docs\PACKAGING_NOTES.md + docs\ACCEPTANCE_TESTS.md" (
    $readmeText -like "*shortcut:install*" -and
    $packagingNotesText -like "*shortcut:install*" -and
    $packagingNotesText -like "*non-elevated*" -and
    $acceptanceTestsText -like "*shortcut:selftest*"
  ) "readmeShortcut=$($readmeText -like '*shortcut:install*'), packagingShortcut=$($packagingNotesText -like '*shortcut:install*'), acceptanceShortcut=$($acceptanceTestsText -like '*shortcut:selftest*')"

  Add-ContentRequirement $requirements "CONTENT-046" "Operator-facing firewall warnings prefer the non-mutating firewall handoff before elevated installation." "scripts\acceptance-doctor.ps1 + scripts\tailscale-setup-check.ps1 + scripts\manual-phone-acceptance.ps1 + docs\ACCEPTANCE_TESTS.md" (
    $acceptanceDoctorText -like "*npm run firewall:handoff first*" -and
    $tailscaleSetupCheckText -like "*npm run firewall:handoff first*" -and
    $manualAcceptanceText -like "*npm run firewall:handoff first*" -and
    $acceptanceTestsText -like "*npm run firewall:handoff*"
  ) "doctorHandoff=$($acceptanceDoctorText -like '*npm run firewall:handoff first*'), setupHandoff=$($tailscaleSetupCheckText -like '*npm run firewall:handoff first*'), manualHandoff=$($manualAcceptanceText -like '*npm run firewall:handoff first*')"

  Add-ContentRequirement $requirements "CONTENT-032" "Physical refresh final commands avoid creating stale proof after successful verifier runs." "scripts\acceptance-refresh.ps1" (
    $acceptanceRefreshText -like "*npm run evidence:bundle*" -and
    $acceptanceRefreshText -like "*npm run completion:audit:save*" -and
    $acceptanceRefreshText -notmatch "npm run acceptance:refresh\s*~~~"
  ) "refreshFinalCommandsUseBundleAndAudit=$($acceptanceRefreshText -like '*npm run evidence:bundle*' -and $acceptanceRefreshText -like '*npm run completion:audit:save*')"

  Add-ContentRequirement $requirements "CONTENT-033" "Physical finalization command verifies both gates, bundles evidence, runs the saved completion audit, and avoids readiness refresh." "scripts\finalize-physical-evidence.ps1 + package.json" (
    $physicalFinalizeText -like "*verify-phone-acceptance.ps1*" -and
    $physicalFinalizeText -like "*evidence-bundle.ps1*" -and
    $physicalFinalizeText -like "*completion-audit.ps1*" -and
    $physicalFinalizeText -like '*"same-wifi"*' -and
    $physicalFinalizeText -like '*"tailscale"*' -and
    $physicalFinalizeText -notmatch "acceptance-ready|acceptance-refresh|prepare-phone-acceptance" -and
    (Test-PackageScriptContains -Package $package -ScriptName "acceptance:finalize" -Fragments @("scripts/finalize-physical-evidence.ps1"))
  ) "finalizeScriptNoRefresh=$($physicalFinalizeText -notmatch 'acceptance-ready|acceptance-refresh|prepare-phone-acceptance')"

  $runQaText = Get-Content -Raw -LiteralPath (Join-Path $Root "scripts\run-qa.ps1")
  Add-ContentRequirement $requirements "CONTENT-034" "Evidence bundle and QA snapshot index physical finalization artifacts when present." "scripts\evidence-bundle.ps1 + scripts\run-qa.ps1" (
    $evidenceBundleText -like "*physical-evidence-finalization-latest.json*" -and
    $evidenceBundleText -like "*physical finalization timestamped Markdown*" -and
    $runQaText -like "*physical-evidence-finalization-latest.json*"
  ) "runQaIndexesFinalization=$($runQaText -like '*physical-evidence-finalization-latest.json*')"

  Add-ContentRequirement $requirements "CONTENT-040" "Evidence bundle and QA snapshot index the physical proof runbook artifacts." "scripts\evidence-bundle.ps1 + scripts\run-qa.ps1" (
    $evidenceBundleText -like "*physical-proof-runbook-latest.json*" -and
    $evidenceBundleText -like "*physical proof runbook timestamped Markdown*" -and
    $runQaText -like "*physical-proof-runbook-latest.json*" -and
    $runQaText -like "*physical proof runbook*"
  ) "bundleIndexesRunbook=$($evidenceBundleText -like '*physical-proof-runbook-latest.json*'), runQaIndexesRunbook=$($runQaText -like '*physical-proof-runbook-latest.json*')"

  Add-ContentRequirement $requirements "CONTENT-044" "Evidence bundle and QA snapshot index the firewall handoff artifacts without treating them as physical proof." "scripts\evidence-bundle.ps1 + scripts\run-qa.ps1" (
    $evidenceBundleText -like "*firewall-handoff-install-latest.json*" -and
    $evidenceBundleText -like "*firewall handoff timestamped script*" -and
    $runQaText -like "*firewall-handoff-install-latest.json*" -and
    $runQaText -like "*firewall handoff*"
  ) "bundleIndexesFirewallHandoff=$($evidenceBundleText -like '*firewall-handoff-install-latest.json*'), runQaIndexesFirewallHandoff=$($runQaText -like '*firewall-handoff-install-latest.json*')"

  Add-ContentRequirement $requirements "CONTENT-062" "QA preserves an already-running live controller host by default and only stops port 4317 when explicitly asked for a fresh QA host." "scripts\run-qa.ps1" (
    $runQaText -match '\[switch\]\$FreshHost' -and
    $runQaText -like "*`$existing -and `$FreshHost*" -and
    $runQaText -like "*Get-FreePort*" -and
    $runQaText -like "*`$env:BASE_URL*" -and
    $runQaText -like "*preservedLiveHost*" -and
    $runQaText -like "*preservedExistingPid*" -and
    $runQaText -like "*reusedExisting*" -and
    $runQaText -like "*startedByQa*"
  ) "freshHostSwitch=$($runQaText -match '\[switch\]\$FreshHost'), stopsOnlyWhenFresh=$($runQaText -like '*`$existing -and `$FreshHost*'), isolatedPort=$($runQaText -like '*Get-FreePort*'), baseUrlSet=$($runQaText -like '*`$env:BASE_URL*')"

  Add-ContentRequirement $requirements "CONTENT-003" "Latest handoff identifies same-Wi-Fi as ready or complete with a gate-aware URL and QR path." "phone-acceptance-handoff-latest.json" (
    $sameHandoff -and "$($sameHandoff.gate)" -eq "same-wifi" -and (Test-AnyStringContains @($sameHandoff.primaryPhoneUrl) "gate=same-wifi") -and -not [string]::IsNullOrWhiteSpace("$($sameHandoff.qrPath)")
  ) $(if ($sameHandoff) { "status=$($sameHandoff.status), url=$($sameHandoff.primaryPhoneUrl), qr=$($sameHandoff.qrPath)" } else { "missing same-wifi handoff gate" })

  Add-ContentRequirement $requirements "CONTENT-004" "Latest handoff identifies the Tailscale gate as either ready for phone or setup-needed with actions/blockers." "phone-acceptance-handoff-latest.json" (
    $tailscaleHandoff -and "$($tailscaleHandoff.gate)" -eq "tailscale" -and (
      "$($tailscaleHandoff.status)" -eq "ready-for-phone" -or
      "$($tailscaleHandoff.status)" -eq "setup-needed" -or
      "$($tailscaleHandoff.status)" -eq "needs-readiness"
    ) -and (@($tailscaleHandoff.actions).Count -gt 0 -or @($tailscaleHandoff.failedChecks).Count -gt 0)
  ) $(if ($tailscaleHandoff) { "status=$($tailscaleHandoff.status), actions=$(@($tailscaleHandoff.actions).Count), failedChecks=$(@($tailscaleHandoff.failedChecks).Count)" } else { "missing tailscale handoff gate" })

  Add-ContentRequirement $requirements "CONTENT-005" "Latest dashboard contains both physical gate cards." "phone-acceptance-dashboard-latest.json" (
    $sameDashboard -and $tailscaleDashboard
  ) "sameWifiDashboard=$([bool]$sameDashboard), tailscaleDashboard=$([bool]$tailscaleDashboard)"

  Add-ContentRequirement $requirements "CONTENT-006" "Latest evidence bundle contains both gate verifier records and latest verifier JSON paths." "remote-controller-evidence-bundle-latest.json" (
    $sameBundle -and $tailscaleBundle -and -not [string]::IsNullOrWhiteSpace("$($sameBundle.latestVerifierJsonPath)") -and -not [string]::IsNullOrWhiteSpace("$($tailscaleBundle.latestVerifierJsonPath)")
  ) $(if ($bundle) { "sameVerifier=$($sameBundle.latestVerifierJsonPath), tailscaleVerifier=$($tailscaleBundle.latestVerifierJsonPath)" } else { "missing or invalid JSON" })

  $bundleNewerThanRefresh = $false
  if ($refresh -and $bundle -and $refresh.generatedAt -and $bundle.generatedAt) {
    try {
      $bundleNewerThanRefresh = [datetime]::Parse("$($bundle.generatedAt)") -gt [datetime]::Parse("$($refresh.generatedAt)")
    } catch {
      $bundleNewerThanRefresh = $false
    }
  }
  Add-ContentRequirement $requirements "CONTENT-007" "Latest refresh reports either complete evidence or expected physical-only blockers." "phone-acceptance-refresh-latest.json" (
    $refresh -and ($refresh.completionReady -eq $true -or $refresh.onlyPhysicalAuditFailures -eq $true -or $bundleNewerThanRefresh)
  ) $(if ($refresh) { "completionReady=$($refresh.completionReady), onlyPhysicalAuditFailures=$($refresh.onlyPhysicalAuditFailures), bundleNewerThanRefresh=$bundleNewerThanRefresh" } else { "missing or invalid JSON" })

  Add-ContentRequirement $requirements "CONTENT-008" "Latest refresh indexes the handoff, dashboard, and evidence bundle artifacts as existing files." "phone-acceptance-refresh-latest.json" (
    $refresh -and
    @($refresh.artifacts | Where-Object { "$($_.name)" -eq "acceptance handoff HTML" -and $_.exists -eq $true }).Count -gt 0 -and
    @($refresh.artifacts | Where-Object { "$($_.name)" -eq "acceptance dashboard HTML" -and $_.exists -eq $true }).Count -gt 0 -and
    @($refresh.artifacts | Where-Object { "$($_.name)" -eq "evidence bundle Markdown" -and $_.exists -eq $true }).Count -gt 0
  ) $(if ($refresh) { "artifactCount=$(@($refresh.artifacts).Count)" } else { "missing or invalid JSON" })

  $bundleHandoffRecords = @()
  if ($bundle -and $bundle.operatorNextActions) {
    $bundleHandoffRecords = @($bundle.operatorNextActions | Where-Object { "$($_.name)" -like "acceptance handoff*" -and $_.exists -eq $true })
  }
  Add-ContentRequirement $requirements "CONTENT-009" "Latest evidence bundle indexes the acceptance handoff JSON, Markdown, and HTML artifacts." "remote-controller-evidence-bundle-latest.json" (
    @($bundleHandoffRecords | Where-Object { "$($_.name)" -eq "acceptance handoff latest JSON" }).Count -gt 0 -and
    @($bundleHandoffRecords | Where-Object { "$($_.name)" -eq "acceptance handoff latest Markdown" }).Count -gt 0 -and
    @($bundleHandoffRecords | Where-Object { "$($_.name)" -eq "acceptance handoff latest HTML" }).Count -gt 0 -and
    @($bundleHandoffRecords | Where-Object { "$($_.name)" -eq "acceptance handoff timestamped JSON" }).Count -gt 0 -and
    @($bundleHandoffRecords | Where-Object { "$($_.name)" -eq "acceptance handoff timestamped Markdown" }).Count -gt 0 -and
    @($bundleHandoffRecords | Where-Object { "$($_.name)" -eq "acceptance handoff timestamped HTML" }).Count -gt 0
  ) $(if ($bundle) { "handoffRecords=$($bundleHandoffRecords.Count)" } else { "missing or invalid JSON" })

  Add-ContentRequirement $requirements "CONTENT-010" "Latest refresh ran the post-audit evidence bundle step so the newest bundle indexes the saved audit." "phone-acceptance-refresh-latest.json" (
    $refresh -and
    @($refresh.steps | Where-Object { "$($_.name)" -eq "Post-audit evidence bundle" -and $_.allowedFailure -eq $true -and -not [string]::IsNullOrWhiteSpace("$($_.primaryPath)") }).Count -gt 0 -and
    @($refresh.artifacts | Where-Object { "$($_.name)" -eq "evidence bundle Markdown" -and $_.exists -eq $true -and "$($_.path)" -like "*remote-controller-evidence-bundle-*" }).Count -gt 0
  ) $(if ($refresh) { "postAuditBundleSteps=$(@($refresh.steps | Where-Object { "$($_.name)" -eq "Post-audit evidence bundle" }).Count)" } else { "missing or invalid JSON" })

  $tailscaleSetupCheckMarkdown = ""
  if ($tailscaleSetupCheck -and -not [string]::IsNullOrWhiteSpace("$($tailscaleSetupCheck.latestReportMarkdownPath)") -and (Test-Path -LiteralPath "$($tailscaleSetupCheck.latestReportMarkdownPath)" -PathType Leaf)) {
    $tailscaleSetupCheckMarkdown = Get-Content -Raw -LiteralPath "$($tailscaleSetupCheck.latestReportMarkdownPath)"
  }
  Add-ContentRequirement $requirements "CONTENT-048" "Acceptance refresh regenerates saved Tailscale setup-check evidence before the Tailscale readiness gate." "scripts\acceptance-refresh.ps1 + tailscale-setup-check-latest.json/.md" (
    $acceptanceRefreshText -like "*tailscale-setup-check.ps1*" -and
    $acceptanceRefreshText -like "*Tailscale setup check*" -and
    $acceptanceRefreshText -like "*-Save*" -and
    $acceptanceRefreshText -like "*Tailscale setup check Markdown*" -and
    $tailscaleSetupCheck -and
    -not [string]::IsNullOrWhiteSpace("$($tailscaleSetupCheck.reportMarkdownPath)") -and
    -not [string]::IsNullOrWhiteSpace("$($tailscaleSetupCheck.reportJsonPath)") -and
    -not [string]::IsNullOrWhiteSpace($tailscaleSetupCheckMarkdown) -and
    $tailscaleSetupCheckMarkdown -like "*firewall:handoff first*"
  ) $(if ($tailscaleSetupCheck) { "setupReport=$($tailscaleSetupCheck.reportMarkdownPath), setupBackend=$($tailscaleSetupCheck.tailscale.statusSnapshot.backendState), markdownHasHandoff=$($tailscaleSetupCheckMarkdown -like '*firewall:handoff first*')" } else { "missing setup-check JSON" })

  $refreshAuditJsonPath = ""
  $refreshPostAuditBundlePath = ""
  if ($refresh) {
    $refreshAuditJsonPath = "$(@($refresh.artifacts | Where-Object { "$($_.name)" -eq "completion audit JSON" -and $_.exists -eq $true } | Select-Object -First 1).path)"
    $refreshPostAuditBundlePath = "$(@($refresh.steps | Where-Object { "$($_.name)" -eq "Post-audit evidence bundle" } | Select-Object -First 1).primaryPath)"
  }
  $bundleAuditRecords = @()
  if ($bundle -and $bundle.operatorNextActions) {
    $bundleAuditRecords = @($bundle.operatorNextActions | Where-Object { "$($_.name)" -like "completion audit*" -and $_.exists -eq $true })
  }
  $bundleDependencyAuditRecords = @()
  if ($bundle -and $bundle.operatorNextActions) {
    $bundleDependencyAuditRecords = @($bundle.operatorNextActions | Where-Object { "$($_.name)" -like "dependency audit*" -and $_.exists -eq $true })
  }
  $bundleFinalizationRecords = @()
  if ($bundle -and $bundle.operatorNextActions) {
    $bundleFinalizationRecords = @($bundle.operatorNextActions | Where-Object { "$($_.name)" -like "physical finalization*" -and $_.exists -eq $true })
  }
  $bundleActiveFinalizationRecords = @()
  if ($bundle -and $bundle.operatorNextActions) {
    $bundleActiveFinalizationRecords = @($bundle.operatorNextActions | Where-Object {
      $_.exists -eq $true -and "$($_.name)" -in @(
        "active finalization manual DOCX",
        "active finalization traceability Markdown",
        "legacy build manual traceability Markdown"
      )
    })
  }
  $bundleFirewallHandoffRecords = @()
  if ($bundle -and $bundle.operatorNextActions) {
    $bundleFirewallHandoffRecords = @($bundle.operatorNextActions | Where-Object { "$($_.name)" -like "firewall handoff*" -and $_.exists -eq $true })
  }
  $bundleLaunchRecords = @()
  if ($bundle -and $bundle.operatorNextActions) {
    $bundleLaunchRecords = @($bundle.operatorNextActions | Where-Object { "$($_.name)" -like "*physical proof launch*" -and $_.exists -eq $true })
  }
  $refreshBundleMatches = -not [string]::IsNullOrWhiteSpace($refreshAuditJsonPath) -and
    -not [string]::IsNullOrWhiteSpace($refreshPostAuditBundlePath) -and
    $bundle -and
    "$($bundle.bundleMarkdownPath)" -eq $refreshPostAuditBundlePath -and
    @($bundleAuditRecords | Where-Object { "$($_.name)" -eq "completion audit timestamped JSON" -and "$($_.path)" -eq $refreshAuditJsonPath -and [int64]$_.bytes -gt 0 }).Count -gt 0
  if ($refresh -and $bundle -and $refresh.generatedAt -and $bundle.generatedAt) {
    try {
      $bundleNewerThanRefresh = [datetime]::Parse("$($bundle.generatedAt)") -gt [datetime]::Parse("$($refresh.generatedAt)")
    } catch {
      $bundleNewerThanRefresh = $false
    }
  }
  Add-ContentRequirement $requirements "CONTENT-022" "Latest refresh post-audit bundle indexes the completion audit generated by the same refresh run." "phone-acceptance-refresh-latest.json + remote-controller-evidence-bundle-latest.json" (
    $refreshBundleMatches -or $bundleNewerThanRefresh
  ) $(if ($refresh -and $bundle) { "refreshAuditJson=$refreshAuditJsonPath, postAuditBundle=$refreshPostAuditBundlePath, bundleMarkdown=$($bundle.bundleMarkdownPath), auditRecords=$($bundleAuditRecords.Count), matches=$refreshBundleMatches, bundleNewerThanRefresh=$bundleNewerThanRefresh" } else { "missing refresh or evidence bundle JSON" })

  Add-ContentRequirement $requirements "CONTENT-030" "Latest evidence bundle indexes dependency audit JSON and Markdown artifacts." "remote-controller-evidence-bundle-latest.json" (
    $bundle -and
    @($bundleDependencyAuditRecords | Where-Object { "$($_.name)" -eq "dependency audit latest JSON" -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($bundleDependencyAuditRecords | Where-Object { "$($_.name)" -eq "dependency audit latest Markdown" -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($bundleDependencyAuditRecords | Where-Object { "$($_.name)" -eq "dependency audit timestamped JSON" -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($bundleDependencyAuditRecords | Where-Object { "$($_.name)" -eq "dependency audit timestamped Markdown" -and [int64]$_.bytes -gt 0 }).Count -gt 0
  ) $(if ($bundle) { "dependencyAuditRecords=$($bundleDependencyAuditRecords.Count)" } else { "missing evidence bundle JSON" })

  Add-ContentRequirement $requirements "CONTENT-035" "Latest evidence bundle indexes physical finalization JSON and Markdown artifacts." "remote-controller-evidence-bundle-latest.json" (
    $bundle -and
    @($bundleFinalizationRecords | Where-Object { "$($_.name)" -eq "physical finalization latest JSON" -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($bundleFinalizationRecords | Where-Object { "$($_.name)" -eq "physical finalization latest Markdown" -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($bundleFinalizationRecords | Where-Object { "$($_.name)" -eq "physical finalization timestamped JSON" -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($bundleFinalizationRecords | Where-Object { "$($_.name)" -eq "physical finalization timestamped Markdown" -and [int64]$_.bytes -gt 0 }).Count -gt 0
  ) $(if ($bundle) { "finalizationRecords=$($bundleFinalizationRecords.Count)" } else { "missing evidence bundle JSON" })

  Add-ContentRequirement $requirements "CONTENT-055" "Latest evidence bundle indexes the active finalization manual and traceability sources." "remote-controller-evidence-bundle-latest.json" (
    $bundle -and
    @($bundleActiveFinalizationRecords | Where-Object { "$($_.name)" -eq "active finalization manual DOCX" -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($bundleActiveFinalizationRecords | Where-Object { "$($_.name)" -eq "active finalization traceability Markdown" -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($bundleActiveFinalizationRecords | Where-Object { "$($_.name)" -eq "legacy build manual traceability Markdown" -and [int64]$_.bytes -gt 0 }).Count -gt 0
  ) $(if ($bundle) { "activeFinalizationRecords=$($bundleActiveFinalizationRecords.Count)" } else { "missing evidence bundle JSON" })

  Add-ContentRequirement $requirements "CONTENT-045" "Latest evidence bundle indexes firewall handoff JSON, Markdown, and generated elevated script artifacts." "remote-controller-evidence-bundle-latest.json" (
    $bundle -and
    @($bundleFirewallHandoffRecords | Where-Object { "$($_.name)" -eq "firewall handoff latest JSON" -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($bundleFirewallHandoffRecords | Where-Object { "$($_.name)" -eq "firewall handoff latest Markdown" -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($bundleFirewallHandoffRecords | Where-Object { "$($_.name)" -eq "firewall handoff latest script" -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($bundleFirewallHandoffRecords | Where-Object { "$($_.name)" -eq "firewall handoff timestamped JSON" -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($bundleFirewallHandoffRecords | Where-Object { "$($_.name)" -eq "firewall handoff timestamped Markdown" -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($bundleFirewallHandoffRecords | Where-Object { "$($_.name)" -eq "firewall handoff timestamped script" -and [int64]$_.bytes -gt 0 }).Count -gt 0
  ) $(if ($bundle) { "firewallHandoffRecords=$($bundleFirewallHandoffRecords.Count)" } else { "missing evidence bundle JSON" })

  Add-ContentRequirement $requirements "CONTENT-050" "Latest evidence bundle indexes same-Wi-Fi and Tailscale physical proof launch JSON and Markdown artifacts." "remote-controller-evidence-bundle-latest.json" (
    $bundle -and
    @($bundleLaunchRecords | Where-Object { "$($_.name)" -eq "same-Wi-Fi physical proof launch latest JSON" -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($bundleLaunchRecords | Where-Object { "$($_.name)" -eq "same-Wi-Fi physical proof launch latest Markdown" -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($bundleLaunchRecords | Where-Object { "$($_.name)" -eq "same-Wi-Fi physical proof launch timestamped JSON" -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($bundleLaunchRecords | Where-Object { "$($_.name)" -eq "same-Wi-Fi physical proof launch timestamped Markdown" -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($bundleLaunchRecords | Where-Object { "$($_.name)" -eq "Tailscale physical proof launch latest JSON" -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($bundleLaunchRecords | Where-Object { "$($_.name)" -eq "Tailscale physical proof launch latest Markdown" -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($bundleLaunchRecords | Where-Object { "$($_.name)" -eq "Tailscale physical proof launch timestamped JSON" -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($bundleLaunchRecords | Where-Object { "$($_.name)" -eq "Tailscale physical proof launch timestamped Markdown" -and [int64]$_.bytes -gt 0 }).Count -gt 0
  ) $(if ($bundle) { "launchRecords=$($bundleLaunchRecords.Count)" } else { "missing evidence bundle JSON" })

  Add-ContentRequirement $requirements "CONTENT-011" "Latest QA report proves automated tests and script self-tests passed against a screen-capture host." "qa-report-latest.json" (
    $qaReport -and
    $qaReport.ok -eq $true -and
    $qaReport.host -and "$($qaReport.host.mode)" -eq "milestone-2-screen-capture" -and
    $qaReport.nodeTests -and [int]$qaReport.nodeTests.exitCode -eq 0 -and
    $qaReport.nodeTests.summary -and [int]$qaReport.nodeTests.summary.fail -eq 0 -and
    [int]$qaReport.nodeTests.summary.pass -gt 0 -and
    @($qaReport.selfTests | Where-Object { $_.ok -eq $false }).Count -eq 0 -and
    @($qaReport.selfTests).Count -ge 20
  ) $(if ($qaReport) { "nodePass=$($qaReport.nodeTests.summary.pass), nodeFail=$($qaReport.nodeTests.summary.fail), selfTests=$(@($qaReport.selfTests).Count), mode=$($qaReport.host.mode)" } else { "missing or invalid JSON" })

  $requiredQaSelfTests = @(
    [pscustomobject]@{ name = "tray host"; script = "scripts\tray-host.ps1" },
    [pscustomobject]@{ name = "acceptance report"; script = "scripts\acceptance-report.ps1" },
    [pscustomobject]@{ name = "manual phone acceptance"; script = "scripts\manual-phone-acceptance.ps1" },
    [pscustomobject]@{ name = "acceptance doctor"; script = "scripts\acceptance-doctor.ps1" },
    [pscustomobject]@{ name = "prepare phone acceptance"; script = "scripts\prepare-phone-acceptance.ps1" },
    [pscustomobject]@{ name = "acceptance ready"; script = "scripts\acceptance-ready.ps1" },
    [pscustomobject]@{ name = "acceptance next"; script = "scripts\acceptance-next.ps1" },
    [pscustomobject]@{ name = "physical proof runbook"; script = "scripts\physical-proof-runbook.ps1" },
    [pscustomobject]@{ name = "physical proof launch"; script = "scripts\physical-proof-launch.ps1" },
    [pscustomobject]@{ name = "acceptance dashboard"; script = "scripts\acceptance-dashboard.ps1" },
    [pscustomobject]@{ name = "acceptance handoff"; script = "scripts\acceptance-handoff.ps1" },
    [pscustomobject]@{ name = "acceptance refresh"; script = "scripts\acceptance-refresh.ps1" },
    [pscustomobject]@{ name = "physical evidence finalization"; script = "scripts\finalize-physical-evidence.ps1" },
    [pscustomobject]@{ name = "attach phone evidence"; script = "scripts\attach-phone-evidence.ps1" },
    [pscustomobject]@{ name = "stop phone acceptance"; script = "scripts\stop-phone-acceptance.ps1" },
    [pscustomobject]@{ name = "verify phone acceptance"; script = "scripts\verify-phone-acceptance.ps1" },
    [pscustomobject]@{ name = "watch phone acceptance"; script = "scripts\watch-phone-acceptance.ps1" },
      [pscustomobject]@{ name = "tailscale setup check"; script = "scripts\tailscale-setup-check.ps1" },
      [pscustomobject]@{ name = "tailscale bootstrap"; script = "scripts\tailscale-bootstrap.ps1" },
      [pscustomobject]@{ name = "firewall rule"; script = "scripts\firewall-rule.ps1" },
      [pscustomobject]@{ name = "firewall handoff"; script = "scripts\firewall-handoff.ps1" },
      [pscustomobject]@{ name = "desktop shortcut"; script = "scripts\install-shortcut.ps1" },
      [pscustomobject]@{ name = "install autostart"; script = "scripts\install-autostart.ps1" },
    [pscustomobject]@{ name = "uninstall autostart"; script = "scripts\uninstall-autostart.ps1" },
    [pscustomobject]@{ name = "dependency audit"; script = "scripts\dependency-audit.ps1" },
    [pscustomobject]@{ name = "completion audit"; script = "scripts\completion-audit.ps1" },
    [pscustomobject]@{ name = "evidence bundle"; script = "scripts\evidence-bundle.ps1" }
  )
  $qaSelfTestNames = @()
  if ($qaReport -and $qaReport.selfTests) {
    $qaSelfTestNames = @($qaReport.selfTests | ForEach-Object { "$($_.name)" })
  }
  $missingQaSelfTests = @($requiredQaSelfTests | Where-Object { $qaSelfTestNames -notcontains "$($_.name)" })
  Add-ContentRequirement $requirements "CONTENT-015" "Latest QA report includes every required named script self-test suite." "qa-report-latest.json" (
    $qaReport -and $missingQaSelfTests.Count -eq 0
  ) $(if ($qaReport) { "missingSelfTests=$($missingQaSelfTests.Count)" } else { "missing or invalid JSON" })

  $wrongQaSelfTestScripts = @()
  if ($qaReport -and $qaReport.selfTests) {
    $wrongQaSelfTestScripts = @($requiredQaSelfTests | Where-Object {
      $expected = $_
      @($qaReport.selfTests | Where-Object { "$($_.name)" -eq "$($expected.name)" -and "$($_.script)" -eq "$($expected.script)" }).Count -eq 0
    })
  }
  Add-ContentRequirement $requirements "CONTENT-016" "Latest QA report maps every required script self-test suite to the expected implementation script path." "qa-report-latest.json" (
    $qaReport -and $wrongQaSelfTestScripts.Count -eq 0
  ) $(if ($qaReport) { "wrongSelfTestScripts=$($wrongQaSelfTestScripts.Count)" } else { "missing or invalid JSON" })

  Add-ContentRequirement $requirements "CONTENT-017" "Latest QA report Markdown visibly exposes test totals, named self-test rows, artifact snapshot rows, and physical gate reminder." "qa-report-latest.md" (
    -not [string]::IsNullOrWhiteSpace($qaReportMarkdown) -and
    $qaReportMarkdown -like "*Node pass:*" -and
    $qaReportMarkdown -like "*Node fail:*" -and
    $qaReportMarkdown -like "*## Self-Tests*" -and
    $qaReportMarkdown -like "*verify phone acceptance*" -and
    $qaReportMarkdown -like "*scripts\verify-phone-acceptance.ps1*" -and
    $qaReportMarkdown -like "*## Operator Artifact Snapshot*" -and
    $qaReportMarkdown -like "*completion audit latest JSON*" -and
    $qaReportMarkdown -like "*## Physical Gates*"
  ) $(if ([string]::IsNullOrWhiteSpace($qaReportMarkdown)) { "missing or empty Markdown" } else { "qaReportMarkdownBytes=$($qaReportMarkdown.Length)" })

  $samePhoneEvidence = Get-OptionalPhoneEvidenceValidation -Gate "same-wifi" -SelectedOutputDir $SelectedOutputDir
  $tailscalePhoneEvidence = Get-OptionalPhoneEvidenceValidation -Gate "tailscale" -SelectedOutputDir $SelectedOutputDir
  Add-ContentRequirement $requirements "CONTENT-018" "Optional attached phone screenshot/photo evidence is supporting-only, gate-matched, copied into the evidence folder, and hash-verified when present." "phone-evidence-*-latest.json" (
    $samePhoneEvidence.passed -eq $true -and $tailscalePhoneEvidence.passed -eq $true
  ) "same-wifi: $($samePhoneEvidence.detail); tailscale: $($tailscalePhoneEvidence.detail)"

  $qaFreshness = Get-QaFreshnessValidation -QaReport $qaReport
  Add-ContentRequirement $requirements "CONTENT-019" "Latest QA report was generated after the newest implementation, test, package, or acceptance script file change." "qa-report-latest.json" (
    $qaFreshness.passed -eq $true
  ) $qaFreshness.detail

  Add-ContentRequirement $requirements "CONTENT-020" "Latest dashboard and handoff were generated from the current QA report identity, not just mutable latest links." "phone-acceptance-dashboard-latest.json + phone-acceptance-handoff-latest.json" (
    $qaReport -and
    $dashboard -and
    $handoff -and
    "$($dashboard.qaGeneratedAt)" -eq "$($qaReport.generatedAt)" -and
    "$($handoff.qaGeneratedAt)" -eq "$($qaReport.generatedAt)" -and
    -not [string]::IsNullOrWhiteSpace("$($qaReport.reportJsonPath)") -and
    -not [string]::IsNullOrWhiteSpace("$($qaReport.reportMarkdownPath)") -and
    "$($dashboard.qaTimestampedReportPath)" -eq "$($qaReport.reportJsonPath)" -and
    "$($handoff.qaTimestampedReportPath)" -eq "$($qaReport.reportJsonPath)" -and
    "$($dashboard.qaTimestampedReportMarkdownPath)" -eq "$($qaReport.reportMarkdownPath)" -and
    "$($handoff.qaTimestampedReportMarkdownPath)" -eq "$($qaReport.reportMarkdownPath)"
  ) $(if ($qaReport -and $dashboard -and $handoff) { "qaGeneratedAt=$($qaReport.generatedAt), dashboardQa=$($dashboard.qaGeneratedAt), handoffQa=$($handoff.qaGeneratedAt), qaReport=$($qaReport.reportJsonPath)" } else { "missing QA, dashboard, or handoff JSON" })

  $bundleQaRecords = @()
  if ($bundle -and $bundle.operatorNextActions) {
    $bundleQaRecords = @($bundle.operatorNextActions | Where-Object { "$($_.name)" -like "QA report*" -and $_.exists -eq $true })
  }
  Add-ContentRequirement $requirements "CONTENT-021" "Latest evidence bundle indexes the current timestamped QA report identity used by the dashboard and handoff." "remote-controller-evidence-bundle-latest.json" (
    $qaReport -and
    -not [string]::IsNullOrWhiteSpace("$($qaReport.reportJsonPath)") -and
    -not [string]::IsNullOrWhiteSpace("$($qaReport.reportMarkdownPath)") -and
    @($bundleQaRecords | Where-Object { "$($_.name)" -eq "QA report timestamped JSON" -and "$($_.path)" -eq "$($qaReport.reportJsonPath)" -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($bundleQaRecords | Where-Object { "$($_.name)" -eq "QA report timestamped Markdown" -and "$($_.path)" -eq "$($qaReport.reportMarkdownPath)" -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($bundleQaRecords | Where-Object { "$($_.name)" -eq "QA report latest JSON" -and "$($_.path)" -eq "$($qaReport.latestReportJsonPath)" -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($bundleQaRecords | Where-Object { "$($_.name)" -eq "QA report latest Markdown" -and "$($_.path)" -eq "$($qaReport.latestReportMarkdownPath)" -and [int64]$_.bytes -gt 0 }).Count -gt 0
  ) $(if ($qaReport -and $bundle) { "qaBundleRecords=$($bundleQaRecords.Count), qaReport=$($qaReport.reportJsonPath)" } else { "missing QA report or evidence bundle JSON" })

  Add-ContentRequirement $requirements "CONTENT-012" "Latest dashboard exposes saved QA status and QA report links beside the physical gates." "phone-acceptance-dashboard-latest.json" (
    $dashboard -and
    $dashboard.qaOk -eq $true -and
    [int]$dashboard.qaPass -gt 0 -and
    [int]$dashboard.qaFail -eq 0 -and
    [int]$dashboard.qaSelfTests -ge 20 -and
    "$($dashboard.qaHostMode)" -eq "milestone-2-screen-capture" -and
    (Test-AnyStringContains @($dashboard.qaReportPath, $dashboard.qaReportMarkdownPath) "qa-report-latest")
  ) $(if ($dashboard) { "qaOk=$($dashboard.qaOk), pass=$($dashboard.qaPass), fail=$($dashboard.qaFail), selfTests=$($dashboard.qaSelfTests), mode=$($dashboard.qaHostMode)" } else { "missing or invalid JSON" })

  Add-ContentRequirement $requirements "CONTENT-013" "Latest handoff exposes saved QA status and QA report links before the real phone run." "phone-acceptance-handoff-latest.json" (
    $handoff -and
    $handoff.qaOk -eq $true -and
    [int]$handoff.qaPass -gt 0 -and
    [int]$handoff.qaFail -eq 0 -and
    [int]$handoff.qaSelfTests -ge 20 -and
    "$($handoff.qaHostMode)" -eq "milestone-2-screen-capture" -and
    (Test-AnyStringContains @($handoff.qaReportPath, $handoff.qaReportMarkdownPath) "qa-report-latest")
  ) $(if ($handoff) { "qaOk=$($handoff.qaOk), pass=$($handoff.qaPass), fail=$($handoff.qaFail), selfTests=$($handoff.qaSelfTests), mode=$($handoff.qaHostMode)" } else { "missing or invalid JSON" })

  Add-ContentRequirement $requirements "CONTENT-047" "Latest handoff Markdown exposes gate warnings and the handoff-first firewall action for scan-first physical runs." "phone-acceptance-handoff-latest.md + scripts\acceptance-handoff.ps1" (
    -not [string]::IsNullOrWhiteSpace($handoffMarkdown) -and
    $acceptanceHandoffText -like "*Warnings:*" -and
    $acceptanceHandoffText -like "*nextAction*" -and
    $handoffMarkdown -like "*Warnings:*" -and
    $handoffMarkdown -like "*firewall:handoff first*"
  ) $(if ([string]::IsNullOrWhiteSpace($handoffMarkdown)) { "missing or empty handoff Markdown" } else { "handoffMarkdownBytes=$($handoffMarkdown.Length), scriptWarnings=$($acceptanceHandoffText -like '*Warnings:*')" })

  $qaArtifactSnapshot = @()
  if ($qaReport -and $qaReport.artifacts) {
    $qaArtifactSnapshot = @($qaReport.artifacts)
  }
  Add-ContentRequirement $requirements "CONTENT-014" "Latest QA report records the current operator artifact snapshot for dashboard, handoff, launch, evidence, refresh, and audit files." "qa-report-latest.json" (
    $qaReport -and
    @($qaArtifactSnapshot | Where-Object { "$($_.relativePath)" -eq "phone-acceptance-dashboard-latest.html" -and $_.exists -eq $true -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($qaArtifactSnapshot | Where-Object { "$($_.relativePath)" -eq "phone-acceptance-handoff-latest.html" -and $_.exists -eq $true -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($qaArtifactSnapshot | Where-Object { "$($_.relativePath)" -eq "physical-proof-launch-same-wifi-latest.json" -and $_.exists -eq $true -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($qaArtifactSnapshot | Where-Object { "$($_.relativePath)" -eq "physical-proof-launch-same-wifi-latest.md" -and $_.exists -eq $true -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($qaArtifactSnapshot | Where-Object { "$($_.relativePath)" -eq "physical-proof-launch-tailscale-latest.json" -and $_.exists -eq $true -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($qaArtifactSnapshot | Where-Object { "$($_.relativePath)" -eq "physical-proof-launch-tailscale-latest.md" -and $_.exists -eq $true -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($qaArtifactSnapshot | Where-Object { "$($_.relativePath)" -eq "remote-controller-evidence-bundle-latest.json" -and $_.exists -eq $true -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($qaArtifactSnapshot | Where-Object { "$($_.relativePath)" -eq "docs\Remote_Controller_Finalization_Plan.docx" -and $_.exists -eq $true -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($qaArtifactSnapshot | Where-Object { "$($_.relativePath)" -eq "docs\FINALIZATION_TRACEABILITY.md" -and $_.exists -eq $true -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($qaArtifactSnapshot | Where-Object { "$($_.relativePath)" -eq "docs\TRACEABILITY_AUDIT.md" -and $_.exists -eq $true -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($qaArtifactSnapshot | Where-Object { "$($_.relativePath)" -eq "phone-acceptance-refresh-latest.json" -and $_.exists -eq $true -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($qaArtifactSnapshot | Where-Object { "$($_.relativePath)" -eq "physical-evidence-finalization-latest.json" -and $_.exists -eq $true -and [int64]$_.bytes -gt 0 }).Count -gt 0 -and
    @($qaArtifactSnapshot | Where-Object { "$($_.relativePath)" -eq "completion-audit-latest.json" -and $_.exists -eq $true -and [int64]$_.bytes -gt 0 }).Count -gt 0
  ) $(if ($qaReport) { "artifactSnapshotCount=$($qaArtifactSnapshot.Count)" } else { "missing or invalid JSON" })

  $sameWifi = Invoke-GateVerification -Gate "same-wifi" -SelectedOutputDir $SelectedOutputDir
  Add-Requirement $requirements "PHYSICAL-001" "Same-Wi-Fi physical phone acceptance evidence passes the verifier." "npm run acceptance:verify -- -Gate same-wifi" $sameWifi.ok (Format-GateVerificationDetail -GateResult $sameWifi)

  $tailscale = Invoke-GateVerification -Gate "tailscale" -SelectedOutputDir $SelectedOutputDir
  Add-Requirement $requirements "PHYSICAL-002" "Tailscale/different-Wi-Fi physical phone acceptance evidence passes the verifier." "npm run acceptance:verify -- -Gate tailscale" $tailscale.ok (Format-GateVerificationDetail -GateResult $tailscale)

  Add-Requirement $requirements "PHYSICAL-003" "Both physical gates are present before the build can be called complete." "PHYSICAL-001 + PHYSICAL-002" ($sameWifi.ok -and $tailscale.ok) "same-wifi=$($sameWifi.ok), tailscale=$($tailscale.ok)"

  $failed = @($requirements | Where-Object { -not $_.passed })
  return [pscustomobject]@{
    ok = $failed.Count -eq 0
    generatedAt = (Get-Date).ToString("o")
    status = if ($failed.Count -eq 0) { "complete-evidence-present" } else { "not-complete" }
    sourceDoc = $sourceDoc
    finalizationDoc = $finalizationDoc
    outputDir = "$resolvedOutputDir"
    requirementCount = $requirements.Count
    failedCount = $failed.Count
    failedIds = @($failed | ForEach-Object { $_.id })
    gates = [pscustomobject]@{
      sameWifi = $sameWifi.ok
      tailscale = $tailscale.ok
    }
    requirements = $requirements
  }
}

if ($SelfTest) {
  $tempOutput = Join-Path ([System.IO.Path]::GetTempPath()) "remote-completion-audit-empty-$([guid]::NewGuid().ToString('N'))"
  New-Item -ItemType Directory -Path $tempOutput -Force | Out-Null
  foreach ($artifactName in @("phone-acceptance-next-latest.md", "physical-proof-runbook-latest.md", "phone-acceptance-dashboard-latest.html", "phone-acceptance-handoff-latest.html", "phone-acceptance-handoff-latest.md", "remote-controller-evidence-bundle-latest.md", "phone-acceptance-refresh-latest.md", "tailscale-bootstrap-latest.md", "physical-evidence-finalization-latest.md")) {
    "self-test artifact" | Set-Content -LiteralPath (Join-Path $tempOutput $artifactName) -Encoding UTF8
  }
  "Warnings:`n`n- warning: firewall: missing. Next: If the phone cannot connect, run npm run firewall:handoff first, then run the copied elevated install command only if you choose to allow inbound TCP 4317." | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-handoff-latest.md") -Encoding UTF8
  @"
# QA Report

Node pass: 37
Node fail: 0

## Self-Tests

| OK | Name | Script |
| --- | --- | --- |
| True | verify phone acceptance | scripts\verify-phone-acceptance.ps1 |

## Operator Artifact Snapshot

| Exists | Name | Relative Path | Bytes | Last Write |
| --- | --- | --- | --- | --- |
| True | completion audit latest JSON | completion-audit-latest.json | 100 | 2026-01-01T00:00:00.0000000Z |

## Physical Gates
"@ | Set-Content -LiteralPath (Join-Path $tempOutput "qa-report-latest.md") -Encoding UTF8
  $fixtureQaGeneratedAt = (Get-Date).ToString("o")
  $selfTestRunbookQrPath = Join-Path $tempOutput "same-runbook-qr.svg"
  "<svg xmlns=""http://www.w3.org/2000/svg"" viewBox=""0 0 10 10""><rect width=""10"" height=""10"" fill=""white""/><rect x=""1"" y=""1"" width=""8"" height=""8"" fill=""black""/></svg>" | Set-Content -LiteralPath $selfTestRunbookQrPath -Encoding UTF8
  $selfTestRunCardHtmlPath = Join-Path $tempOutput "same-run-card.html"
  "<!doctype html><html><body><h1>Physical Phone Acceptance Session</h1><a href=""http://192.168.1.20:4317?v=57&amp;acceptance=1&amp;gate=same-wifi&amp;step=physical-phone-proof"">same-wifi proof</a></body></html>" | Set-Content -LiteralPath $selfTestRunCardHtmlPath -Encoding UTF8
  [pscustomobject]@{
    ok = $true
    generatedAt = (Get-Date).ToString("o")
    zipPath = "C:\fake\RemoteController-LocalWiFi.zip"
    sha256 = "SELFTEST"
    sizeMB = 1.25
    smokeRoot = "C:\fake\package-smoke"
    port = 4417
    phoneShell = "loaded"
    phoneAppVersion = "67"
    serviceWorker = "remote-controller-shell-v67"
    hostConsolePhoneUrls = "v62"
    hostConsoleCheckedUrlCount = 19
    transport = "native-websocket-binary-jpeg"
    inputEnabled = $true
    packageManifestClean = $true
    readmeFirstClean = $true
    portConflictGuard = $true
    stalePidGuard = $true
    packageManifestScripts = @("start", "stop", "smoke")
    packageManifestScriptCount = 3
    listenerStopped = $true
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempOutput "package-smoke-latest.json") -Encoding UTF8
  [byte[]](0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0x53,0x45,0x4C,0x46,0x54,0x45,0x53,0x54) | Set-Content -LiteralPath (Join-Path $tempOutput "live-phone-visual-proof-latest.png") -Encoding Byte
  [pscustomobject]@{
    ok = $true
    generatedAt = (Get-Date).ToString("o")
    phoneAppVersion = "67"
    hostMode = "milestone-2-screen-capture"
    screenshotPath = Join-Path $tempOutput "live-phone-visual-proof-latest.png"
    latestScreenshotPath = Join-Path $tempOutput "live-phone-visual-proof-latest.png"
    visual = [pscustomobject]@{
      connected = $true
      binaryTransport = $true
      frameImageReady = $true
      activePixelRatio = 0.2
      goldPixelSamples = 20
      cursorCenteredInLens = $true
      bottomEdgeCursorVisible = $true
      bottomEdgeProof = [pscustomobject]@{
        sourceNearBottom = $true
        canvasNearBottom = $true
        normalizedY = 0.985
      }
    }
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempOutput "live-phone-visual-proof-latest.json") -Encoding UTF8
  [pscustomobject]@{
    ok = $true
    evidencePassed = $false
    status = "ready-for-phone"
    gate = "same-wifi"
    primaryPhoneUrl = "http://192.168.1.20:4317?v=57&acceptance=1&gate=same-wifi&step=physical-phone-proof"
    phoneUrls = @("http://192.168.1.20:4317?v=57&acceptance=1&gate=same-wifi&step=physical-phone-proof")
    runCardHtml = $selfTestRunCardHtmlPath
    setupBlockerCount = 0
    physicalBlockerCount = 2
    hostHealth = [pscustomobject]@{ reachable = $true }
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-ready-same-wifi-latest.json") -Encoding UTF8
  [pscustomobject]@{
    ok = $false
    evidencePassed = $false
    status = "setup-needed"
    gate = "tailscale"
    primaryPhoneUrl = ""
    phoneUrls = @()
    setupBlockerCount = 1
    physicalBlockerCount = 0
    readyActions = @("Open https://login.tailscale.com/a/selftest, sign in, then run npm run acceptance:ready -- -Gate tailscale.")
    prepareFailures = @([pscustomobject]@{ name = "prepare: tailscale URL"; detail = "No Tailscale URL"; nextAction = "Open https://login.tailscale.com/a/selftest, sign in, then run npm run acceptance:ready -- -Gate tailscale." })
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-ready-tailscale-latest.json") -Encoding UTF8
  [pscustomobject]@{
    ok = $true
    gate = "same-wifi"
    readinessStatus = "ready-for-phone"
    primaryPhoneUrl = "http://192.168.1.20:4317?v=57&acceptance=1&gate=same-wifi&step=physical-phone-proof"
    failedChecks = @([pscustomobject]@{ name = "phone proof log exists"; detail = "event=acceptance.phoneMark" })
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-watch-same-wifi-latest.json") -Encoding UTF8
  [pscustomobject]@{
    ok = $false
    gate = "tailscale"
    readinessStatus = "setup-needed"
    primaryPhoneUrl = ""
    failedChecks = @([pscustomobject]@{ name = "selected-gate URL preflight exists"; detail = "preflight checks=0" })
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-watch-tailscale-latest.json") -Encoding UTF8
  [pscustomobject]@{
    ok = $true
    status = "some-ready"
    operatorRunNow = [pscustomobject]@{
      firstCommand = "npm run acceptance:phone -- -Gate same-wifi -SkipStart -RequireReady"
      finalCommand = "npm run acceptance:finalize"
      doNotRefreshAfterProof = $true
      steps = @(
        "Run the same-Wi-Fi phone proof now: npm run acceptance:phone -- -Gate same-wifi -SkipStart -RequireReady",
        "Refresh the Tailscale setup evidence after any sign-in or network change: npm run tailscale:check:save",
        "After both saved verifiers pass, do not run npm run acceptance:refresh; run npm run acceptance:finalize so no newer readiness artifact invalidates the proof."
      )
    }
    gates = @(
      [pscustomobject]@{ gate = "same-wifi"; status = "ready-for-phone"; primaryPhoneUrl = "http://192.168.1.20:4317?v=57&acceptance=1&gate=same-wifi&step=physical-phone-proof" },
      [pscustomobject]@{ gate = "tailscale"; status = "setup-needed"; primaryPhoneUrl = ""; actions = @("Review the latest Tailscale setup check: C:\tmp\tailscale-setup-check-latest.md") }
    )
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-next-latest.json") -Encoding UTF8
  [pscustomobject]@{
    ok = $true
    status = "same-wifi-ready-tailscale-setup-needed"
    completionReady = $false
    onlyPhysicalAuditFailures = $true
    failedAuditIds = @("PHYSICAL-001", "PHYSICAL-002", "PHYSICAL-003")
    operatorRunNow = [pscustomobject]@{
      firstCommand = "npm run acceptance:phone -- -Gate same-wifi -SkipStart -RequireReady"
      finalCommand = "npm run acceptance:finalize"
      doNotRefreshAfterProof = $true
      steps = @("Run same-wifi: npm run acceptance:phone -- -Gate same-wifi -SkipStart -RequireReady", "Refresh the Tailscale setup evidence after any sign-in or network change: npm run tailscale:check:save", "After both saved verifiers pass, do not run npm run acceptance:refresh; run npm run acceptance:finalize.")
    }
    gates = @(
      [pscustomobject]@{ gate = "same-wifi"; status = "ready-for-phone"; primaryPhoneUrl = "http://192.168.1.20:4317?v=57&acceptance=1&gate=same-wifi&step=physical-phone-proof"; runCardHtml = $selfTestRunCardHtmlPath; hostConsole = "http://127.0.0.1:4317/host?key=selftest"; currentPin = [pscustomobject]@{ available = $true; pin = "123456"; secondsRemaining = 120; refreshedAt = (Get-Date).ToString("o"); source = "host-refresh"; error = "" }; qrCodes = @([pscustomobject]@{ url = "http://192.168.1.20:4317?v=57&acceptance=1&gate=same-wifi&step=physical-phone-proof"; path = $selfTestRunbookQrPath; exists = $true }) },
      [pscustomobject]@{ gate = "tailscale"; status = "setup-needed"; primaryPhoneUrl = ""; runCardHtml = ""; hostConsole = "http://127.0.0.1:4317/host?key=selftest"; currentPin = [pscustomobject]@{ available = $false; pin = ""; secondsRemaining = 0; refreshedAt = ""; source = ""; error = "setup-needed" }; qrCodes = @(); actions = @("Review the latest Tailscale setup check: C:\tmp\tailscale-setup-check-latest.md") }
    )
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempOutput "physical-proof-runbook-latest.json") -Encoding UTF8
  "Host console: http://127.0.0.1:4317/host?key=selftest`n`nCurrent PIN:`n`n- PIN: 123456`n- Source: host-refresh`n- Refreshed: $((Get-Date).ToString("o"))`n- Expires in about: 120 seconds`n`nQR files`n`n- $selfTestRunbookQrPath`n`nReview the latest Tailscale setup check: C:\tmp\tailscale-setup-check-latest.md`nRefresh the Tailscale setup evidence after any sign-in or network change: npm run tailscale:check:save`n`nDo not run ``npm run acceptance:refresh`` after both saved verifier commands pass. Use ``npm run acceptance:finalize`` so the final evidence stays current." | Set-Content -LiteralPath (Join-Path $tempOutput "physical-proof-runbook-latest.md") -Encoding UTF8
  [pscustomobject]@{
    ok = $true
    gate = "same-wifi"
    status = "ready-for-phone"
    primaryPhoneUrl = "http://192.168.1.20:4317?v=57&acceptance=1&gate=same-wifi&step=physical-phone-proof"
    hostConsole = "http://127.0.0.1:4317/host?key=selftest"
    currentPin = [pscustomobject]@{ available = $true; pin = "123456"; secondsRemaining = 120; refreshedAt = (Get-Date).ToString("o"); source = "host-refresh"; hostConsole = "http://127.0.0.1:4317/host?key=selftest"; error = "" }
    clipboardKind = "phone-url"
    actions = @("Open this URL on the phone: http://192.168.1.20:4317?v=57&acceptance=1&gate=same-wifi&step=physical-phone-proof")
    failedChecks = @([pscustomobject]@{ name = "phone proof log exists"; detail = "event=acceptance.phoneMark"; nextAction = "Open the same-wifi proof URL on the phone, complete the proof checklist, tap Mark Proof, then complete npm run acceptance:phone -- -Gate same-wifi -SkipStart -RequireReady." })
    warnings = @([pscustomobject]@{ name = "warning: windows firewall rule"; detail = "Inbound TCP 4317 rule is not installed or not ready."; nextAction = "Run npm run firewall:handoff first if needed." })
    doesNotReplaceVerifier = $true
    doesNotMarkPhysicalGate = $true
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempOutput "physical-proof-launch-same-wifi-latest.json") -Encoding UTF8
  "# Same-Wi-Fi Physical Proof Launch`n`n## Current PIN`n`n- Host console: http://127.0.0.1:4317/host?key=selftest`n- PIN: 123456`n- Source: host-refresh`n- Refreshed: $((Get-Date).ToString("o"))`n- Expires in about: 120 seconds`n`n## Run Actions`n`n1. Open this URL on the phone: http://192.168.1.20:4317?v=57&acceptance=1&gate=same-wifi&step=physical-phone-proof`n`n## Current Blockers`n`n- phone proof log exists: event=acceptance.phoneMark Next: Open the same-wifi proof URL on the phone, complete the proof checklist, tap Mark Proof, then complete npm run acceptance:phone -- -Gate same-wifi -SkipStart -RequireReady.`n`n## Warnings`n`n- warning: windows firewall rule: Inbound TCP 4317 rule is not installed or not ready. Next: Run npm run firewall:handoff first if needed." | Set-Content -LiteralPath (Join-Path $tempOutput "physical-proof-launch-same-wifi-latest.md") -Encoding UTF8
  [pscustomobject]@{
    ok = $true
    gate = "tailscale"
    status = "setup-needed"
    setupUrl = "https://login.tailscale.com/a/selftest"
    hostConsole = "http://127.0.0.1:4317/host?key=selftest"
    currentPin = [pscustomobject]@{ available = $false; pin = ""; secondsRemaining = 0; refreshedAt = ""; source = "setup-needed"; hostConsole = "http://127.0.0.1:4317/host?key=selftest"; error = "setup-needed" }
    clipboardKind = "setup-url"
    actions = @("Open this URL on the phone: http://100.64.0.1:4317?v=57&acceptance=1&gate=tailscale&step=physical-phone-proof")
    failedChecks = @([pscustomobject]@{ name = "phone proof log exists"; detail = "event=acceptance.phoneMark"; nextAction = "Open the tailscale proof URL on the phone, complete the proof checklist, tap Mark Proof, then complete npm run acceptance:phone -- -Gate tailscale -SkipStart -RequireReady." })
    warnings = @([pscustomobject]@{ name = "warning: windows firewall rule"; detail = "Inbound TCP 4317 rule is not installed or not ready."; nextAction = "Run npm run firewall:handoff first if needed." })
    doesNotReplaceVerifier = $true
    doesNotMarkPhysicalGate = $true
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempOutput "physical-proof-launch-tailscale-latest.json") -Encoding UTF8
  "# Tailscale Physical Proof Launch`n`n## Current PIN`n`n- Host console: http://127.0.0.1:4317/host?key=selftest`n- unavailable: setup-needed`n- Source: setup-needed`n`n## Run Actions`n`n1. Open this URL on the phone: http://100.64.0.1:4317?v=57&acceptance=1&gate=tailscale&step=physical-phone-proof`n`n## Current Blockers`n`n- phone proof log exists: event=acceptance.phoneMark Next: Open the tailscale proof URL on the phone, complete the proof checklist, tap Mark Proof, then complete npm run acceptance:phone -- -Gate tailscale -SkipStart -RequireReady.`n`n## Warnings`n`n- warning: windows firewall rule: Inbound TCP 4317 rule is not installed or not ready. Next: Run npm run firewall:handoff first if needed." | Set-Content -LiteralPath (Join-Path $tempOutput "physical-proof-launch-tailscale-latest.md") -Encoding UTF8
  [pscustomobject]@{
    ok = $true
    gates = @(
      [pscustomobject]@{ gate = "same-wifi"; status = "ready-for-phone"; primaryPhoneUrl = "http://192.168.1.20:4317?v=57&acceptance=1&gate=same-wifi&step=physical-phone-proof" },
      [pscustomobject]@{ gate = "tailscale"; status = "setup-needed"; primaryPhoneUrl = "" }
    )
    qaOk = $true
    qaPass = 37
    qaFail = 0
    qaSelfTests = 21
    qaHostMode = "milestone-2-screen-capture"
    qaReportPath = Join-Path $tempOutput "qa-report-latest.json"
    qaReportMarkdownPath = Join-Path $tempOutput "qa-report-latest.md"
    qaGeneratedAt = $fixtureQaGeneratedAt
    qaTimestampedReportPath = Join-Path $tempOutput "qa-report-20260101-000000.json"
    qaTimestampedReportMarkdownPath = Join-Path $tempOutput "qa-report-20260101-000000.md"
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-dashboard-latest.json") -Encoding UTF8
  [pscustomobject]@{
    ok = $true
    status = "same-wifi-ready"
    qaOk = $true
    qaPass = 37
    qaFail = 0
    qaSelfTests = 21
    qaHostMode = "milestone-2-screen-capture"
    qaReportPath = Join-Path $tempOutput "qa-report-latest.json"
    qaReportMarkdownPath = Join-Path $tempOutput "qa-report-latest.md"
    qaGeneratedAt = $fixtureQaGeneratedAt
    qaTimestampedReportPath = Join-Path $tempOutput "qa-report-20260101-000000.json"
    qaTimestampedReportMarkdownPath = Join-Path $tempOutput "qa-report-20260101-000000.md"
    gates = @(
      [pscustomobject]@{ gate = "same-wifi"; status = "ready-for-phone"; primaryPhoneUrl = "http://192.168.1.20:4317?v=57&acceptance=1&gate=same-wifi&step=physical-phone-proof"; qrPath = (Join-Path $tempOutput "same.svg"); actions = @("Run same-wifi") },
      [pscustomobject]@{ gate = "tailscale"; status = "setup-needed"; primaryPhoneUrl = ""; actions = @("Install/start Tailscale"); failedChecks = @([pscustomobject]@{ name = "prepare: tailscale URL" }) }
    )
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-handoff-latest.json") -Encoding UTF8
  [pscustomobject]@{
    ok = $false
    gates = @(
      [pscustomobject]@{ gate = "same-wifi"; latestVerifierJsonPath = Join-Path $tempOutput "phone-acceptance-verification-same-wifi-latest.json" },
      [pscustomobject]@{ gate = "tailscale"; latestVerifierJsonPath = Join-Path $tempOutput "phone-acceptance-verification-tailscale-latest.json" }
    )
    operatorNextActions = @(
      [pscustomobject]@{ name = "acceptance handoff latest JSON"; exists = $true; path = Join-Path $tempOutput "phone-acceptance-handoff-latest.json" },
      [pscustomobject]@{ name = "acceptance handoff latest Markdown"; exists = $true; path = Join-Path $tempOutput "phone-acceptance-handoff-latest.md" },
      [pscustomobject]@{ name = "acceptance handoff latest HTML"; exists = $true; path = Join-Path $tempOutput "phone-acceptance-handoff-latest.html" },
      [pscustomobject]@{ name = "acceptance handoff timestamped JSON"; exists = $true; path = Join-Path $tempOutput "phone-acceptance-handoff-20260101-000000.json" },
      [pscustomobject]@{ name = "acceptance handoff timestamped Markdown"; exists = $true; path = Join-Path $tempOutput "phone-acceptance-handoff-20260101-000000.md" },
      [pscustomobject]@{ name = "acceptance handoff timestamped HTML"; exists = $true; path = Join-Path $tempOutput "phone-acceptance-handoff-20260101-000000.html" },
      [pscustomobject]@{ name = "physical proof runbook latest JSON"; exists = $true; path = Join-Path $tempOutput "physical-proof-runbook-latest.json"; bytes = 100 },
      [pscustomobject]@{ name = "physical proof runbook latest Markdown"; exists = $true; path = Join-Path $tempOutput "physical-proof-runbook-latest.md"; bytes = 100 },
      [pscustomobject]@{ name = "physical proof runbook timestamped JSON"; exists = $true; path = Join-Path $tempOutput "physical-proof-runbook-20260101-000000.json"; bytes = 100 },
      [pscustomobject]@{ name = "physical proof runbook timestamped Markdown"; exists = $true; path = Join-Path $tempOutput "physical-proof-runbook-20260101-000000.md"; bytes = 100 },
      [pscustomobject]@{ name = "QA report latest JSON"; exists = $true; path = Join-Path $tempOutput "qa-report-latest.json"; bytes = 100 },
      [pscustomobject]@{ name = "QA report latest Markdown"; exists = $true; path = Join-Path $tempOutput "qa-report-latest.md"; bytes = 100 },
      [pscustomobject]@{ name = "QA report timestamped JSON"; exists = $true; path = Join-Path $tempOutput "qa-report-20260101-000000.json"; bytes = 100 },
      [pscustomObject]@{ name = "QA report timestamped Markdown"; exists = $true; path = Join-Path $tempOutput "qa-report-20260101-000000.md"; bytes = 100 },
      [pscustomobject]@{ name = "dependency audit latest JSON"; exists = $true; path = Join-Path $tempOutput "dependency-audit-latest.json"; bytes = 100 },
      [pscustomobject]@{ name = "dependency audit latest Markdown"; exists = $true; path = Join-Path $tempOutput "dependency-audit-latest.md"; bytes = 100 },
      [pscustomobject]@{ name = "dependency audit timestamped JSON"; exists = $true; path = Join-Path $tempOutput "dependency-audit-20260101-000000.json"; bytes = 100 },
      [pscustomobject]@{ name = "dependency audit timestamped Markdown"; exists = $true; path = Join-Path $tempOutput "dependency-audit-20260101-000000.md"; bytes = 100 },
      [pscustomobject]@{ name = "completion audit latest JSON"; exists = $true; path = Join-Path $tempOutput "completion-audit-latest.json"; bytes = 100 },
      [pscustomobject]@{ name = "completion audit timestamped JSON"; exists = $true; path = Join-Path $tempOutput "completion-audit-20260101-000000.json"; bytes = 100 },
      [pscustomobject]@{ name = "physical finalization latest JSON"; exists = $true; path = Join-Path $tempOutput "physical-evidence-finalization-latest.json"; bytes = 100 },
      [pscustomobject]@{ name = "physical finalization latest Markdown"; exists = $true; path = Join-Path $tempOutput "physical-evidence-finalization-latest.md"; bytes = 100 },
      [pscustomobject]@{ name = "physical finalization timestamped JSON"; exists = $true; path = Join-Path $tempOutput "physical-evidence-finalization-20260101-000000.json"; bytes = 100 },
      [pscustomobject]@{ name = "physical finalization timestamped Markdown"; exists = $true; path = Join-Path $tempOutput "physical-evidence-finalization-20260101-000000.md"; bytes = 100 },
      [pscustomobject]@{ name = "active finalization manual DOCX"; exists = $true; path = Join-Path $Root "docs\Remote_Controller_Finalization_Plan.docx"; bytes = 100 },
      [pscustomobject]@{ name = "active finalization traceability Markdown"; exists = $true; path = Join-Path $Root "docs\FINALIZATION_TRACEABILITY.md"; bytes = 100 },
      [pscustomobject]@{ name = "legacy build manual traceability Markdown"; exists = $true; path = Join-Path $Root "docs\TRACEABILITY_AUDIT.md"; bytes = 100 },
      [pscustomobject]@{ name = "firewall handoff latest JSON"; exists = $true; path = Join-Path $tempOutput "firewall-handoff-install-latest.json"; bytes = 100 },
      [pscustomobject]@{ name = "firewall handoff latest Markdown"; exists = $true; path = Join-Path $tempOutput "firewall-handoff-install-latest.md"; bytes = 100 },
      [pscustomobject]@{ name = "firewall handoff latest script"; exists = $true; path = Join-Path $tempOutput "firewall-handoff-install-latest.ps1"; bytes = 100 },
      [pscustomobject]@{ name = "firewall handoff timestamped JSON"; exists = $true; path = Join-Path $tempOutput "firewall-handoff-install-20260101-000000.json"; bytes = 100 },
      [pscustomobject]@{ name = "firewall handoff timestamped Markdown"; exists = $true; path = Join-Path $tempOutput "firewall-handoff-install-20260101-000000.md"; bytes = 100 },
      [pscustomobject]@{ name = "firewall handoff timestamped script"; exists = $true; path = Join-Path $tempOutput "firewall-handoff-install-20260101-000000.ps1"; bytes = 100 },
      [pscustomobject]@{ name = "same-Wi-Fi physical proof launch latest JSON"; exists = $true; path = Join-Path $tempOutput "physical-proof-launch-same-wifi-latest.json"; bytes = 100 },
      [pscustomobject]@{ name = "same-Wi-Fi physical proof launch latest Markdown"; exists = $true; path = Join-Path $tempOutput "physical-proof-launch-same-wifi-latest.md"; bytes = 100 },
      [pscustomobject]@{ name = "same-Wi-Fi physical proof launch timestamped JSON"; exists = $true; path = Join-Path $tempOutput "physical-proof-launch-same-wifi-20260101-000000.json"; bytes = 100 },
      [pscustomobject]@{ name = "same-Wi-Fi physical proof launch timestamped Markdown"; exists = $true; path = Join-Path $tempOutput "physical-proof-launch-same-wifi-20260101-000000.md"; bytes = 100 },
      [pscustomobject]@{ name = "Tailscale physical proof launch latest JSON"; exists = $true; path = Join-Path $tempOutput "physical-proof-launch-tailscale-latest.json"; bytes = 100 },
      [pscustomobject]@{ name = "Tailscale physical proof launch latest Markdown"; exists = $true; path = Join-Path $tempOutput "physical-proof-launch-tailscale-latest.md"; bytes = 100 },
      [pscustomobject]@{ name = "Tailscale physical proof launch timestamped JSON"; exists = $true; path = Join-Path $tempOutput "physical-proof-launch-tailscale-20260101-000000.json"; bytes = 100 },
      [pscustomobject]@{ name = "Tailscale physical proof launch timestamped Markdown"; exists = $true; path = Join-Path $tempOutput "physical-proof-launch-tailscale-20260101-000000.md"; bytes = 100 }
    )
    bundleMarkdownPath = Join-Path $tempOutput "remote-controller-evidence-bundle-20260101-000001.md"
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempOutput "remote-controller-evidence-bundle-latest.json") -Encoding UTF8
  [pscustomobject]@{
    ok = $true
    completionReady = $false
    onlyPhysicalAuditFailures = $true
    artifacts = @(
      [pscustomobject]@{ name = "acceptance handoff HTML"; exists = $true },
      [pscustomobject]@{ name = "acceptance dashboard HTML"; exists = $true },
      [pscustomobject]@{ name = "Tailscale setup check Markdown"; exists = $true; path = Join-Path $tempOutput "tailscale-setup-check-20260101-000000.md" },
      [pscustomobject]@{ name = "Tailscale setup check JSON"; exists = $true; path = Join-Path $tempOutput "tailscale-setup-check-20260101-000000.json" },
      [pscustomobject]@{ name = "evidence bundle Markdown"; exists = $true; path = Join-Path $tempOutput "remote-controller-evidence-bundle-20260101-000001.md" },
      [pscustomobject]@{ name = "completion audit JSON"; exists = $true; path = Join-Path $tempOutput "completion-audit-20260101-000000.json" }
    )
    steps = @(
      [pscustomobject]@{ name = "Tailscale setup check"; allowedFailure = $true; primaryPath = Join-Path $tempOutput "tailscale-setup-check-20260101-000000.md" },
      [pscustomobject]@{ name = "Post-audit evidence bundle"; allowedFailure = $true; primaryPath = Join-Path $tempOutput "remote-controller-evidence-bundle-20260101-000001.md" }
    )
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-refresh-latest.json") -Encoding UTF8
  [pscustomobject]@{ ok = $true } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-verification-same-wifi-latest.json") -Encoding UTF8
  [pscustomobject]@{ ok = $true } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-verification-tailscale-latest.json") -Encoding UTF8
  [pscustomobject]@{
    ok = $true
    tailscale = [pscustomobject]@{
      statusSnapshot = [pscustomobject]@{ backendState = "NeedsLogin"; authUrl = "https://login.tailscale.com/a/selftest"; hasTailnetIp = $false }
      ipv4 = @()
      ipv6 = @()
    }
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempOutput "tailscale-bootstrap-latest.json") -Encoding UTF8
  [pscustomobject]@{
    ok = $false
    reportJsonPath = Join-Path $tempOutput "tailscale-setup-check-20260101-000000.json"
    reportMarkdownPath = Join-Path $tempOutput "tailscale-setup-check-20260101-000000.md"
    latestReportJsonPath = Join-Path $tempOutput "tailscale-setup-check-latest.json"
    latestReportMarkdownPath = Join-Path $tempOutput "tailscale-setup-check-latest.md"
    tailscale = [pscustomobject]@{
      statusSnapshot = [pscustomobject]@{ backendState = "NeedsLogin"; authUrl = "https://login.tailscale.com/a/selftest"; hasTailnetIp = $false }
      ipv4 = @()
      ipv6 = @()
    }
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempOutput "tailscale-setup-check-latest.json") -Encoding UTF8
  "If the phone cannot connect, run npm run firewall:handoff first, then run the copied elevated install command only if you choose to allow inbound TCP 4317." | Set-Content -LiteralPath (Join-Path $tempOutput "tailscale-setup-check-latest.md") -Encoding UTF8
  [pscustomobject]@{ ok = $false; generatedAt = $fixtureQaGeneratedAt } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $tempOutput "physical-evidence-finalization-latest.json") -Encoding UTF8
  [pscustomobject]@{ ok = $false; generatedAt = $fixtureQaGeneratedAt } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $tempOutput "physical-evidence-finalization-20260101-000000.json") -Encoding UTF8
  "# Physical Evidence Finalization" | Set-Content -LiteralPath (Join-Path $tempOutput "physical-evidence-finalization-20260101-000000.md") -Encoding UTF8
  [pscustomobject]@{
    ok = $true
    status = "reviewed-known-risk"
    total = 7
    moderate = 7
    highCritical = 0
    direct = 1
    policy = "Fail on high/critical advisories."
  } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $tempOutput "dependency-audit-latest.json") -Encoding UTF8
  "# Dependency Audit`n`nStatus: reviewed-known-risk`nHigh/Critical advisories: 0" | Set-Content -LiteralPath (Join-Path $tempOutput "dependency-audit-latest.md") -Encoding UTF8
  [pscustomobject]@{
    ok = $true
    generatedAt = $fixtureQaGeneratedAt
    reportJsonPath = Join-Path $tempOutput "qa-report-20260101-000000.json"
    reportMarkdownPath = Join-Path $tempOutput "qa-report-20260101-000000.md"
    latestReportJsonPath = Join-Path $tempOutput "qa-report-latest.json"
    latestReportMarkdownPath = Join-Path $tempOutput "qa-report-latest.md"
    host = [pscustomobject]@{ mode = "milestone-2-screen-capture"; reachable = $true }
    nodeTests = [pscustomobject]@{
      exitCode = 0
      summary = [pscustomobject]@{ tests = 37; pass = 37; fail = 0; durationMs = 1000 }
    }
    selfTests = @(
      [pscustomobject]@{ name = "tray host"; script = "scripts\tray-host.ps1"; ok = $true },
      [pscustomobject]@{ name = "acceptance report"; script = "scripts\acceptance-report.ps1"; ok = $true },
      [pscustomobject]@{ name = "manual phone acceptance"; script = "scripts\manual-phone-acceptance.ps1"; ok = $true },
      [pscustomobject]@{ name = "acceptance doctor"; script = "scripts\acceptance-doctor.ps1"; ok = $true },
      [pscustomobject]@{ name = "prepare phone acceptance"; script = "scripts\prepare-phone-acceptance.ps1"; ok = $true },
      [pscustomobject]@{ name = "acceptance ready"; script = "scripts\acceptance-ready.ps1"; ok = $true },
      [pscustomobject]@{ name = "acceptance next"; script = "scripts\acceptance-next.ps1"; ok = $true },
      [pscustomobject]@{ name = "physical proof runbook"; script = "scripts\physical-proof-runbook.ps1"; ok = $true },
      [pscustomobject]@{ name = "physical proof launch"; script = "scripts\physical-proof-launch.ps1"; ok = $true },
      [pscustomobject]@{ name = "acceptance dashboard"; script = "scripts\acceptance-dashboard.ps1"; ok = $true },
      [pscustomobject]@{ name = "acceptance handoff"; script = "scripts\acceptance-handoff.ps1"; ok = $true },
      [pscustomobject]@{ name = "acceptance refresh"; script = "scripts\acceptance-refresh.ps1"; ok = $true },
      [pscustomobject]@{ name = "physical evidence finalization"; script = "scripts\finalize-physical-evidence.ps1"; ok = $true },
      [pscustomobject]@{ name = "attach phone evidence"; script = "scripts\attach-phone-evidence.ps1"; ok = $true },
      [pscustomobject]@{ name = "stop phone acceptance"; script = "scripts\stop-phone-acceptance.ps1"; ok = $true },
      [pscustomobject]@{ name = "verify phone acceptance"; script = "scripts\verify-phone-acceptance.ps1"; ok = $true },
      [pscustomobject]@{ name = "watch phone acceptance"; script = "scripts\watch-phone-acceptance.ps1"; ok = $true },
      [pscustomobject]@{ name = "tailscale setup check"; script = "scripts\tailscale-setup-check.ps1"; ok = $true },
      [pscustomobject]@{ name = "tailscale bootstrap"; script = "scripts\tailscale-bootstrap.ps1"; ok = $true },
      [pscustomobject]@{ name = "firewall rule"; script = "scripts\firewall-rule.ps1"; ok = $true },
      [pscustomobject]@{ name = "firewall handoff"; script = "scripts\firewall-handoff.ps1"; ok = $true },
      [pscustomobject]@{ name = "desktop shortcut"; script = "scripts\install-shortcut.ps1"; ok = $true },
      [pscustomobject]@{ name = "install autostart"; script = "scripts\install-autostart.ps1"; ok = $true },
      [pscustomobject]@{ name = "uninstall autostart"; script = "scripts\uninstall-autostart.ps1"; ok = $true },
      [pscustomobject]@{ name = "dependency audit"; script = "scripts\dependency-audit.ps1"; ok = $true },
      [pscustomobject]@{ name = "completion audit"; script = "scripts\completion-audit.ps1"; ok = $true },
      [pscustomobject]@{ name = "evidence bundle"; script = "scripts\evidence-bundle.ps1"; ok = $true }
    )
    artifacts = @(
      [pscustomobject]@{ name = "acceptance dashboard latest HTML"; relativePath = "phone-acceptance-dashboard-latest.html"; exists = $true; bytes = 100; lastWriteTime = (Get-Date).ToString("o") },
      [pscustomobject]@{ name = "acceptance handoff latest HTML"; relativePath = "phone-acceptance-handoff-latest.html"; exists = $true; bytes = 100; lastWriteTime = (Get-Date).ToString("o") },
      [pscustomobject]@{ name = "physical proof runbook latest JSON"; relativePath = "physical-proof-runbook-latest.json"; exists = $true; bytes = 100; lastWriteTime = (Get-Date).ToString("o") },
      [pscustomobject]@{ name = "same-Wi-Fi physical proof launch latest Markdown"; relativePath = "physical-proof-launch-same-wifi-latest.md"; exists = $true; bytes = 100; lastWriteTime = (Get-Date).ToString("o") },
      [pscustomobject]@{ name = "same-Wi-Fi physical proof launch latest JSON"; relativePath = "physical-proof-launch-same-wifi-latest.json"; exists = $true; bytes = 100; lastWriteTime = (Get-Date).ToString("o") },
      [pscustomobject]@{ name = "Tailscale physical proof launch latest Markdown"; relativePath = "physical-proof-launch-tailscale-latest.md"; exists = $true; bytes = 100; lastWriteTime = (Get-Date).ToString("o") },
      [pscustomobject]@{ name = "Tailscale physical proof launch latest JSON"; relativePath = "physical-proof-launch-tailscale-latest.json"; exists = $true; bytes = 100; lastWriteTime = (Get-Date).ToString("o") },
      [pscustomobject]@{ name = "evidence bundle latest JSON"; relativePath = "remote-controller-evidence-bundle-latest.json"; exists = $true; bytes = 100; lastWriteTime = (Get-Date).ToString("o") },
      [pscustomobject]@{ name = "active finalization manual DOCX"; relativePath = "docs\Remote_Controller_Finalization_Plan.docx"; exists = $true; bytes = 100; lastWriteTime = (Get-Date).ToString("o") },
      [pscustomobject]@{ name = "active finalization traceability Markdown"; relativePath = "docs\FINALIZATION_TRACEABILITY.md"; exists = $true; bytes = 100; lastWriteTime = (Get-Date).ToString("o") },
      [pscustomobject]@{ name = "legacy build manual traceability Markdown"; relativePath = "docs\TRACEABILITY_AUDIT.md"; exists = $true; bytes = 100; lastWriteTime = (Get-Date).ToString("o") },
      [pscustomobject]@{ name = "acceptance refresh latest JSON"; relativePath = "phone-acceptance-refresh-latest.json"; exists = $true; bytes = 100; lastWriteTime = (Get-Date).ToString("o") },
      [pscustomobject]@{ name = "physical finalization latest JSON"; relativePath = "physical-evidence-finalization-latest.json"; exists = $true; bytes = 100; lastWriteTime = (Get-Date).ToString("o") },
      [pscustomobject]@{ name = "completion audit latest JSON"; relativePath = "completion-audit-latest.json"; exists = $true; bytes = 100; lastWriteTime = (Get-Date).ToString("o") }
    )
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempOutput "qa-report-latest.json") -Encoding UTF8
  $result = Invoke-CompletionAudit -SelectedOutputDir $tempOutput
  $saved = Save-CompletionAudit -Audit $result -SelectedOutputDir $tempOutput
  $expectedMissingPhysicalEvidence = (-not $result.ok) -and (-not $result.gates.sameWifi) -and (-not $result.gates.tailscale)
  $allowedFreshCloneFailures = @(
    "DOC-001",
    "DOC-002",
    "DOC-007",
    "CONTENT-053",
    "CONTENT-056",
    "CONTENT-057",
    "PHYSICAL-001",
    "PHYSICAL-002",
    "PHYSICAL-003"
  )
  $unexpectedFailures = @($result.failedIds | Where-Object { $_ -notin $allowedFreshCloneFailures })
  $expectedPhysicalFailuresPresent = @("PHYSICAL-001", "PHYSICAL-002", "PHYSICAL-003") |
    Where-Object { $result.failedIds -contains $_ } |
    Measure-Object |
    Select-Object -ExpandProperty Count
  $expectedFreshCloneBlockers = $expectedPhysicalFailuresPresent -eq 3 -and $unexpectedFailures.Count -eq 0
  [pscustomobject]@{
    ok = $expectedMissingPhysicalEvidence -and $expectedFreshCloneBlockers -and (Test-Path -LiteralPath $saved.auditJsonPath) -and (Test-Path -LiteralPath $saved.auditMarkdownPath)
    expectedStatus = "not-complete"
    actualStatus = $result.status
    requirementCount = $result.requirementCount
    failedCount = $result.failedCount
    failedIds = @($result.failedIds)
    allowedFreshCloneFailures = @($allowedFreshCloneFailures)
    unexpectedFailures = @($unexpectedFailures)
    sameWifi = $result.gates.sameWifi
    tailscale = $result.gates.tailscale
    writesSavedAudit = (Test-Path -LiteralPath $saved.auditJsonPath) -and (Test-Path -LiteralPath $saved.auditMarkdownPath)
  } | ConvertTo-Json -Compress
  if (-not ($expectedMissingPhysicalEvidence -and $expectedFreshCloneBlockers -and (Test-Path -LiteralPath $saved.auditJsonPath) -and (Test-Path -LiteralPath $saved.auditMarkdownPath))) { exit 1 }
  exit 0
}

$audit = Invoke-CompletionAudit -SelectedOutputDir $OutputDir
if ($Save) {
  $audit = Save-CompletionAudit -Audit $audit -SelectedOutputDir $OutputDir
}
$audit | ConvertTo-Json -Depth 8 -Compress
if (-not $audit.ok) { exit 1 }


















