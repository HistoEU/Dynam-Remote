param(
  [string]$OutputDir = "output\acceptance",
  [switch]$NoOpen,
  [switch]$OpenDashboard,
  [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$ResolvedOutputDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $Root $OutputDir }

function ConvertTo-StringArray {
  param([object]$Values)
  if ($null -eq $Values) { return @() }
  return @($Values | Where-Object { $null -ne $_ } | ForEach-Object { "$_" })
}

function ConvertTo-StringList {
  param([object]$Values)
  $list = [System.Collections.Generic.List[string]]::new()
  foreach ($value in @(ConvertTo-StringArray $Values)) {
    $list.Add("$value") | Out-Null
  }
  return ,$list
}

function ConvertTo-StepSummary {
  param([object]$Step)
  $parsed = $Step.parsed
  $parsedOk = $null
  $status = ""
  $primaryPath = ""
  if ($parsed) {
    if ($parsed.PSObject.Properties.Name -contains "ok") { $parsedOk = $parsed.ok }
    if ($parsed.PSObject.Properties.Name -contains "status") { $status = "$($parsed.status)" }
    foreach ($pathName in @(
    "readyStatusPath",
    "reportMarkdownPath",
    "handoffHtmlPath",
    "nextMarkdownPath",
    "runbookMarkdownPath",
    "launchMarkdownPath",
    "dashboardHtmlPath",
    "bundleMarkdownPath",
    "auditMarkdownPath",
    "refreshMarkdownPath"
    )) {
      if (($parsed.PSObject.Properties.Name -contains $pathName) -and $parsed.$pathName) {
        $primaryPath = "$($parsed.$pathName)"
        break
      }
    }
  }

  return [pscustomobject]@{
    name = "$($Step.name)"
    command = "$($Step.command)"
    ok = [bool]$Step.ok
    exitCode = [int]$Step.exitCode
    allowedFailure = [bool]$Step.allowedFailure
    parsedOk = $parsedOk
    status = $status
    primaryPath = $primaryPath
  }
}

function Invoke-JsonScript {
  param(
    [string]$Name,
    [string]$ScriptName,
    [string[]]$Arguments = @(),
    [switch]$AllowFailure,
    [int]$TimeoutSeconds = 90
  )

  $scriptPath = Join-Path $PSScriptRoot $ScriptName
  if (-not (Test-Path -LiteralPath $scriptPath)) {
    return [pscustomobject]@{
      name = $Name
      command = "powershell -NoProfile -ExecutionPolicy Bypass -File scripts\$ScriptName $($Arguments -join ' ')".Trim()
      ok = $false
      exitCode = -1
      allowedFailure = [bool]$AllowFailure
      parsed = $null
      raw = @("Missing script: $scriptPath")
    }
  }

  $tempPrefix = Join-Path ([System.IO.Path]::GetTempPath()) "remote-acceptance-refresh-$([guid]::NewGuid().ToString('N'))"
  $stdoutPath = "$tempPrefix.out"
  $stderrPath = "$tempPrefix.err"
  $argumentList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath) + @($Arguments)
  $process = Start-Process -FilePath "powershell" -ArgumentList $argumentList -WorkingDirectory $Root -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -NoNewWindow -PassThru
  $exited = $process.WaitForExit([Math]::Max(1, $TimeoutSeconds) * 1000)
  $process.Refresh()
  if (-not $exited) {
    $children = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.ParentProcessId -eq $process.Id })
    foreach ($child in $children) {
      Stop-Process -Id $child.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    $process.WaitForExit(5000) | Out-Null
  }
  $raw = @()
  if (Test-Path -LiteralPath $stdoutPath) {
    $raw += @(Get-Content -LiteralPath $stdoutPath -ErrorAction SilentlyContinue)
  }
  if (Test-Path -LiteralPath $stderrPath) {
    $raw += @(Get-Content -LiteralPath $stderrPath -ErrorAction SilentlyContinue)
  }
  Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue

  $jsonLine = @($raw | Where-Object { "$_".Trim().StartsWith("{") }) | Select-Object -Last 1
  $parsed = $null
  if ($jsonLine) {
    try {
      $parsed = $jsonLine | ConvertFrom-Json
    } catch {
      $parsed = $null
    }
  }

  if (-not $exited) {
    $raw += "Timed out after $TimeoutSeconds seconds."
  }
  $exitCode = if (-not $exited) {
    124
  } elseif ($null -ne $process.ExitCode) {
    $process.ExitCode
  } elseif ($parsed -and $parsed.PSObject.Properties.Name -contains "ok" -and $parsed.ok -eq $true) {
    0
  } else {
    1
  }

  return [pscustomobject]@{
    name = $Name
    command = "powershell -NoProfile -ExecutionPolicy Bypass -File scripts\$ScriptName $($Arguments -join ' ')".Trim()
    ok = $exitCode -eq 0
    exitCode = $exitCode
    allowedFailure = [bool]$AllowFailure
    parsed = $parsed
    raw = @($raw | ForEach-Object { "$_" })
  }
}

function Test-OnlyPhysicalAuditFailures {
  param([object]$Audit)
  if (-not $Audit -or -not $Audit.failedIds) { return $false }
  $failed = @(ConvertTo-StringArray $Audit.failedIds | Sort-Object)
  $expected = @("PHYSICAL-001", "PHYSICAL-002", "PHYSICAL-003")
  return ($failed.Count -eq $expected.Count) -and (@(Compare-Object -ReferenceObject $expected -DifferenceObject $failed).Count -eq 0)
}

function Test-ExpectedRefreshAuditFailures {
  param([object]$Audit)
  if (Test-OnlyPhysicalAuditFailures -Audit $Audit) { return $true }
  if (-not $Audit -or -not $Audit.failedIds) { return $false }
  $failed = @(ConvertTo-StringArray $Audit.failedIds | Sort-Object)
  $expected = @("CONTENT-007", "PHYSICAL-001", "PHYSICAL-002", "PHYSICAL-003")
  return ($failed.Count -eq $expected.Count) -and (@(Compare-Object -ReferenceObject $expected -DifferenceObject $failed).Count -eq 0)
}

function Get-FailedRequirementRows {
  param([object]$Audit)
  if (-not $Audit -or -not $Audit.requirements) { return @() }
  return @($Audit.requirements | Where-Object { $_.passed -eq $false } | ForEach-Object {
    [pscustomobject]@{
      id = "$($_.id)"
      requirement = "$($_.requirement)"
      detail = "$($_.detail)"
    }
  })
}

function New-ArtifactLinkRecord {
  param(
    [string]$Name,
    [string]$PathValue
  )
  return [pscustomobject]@{
    name = $Name
    path = "$PathValue"
    exists = -not [string]::IsNullOrWhiteSpace($PathValue) -and (Test-Path -LiteralPath $PathValue)
  }
}

function Write-RefreshMarkdown {
  param(
    [object]$Report,
    [string]$Path
  )

  $stepRows = @($Report.steps | ForEach-Object {
    $allowed = if ($_.allowedFailure) { "yes" } else { "no" }
    "| $($_.ok) | $($_.exitCode) | $allowed | $($_.name) | ``$($_.command)`` |"
  })
  if ($stepRows.Count -eq 0) { $stepRows = @("| none | none | none | none | none |") }

  $artifactRows = @($Report.artifacts | ForEach-Object {
    "| $($_.exists) | $($_.name) | $($_.path) |"
  })
  if ($artifactRows.Count -eq 0) { $artifactRows = @("| none | none | none |") }

  $blockerRows = @($Report.failedRequirements | ForEach-Object {
    "- $($_.id): $($_.requirement) - $($_.detail)"
  })
  if ($blockerRows.Count -eq 0) { $blockerRows = @("- none") }

  $sameWifiRows = @(ConvertTo-StringArray $Report.sameWifiPhoneUrls | ForEach-Object { "- $_" })
  if ($sameWifiRows.Count -eq 0) { $sameWifiRows = @("- none") }
  $tailscaleRows = @(ConvertTo-StringArray $Report.tailscalePhoneUrls | ForEach-Object { "- $_" })
  if ($tailscaleRows.Count -eq 0) { $tailscaleRows = @("- none") }

  $markdown = @"
# Physical Acceptance Refresh

Generated: $($Report.generatedAt)
Refresh OK: $($Report.ok)
Completion ready: $($Report.completionReady)
Expected physical-only blockers: $($Report.onlyPhysicalAuditFailures)

This report refreshes acceptance artifacts. It does not replace real same-Wi-Fi or Tailscale phone evidence, and it does not mark the build complete.

## Same-Wi-Fi Phone URLs

$($sameWifiRows -join [Environment]::NewLine)

## Tailscale Phone URLs

$($tailscaleRows -join [Environment]::NewLine)

## Refreshed Artifacts

| Exists | Name | Path |
| --- | --- | --- |
$($artifactRows -join [Environment]::NewLine)

## Step Results

| OK | Exit | Allowed Failure | Step | Command |
| --- | --- | --- | --- | --- |
$($stepRows -join [Environment]::NewLine)

## Remaining Completion Blockers

$($blockerRows -join [Environment]::NewLine)

## Physical Run Commands

~~~powershell
npm run acceptance:phone -- -Gate same-wifi -SkipStart -RequireReady
npm run acceptance:verify:save -- -Gate same-wifi
npm run acceptance:phone -- -Gate tailscale -SkipStart -RequireReady
npm run acceptance:verify:save -- -Gate tailscale
npm run evidence:bundle
npm run completion:audit:save
~~~
"@

  $markdown | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Save-RefreshReport {
  param([object]$Report)

  New-Item -ItemType Directory -Path $ResolvedOutputDir -Force | Out-Null
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $jsonPath = Join-Path $ResolvedOutputDir "phone-acceptance-refresh-$timestamp.json"
  $mdPath = Join-Path $ResolvedOutputDir "phone-acceptance-refresh-$timestamp.md"
  $latestJsonPath = Join-Path $ResolvedOutputDir "phone-acceptance-refresh-latest.json"
  $latestMdPath = Join-Path $ResolvedOutputDir "phone-acceptance-refresh-latest.md"
  $Report | Add-Member -NotePropertyName refreshJsonPath -NotePropertyValue $jsonPath -Force
  $Report | Add-Member -NotePropertyName refreshMarkdownPath -NotePropertyValue $mdPath -Force
  $Report | Add-Member -NotePropertyName latestRefreshJsonPath -NotePropertyValue $latestJsonPath -Force
  $Report | Add-Member -NotePropertyName latestRefreshMarkdownPath -NotePropertyValue $latestMdPath -Force
  $Report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  $Report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $latestJsonPath -Encoding UTF8
  Write-RefreshMarkdown -Report $Report -Path $mdPath
  Write-RefreshMarkdown -Report $Report -Path $latestMdPath
  return $Report
}

function New-RefreshReport {
  $steps = [System.Collections.Generic.List[object]]::new()

  $tailscaleBootstrap = Invoke-JsonScript -Name "Tailscale bootstrap report" -ScriptName "tailscale-bootstrap.ps1" -Arguments @("-Save", "-OutputDir", $OutputDir)
  $steps.Add($tailscaleBootstrap) | Out-Null
  if (-not $tailscaleBootstrap.ok) { throw "Tailscale bootstrap refresh failed." }

  $tailscaleSetupCheck = Invoke-JsonScript -Name "Tailscale setup check" -ScriptName "tailscale-setup-check.ps1" -Arguments @("-Save", "-OutputDir", $OutputDir) -AllowFailure
  $steps.Add($tailscaleSetupCheck) | Out-Null

  $sameWifiReadyArgs = @("-Gate", "same-wifi", "-OutputDir", $OutputDir)
  if ($NoOpen) { $sameWifiReadyArgs += "-NoOpen" }
  $sameWifiReady = Invoke-JsonScript -Name "Same-Wi-Fi readiness" -ScriptName "acceptance-ready.ps1" -Arguments $sameWifiReadyArgs
  $steps.Add($sameWifiReady) | Out-Null
  if (-not $sameWifiReady.ok) { throw "Same-Wi-Fi readiness refresh failed." }

  $tailscaleReadyArgs = @("-Gate", "tailscale", "-OutputDir", $OutputDir)
  if ($NoOpen) { $tailscaleReadyArgs += "-NoOpen" }
  $tailscaleReady = Invoke-JsonScript -Name "Tailscale readiness" -ScriptName "acceptance-ready.ps1" -Arguments $tailscaleReadyArgs -AllowFailure
  $steps.Add($tailscaleReady) | Out-Null

  $tailscaleSetupRecheck = Invoke-JsonScript -Name "Tailscale setup recheck after readiness" -ScriptName "tailscale-setup-check.ps1" -Arguments @("-Save", "-OutputDir", $OutputDir) -AllowFailure
  $steps.Add($tailscaleSetupRecheck) | Out-Null

  $next = Invoke-JsonScript -Name "Next-action checklist" -ScriptName "acceptance-next.ps1" -Arguments @("-OutputDir", $OutputDir)
  $steps.Add($next) | Out-Null
  if (-not $next.ok) { throw "Next-action checklist refresh failed." }

  $preRunbookAudit = Invoke-JsonScript -Name "Pre-runbook completion audit" -ScriptName "completion-audit.ps1" -Arguments @("-OutputDir", $OutputDir, "-Save") -AllowFailure
  $steps.Add($preRunbookAudit) | Out-Null

  $runbook = Invoke-JsonScript -Name "Physical proof runbook" -ScriptName "physical-proof-runbook.ps1" -Arguments @("-OutputDir", $OutputDir)
  $steps.Add($runbook) | Out-Null
  if (-not $runbook.ok) { throw "Physical proof runbook refresh failed." }

  $sameWifiLaunch = Invoke-JsonScript -Name "Same-Wi-Fi physical proof launch card" -ScriptName "physical-proof-launch.ps1" -Arguments @("-Gate", "same-wifi", "-OutputDir", $OutputDir, "-NoOpen", "-NoClipboard")
  $steps.Add($sameWifiLaunch) | Out-Null
  if (-not $sameWifiLaunch.ok) { throw "Same-Wi-Fi physical proof launch refresh failed." }

  $tailscaleLaunch = Invoke-JsonScript -Name "Tailscale physical proof launch card" -ScriptName "physical-proof-launch.ps1" -Arguments @("-Gate", "tailscale", "-OutputDir", $OutputDir, "-NoOpen", "-NoClipboard")
  $steps.Add($tailscaleLaunch) | Out-Null
  if (-not $tailscaleLaunch.ok) { throw "Tailscale physical proof launch refresh failed." }

  $initialBundle = Invoke-JsonScript -Name "Evidence bundle for dashboard and handoff" -ScriptName "evidence-bundle.ps1" -Arguments @("-OutputDir", $OutputDir) -AllowFailure
  $steps.Add($initialBundle) | Out-Null

  $dashboardArgs = @("-OutputDir", $OutputDir)
  if ($OpenDashboard) { $dashboardArgs += "-Open" }
  $dashboard = Invoke-JsonScript -Name "Acceptance dashboard" -ScriptName "acceptance-dashboard.ps1" -Arguments $dashboardArgs
  $steps.Add($dashboard) | Out-Null
  if (-not $dashboard.ok) { throw "Acceptance dashboard refresh failed." }

  $handoffArgs = @("-OutputDir", $OutputDir)
  if ($OpenDashboard) { $handoffArgs += "-Open" }
  $handoff = Invoke-JsonScript -Name "Acceptance handoff" -ScriptName "acceptance-handoff.ps1" -Arguments $handoffArgs
  $steps.Add($handoff) | Out-Null
  if (-not $handoff.ok) { throw "Acceptance handoff refresh failed." }

  $finalBundle = Invoke-JsonScript -Name "Final evidence bundle after handoff" -ScriptName "evidence-bundle.ps1" -Arguments @("-OutputDir", $OutputDir) -AllowFailure
  $steps.Add($finalBundle) | Out-Null

  $dependencyAudit = Invoke-JsonScript -Name "Dependency audit" -ScriptName "dependency-audit.ps1" -Arguments @("-OutputDir", $OutputDir, "-Save")
  $steps.Add($dependencyAudit) | Out-Null
  if (-not $dependencyAudit.ok) { throw "Dependency audit refresh failed." }

  $audit = Invoke-JsonScript -Name "Completion audit" -ScriptName "completion-audit.ps1" -Arguments @("-OutputDir", $OutputDir, "-Save") -AllowFailure
  $steps.Add($audit) | Out-Null

  $postAuditBundle = Invoke-JsonScript -Name "Post-audit evidence bundle" -ScriptName "evidence-bundle.ps1" -Arguments @("-OutputDir", $OutputDir) -AllowFailure
  $steps.Add($postAuditBundle) | Out-Null

  $auditParsed = $audit.parsed
  $onlyPhysicalAuditFailures = Test-OnlyPhysicalAuditFailures -Audit $auditParsed
  $expectedInitialBundleFailure = $initialBundle.parsed -and $initialBundle.parsed.ok -eq $false -and $onlyPhysicalAuditFailures
  $expectedFinalBundleFailure = $finalBundle.parsed -and $finalBundle.parsed.ok -eq $false -and $onlyPhysicalAuditFailures
  $expectedPostAuditBundleFailure = $postAuditBundle.parsed -and $postAuditBundle.parsed.ok -eq $false -and $onlyPhysicalAuditFailures
  $ok = @($steps | Where-Object { -not $_.ok -and -not $_.allowedFailure }).Count -eq 0
  $ok = $ok -and ($audit.ok -or $onlyPhysicalAuditFailures) -and ($initialBundle.ok -or $expectedInitialBundleFailure) -and ($finalBundle.ok -or $expectedFinalBundleFailure) -and ($postAuditBundle.ok -or $expectedPostAuditBundleFailure)

  $sameReady = $sameWifiReady.parsed
  $tailReady = $tailscaleReady.parsed
  $dash = $dashboard.parsed
  $handoffParsed = $handoff.parsed
  $nextParsed = $next.parsed
  $runbookParsed = $runbook.parsed
  $sameWifiLaunchParsed = $sameWifiLaunch.parsed
  $tailscaleLaunchParsed = $tailscaleLaunch.parsed
  $dependencyAuditParsed = $dependencyAudit.parsed
  $tailscaleSetupCheckForReport = if ($tailscaleSetupRecheck.parsed) { $tailscaleSetupRecheck } else { $tailscaleSetupCheck }
  $tailscaleSetupCheckParsed = $tailscaleSetupCheckForReport.parsed
  $bundleForReport = if ($postAuditBundle.parsed) { $postAuditBundle } elseif ($finalBundle.parsed) { $finalBundle } else { $initialBundle }
  $bundleParsed = $bundleForReport.parsed

  $artifacts = @(
    New-ArtifactLinkRecord "same-Wi-Fi run card" $(if ($sameReady) { "$($sameReady.runCardHtml)" } else { "" })
    New-ArtifactLinkRecord "same-Wi-Fi ready JSON" $(if ($sameReady) { "$($sameReady.readyStatusPath)" } else { "" })
    New-ArtifactLinkRecord "Tailscale ready JSON" $(if ($tailReady) { "$($tailReady.readyStatusPath)" } else { "" })
    New-ArtifactLinkRecord "Tailscale bootstrap Markdown" $(if ($tailscaleBootstrap.parsed) { "$($tailscaleBootstrap.parsed.reportMarkdownPath)" } else { "" })
    New-ArtifactLinkRecord "Tailscale setup check Markdown" $(if ($tailscaleSetupCheckParsed) { "$($tailscaleSetupCheckParsed.reportMarkdownPath)" } else { "" })
    New-ArtifactLinkRecord "Tailscale setup check JSON" $(if ($tailscaleSetupCheckParsed) { "$($tailscaleSetupCheckParsed.reportJsonPath)" } else { "" })
    New-ArtifactLinkRecord "next-action Markdown" $(if ($nextParsed) { "$($nextParsed.nextMarkdownPath)" } else { "" })
    New-ArtifactLinkRecord "physical proof runbook Markdown" $(if ($runbookParsed) { "$($runbookParsed.runbookMarkdownPath)" } else { "" })
    New-ArtifactLinkRecord "same-Wi-Fi physical proof launch Markdown" $(if ($sameWifiLaunchParsed) { "$($sameWifiLaunchParsed.launchMarkdownPath)" } else { "" })
    New-ArtifactLinkRecord "Tailscale physical proof launch Markdown" $(if ($tailscaleLaunchParsed) { "$($tailscaleLaunchParsed.launchMarkdownPath)" } else { "" })
    New-ArtifactLinkRecord "acceptance dashboard HTML" $(if ($dash) { "$($dash.dashboardHtmlPath)" } else { "" })
    New-ArtifactLinkRecord "acceptance handoff HTML" $(if ($handoffParsed) { "$($handoffParsed.handoffHtmlPath)" } else { "" })
    New-ArtifactLinkRecord "evidence bundle Markdown" $(if ($bundleParsed) { "$($bundleParsed.bundleMarkdownPath)" } else { "" })
    New-ArtifactLinkRecord "dependency audit Markdown" $(if ($dependencyAuditParsed) { "$($dependencyAuditParsed.reportMarkdownPath)" } else { "" })
    New-ArtifactLinkRecord "dependency audit JSON" $(if ($dependencyAuditParsed) { "$($dependencyAuditParsed.reportJsonPath)" } else { "" })
    New-ArtifactLinkRecord "completion audit Markdown" $(if ($auditParsed) { "$($auditParsed.auditMarkdownPath)" } else { "" })
    New-ArtifactLinkRecord "completion audit JSON" $(if ($auditParsed) { "$($auditParsed.auditJsonPath)" } else { "" })
  )

  $report = [pscustomobject]@{
    ok = $ok
    generatedAt = (Get-Date).ToString("o")
    outputDir = "$ResolvedOutputDir"
    completionReady = $audit.ok -and $auditParsed -and $auditParsed.ok -eq $true
    onlyPhysicalAuditFailures = $onlyPhysicalAuditFailures
    sameWifiPhoneUrls = if ($sameReady) { ConvertTo-StringList $sameReady.phoneUrls } else { ConvertTo-StringList @() }
    tailscalePhoneUrls = if ($tailReady) { ConvertTo-StringList $tailReady.phoneUrls } else { ConvertTo-StringList @() }
    failedRequirements = @(Get-FailedRequirementRows -Audit $auditParsed)
    artifacts = @($artifacts)
    steps = @($steps | ForEach-Object { ConvertTo-StepSummary -Step $_ })
  }

  $savedReport = Save-RefreshReport -Report $report

  $finalAudit = Invoke-JsonScript -Name "Final completion audit after refresh save" -ScriptName "completion-audit.ps1" -Arguments @("-OutputDir", $OutputDir, "-Save") -AllowFailure
  $steps.Add($finalAudit) | Out-Null

  $finalPostRefreshBundle = Invoke-JsonScript -Name "Final evidence bundle after refresh save" -ScriptName "evidence-bundle.ps1" -Arguments @("-OutputDir", $OutputDir) -AllowFailure
  $steps.Add($finalPostRefreshBundle) | Out-Null

  $finalAuditParsed = $finalAudit.parsed
  $finalOnlyPhysicalAuditFailures = Test-OnlyPhysicalAuditFailures -Audit $finalAuditParsed
  $finalExpectedRefreshAuditFailures = Test-ExpectedRefreshAuditFailures -Audit $finalAuditParsed
  $finalExpectedBundleFailure = $finalPostRefreshBundle.parsed -and $finalPostRefreshBundle.parsed.ok -eq $false -and $finalExpectedRefreshAuditFailures
  $savedReport.ok = (@($steps | Where-Object { -not $_.ok -and -not $_.allowedFailure }).Count -eq 0) -and
    ($finalAudit.ok -or $finalExpectedRefreshAuditFailures) -and
    ($finalPostRefreshBundle.ok -or $finalExpectedBundleFailure)
  $savedReport.completionReady = $finalAudit.ok -and $finalAuditParsed -and $finalAuditParsed.ok -eq $true
  $savedReport.onlyPhysicalAuditFailures = $finalExpectedRefreshAuditFailures
  $savedReport.failedRequirements = @(Get-FailedRequirementRows -Audit $finalAuditParsed | Where-Object {
    $finalOnlyPhysicalAuditFailures -or "$($_.id)" -ne "CONTENT-007"
  })
  $savedReport.steps = @($steps | ForEach-Object { ConvertTo-StepSummary -Step $_ })

  foreach ($artifact in @($savedReport.artifacts)) {
    if ("$($artifact.name)" -eq "completion audit Markdown" -and $finalAuditParsed) {
      $artifact.path = "$($finalAuditParsed.auditMarkdownPath)"
      $artifact.exists = -not [string]::IsNullOrWhiteSpace("$($artifact.path)") -and (Test-Path -LiteralPath "$($artifact.path)")
    }
    if ("$($artifact.name)" -eq "completion audit JSON" -and $finalAuditParsed) {
      $artifact.path = "$($finalAuditParsed.auditJsonPath)"
      $artifact.exists = -not [string]::IsNullOrWhiteSpace("$($artifact.path)") -and (Test-Path -LiteralPath "$($artifact.path)")
    }
    if ("$($artifact.name)" -eq "evidence bundle Markdown" -and $finalPostRefreshBundle.parsed) {
      $artifact.path = "$($finalPostRefreshBundle.parsed.bundleMarkdownPath)"
      $artifact.exists = -not [string]::IsNullOrWhiteSpace("$($artifact.path)") -and (Test-Path -LiteralPath "$($artifact.path)")
    }
  }

  $finalSavedReport = Save-RefreshReport -Report $savedReport

  Invoke-JsonScript -Name "Closing evidence bundle after final refresh save" -ScriptName "evidence-bundle.ps1" -Arguments @("-OutputDir", $OutputDir) -AllowFailure | Out-Null
  Invoke-JsonScript -Name "Closing completion audit after final refresh bundle" -ScriptName "completion-audit.ps1" -Arguments @("-OutputDir", $OutputDir, "-Save") -AllowFailure | Out-Null

  return $finalSavedReport
}

if ($SelfTest) {
  $tempOutput = Join-Path ([System.IO.Path]::GetTempPath()) "remote-acceptance-refresh-$([guid]::NewGuid().ToString('N'))"
  $oldOutput = $script:ResolvedOutputDir
  $script:ResolvedOutputDir = $tempOutput
  try {
    New-Item -ItemType Directory -Path $tempOutput -Force | Out-Null
    $mockReport = [pscustomobject]@{
      ok = $true
      generatedAt = (Get-Date).ToString("o")
      outputDir = $tempOutput
      completionReady = $false
      onlyPhysicalAuditFailures = $true
      sameWifiPhoneUrls = @("http://192.168.1.20:4317?acceptance=1&gate=same-wifi&step=physical-phone-proof")
      tailscalePhoneUrls = @()
      failedRequirements = @(
        [pscustomobject]@{ id = "PHYSICAL-001"; requirement = "Same-Wi-Fi physical phone acceptance evidence passes the verifier."; detail = "missing phone proof" }
      )
      artifacts = @(
        [pscustomobject]@{ name = "acceptance dashboard HTML"; path = (Join-Path $tempOutput "dashboard.html"); exists = $true }
      )
      steps = @(
        [pscustomobject]@{ name = "Completion audit"; command = "npm run completion:audit"; ok = $false; exitCode = 1; allowedFailure = $true }
      )
    }
    "dashboard" | Set-Content -LiteralPath (Join-Path $tempOutput "dashboard.html") -Encoding UTF8
    $saved = Save-RefreshReport -Report $mockReport
    $markdown = Get-Content -Raw -LiteralPath $saved.refreshMarkdownPath
    $requiredScriptsExist = @(
      "tailscale-bootstrap.ps1",
      "tailscale-setup-check.ps1",
      "acceptance-ready.ps1",
      "acceptance-next.ps1",
      "physical-proof-runbook.ps1",
      "physical-proof-launch.ps1",
      "acceptance-dashboard.ps1",
      "acceptance-handoff.ps1",
      "evidence-bundle.ps1",
      "dependency-audit.ps1",
      "completion-audit.ps1"
    ) | ForEach-Object { Test-Path -LiteralPath (Join-Path $PSScriptRoot $_) }
    $ok = -not ($requiredScriptsExist -contains $false) -and
      (Test-Path -LiteralPath $saved.refreshJsonPath) -and
      (Test-Path -LiteralPath $saved.refreshMarkdownPath) -and
      ($markdown -match "Physical Acceptance Refresh") -and
      ($markdown -match "Allowed Failure") -and
      ($markdown -match "acceptance:phone -- -Gate same-wifi") -and
      ($markdown -match "npm run evidence:bundle") -and
      ($markdown -match "npm run completion:audit:save") -and
      ($markdown -notmatch "npm run acceptance:refresh\s*~~~")
    [pscustomobject]@{
      ok = $ok
      writesJsonAndMarkdown = (Test-Path -LiteralPath $saved.refreshJsonPath) -and (Test-Path -LiteralPath $saved.refreshMarkdownPath)
      requiredScriptsExist = -not ($requiredScriptsExist -contains $false)
      physicalOnlyFailureIsAllowed = $true
    } | ConvertTo-Json -Compress
    if (-not $ok) { exit 1 }
    exit 0
  } finally {
    $script:ResolvedOutputDir = $oldOutput
  }
}

$report = New-RefreshReport
$report | ConvertTo-Json -Depth 10 -Compress
if (-not $report.ok) { exit 1 }
