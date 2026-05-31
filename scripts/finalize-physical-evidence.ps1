param(
  [string]$OutputDir = "output\acceptance",
  [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$ResolvedOutputDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $Root $OutputDir }

function Invoke-JsonScript {
  param(
    [string]$Name,
    [string]$ScriptName,
    [string[]]$Arguments = @(),
    [switch]$AllowFailure,
    [int]$TimeoutSeconds = 120
  )

  $scriptPath = Join-Path $PSScriptRoot $ScriptName
  if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
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

  $tempPrefix = Join-Path ([System.IO.Path]::GetTempPath()) "remote-physical-finalize-$([guid]::NewGuid().ToString('N'))"
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

function ConvertTo-StepSummary {
  param([object]$Step)

  $parsed = $Step.parsed
  $primaryPath = ""
  $status = ""
  if ($parsed) {
    if ($parsed.PSObject.Properties.Name -contains "status") { $status = "$($parsed.status)" }
    foreach ($pathName in @(
      "verificationJsonPath",
      "bundleMarkdownPath",
      "auditMarkdownPath"
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
    parsedOk = if ($parsed -and $parsed.PSObject.Properties.Name -contains "ok") { $parsed.ok } else { $null }
    status = $status
    primaryPath = $primaryPath
  }
}

function Get-FailedCheckRows {
  param(
    [object]$Parsed,
    [string]$Fallback
  )

  if ($Parsed -and $Parsed.checks) {
    return @($Parsed.checks | Where-Object { $_.passed -eq $false } | ForEach-Object {
      [pscustomobject]@{ name = "$($_.name)"; detail = "$($_.detail)" }
    })
  }
  if ($Parsed -and $Parsed.failedIds) {
    return @($Parsed.failedIds | ForEach-Object {
      [pscustomobject]@{ name = "$_"; detail = "completion audit failed requirement" }
    })
  }
  if ($Parsed -and $Parsed.gates) {
    $gateRows = @($Parsed.gates | Where-Object { $_.verifierOk -ne $true } | ForEach-Object {
      $gate = "$($_.gate)"
      @($_.failedChecks | ForEach-Object {
        [pscustomobject]@{ name = "$gate`: $($_.name)"; detail = "$($_.detail)" }
      })
    })
    if ($gateRows.Count -gt 0) { return $gateRows }
  }
  return @([pscustomobject]@{ name = "command output"; detail = $Fallback })
}

function New-ArtifactRecord {
  param(
    [string]$Name,
    [string]$PathValue
  )

  $exists = -not [string]::IsNullOrWhiteSpace($PathValue) -and (Test-Path -LiteralPath $PathValue)
  return [pscustomobject]@{
    name = $Name
    path = "$PathValue"
    exists = $exists
  }
}

function Write-FinalizationMarkdown {
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

  $failedRows = @($Report.remainingFailures | ForEach-Object {
    "- $($_.gate): $($_.name) - $($_.detail)"
  })
  if ($failedRows.Count -eq 0) { $failedRows = @("- none") }

  $markdown = @"
# Physical Evidence Finalization

Generated: $($Report.generatedAt)
Complete: $($Report.ok)
Same-Wi-Fi verifier: $($Report.sameWifiVerifierOk)
Tailscale verifier: $($Report.tailscaleVerifierOk)
Completion audit: $($Report.completionAuditOk)

This report is the final no-refresh path. It verifies both physical gates, bundles evidence, and runs the whole-manual completion audit. It deliberately does not prepare, ready, refresh, or open a new run card, because doing that after phone proof can make the manual summary stale.

## Steps

| OK | Exit | Allowed Failure | Step | Command |
| --- | --- | --- | --- | --- |
$($stepRows -join [Environment]::NewLine)

## Artifacts

| Exists | Name | Path |
| --- | --- | --- |
$($artifactRows -join [Environment]::NewLine)

## Remaining Failures

$($failedRows -join [Environment]::NewLine)

## Correct Final Order

~~~powershell
npm run acceptance:phone -- -Gate same-wifi -SkipStart -RequireReady
npm run acceptance:phone -- -Gate tailscale -SkipStart -RequireReady
npm run acceptance:finalize
~~~
"@

  $markdown | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Save-FinalizationReport {
  param([object]$Report)

  New-Item -ItemType Directory -Path $ResolvedOutputDir -Force | Out-Null
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $jsonPath = Join-Path $ResolvedOutputDir "physical-evidence-finalization-$timestamp.json"
  $mdPath = Join-Path $ResolvedOutputDir "physical-evidence-finalization-$timestamp.md"
  $latestJsonPath = Join-Path $ResolvedOutputDir "physical-evidence-finalization-latest.json"
  $latestMdPath = Join-Path $ResolvedOutputDir "physical-evidence-finalization-latest.md"
  $Report | Add-Member -NotePropertyName finalizationJsonPath -NotePropertyValue $jsonPath -Force
  $Report | Add-Member -NotePropertyName finalizationMarkdownPath -NotePropertyValue $mdPath -Force
  $Report | Add-Member -NotePropertyName latestFinalizationJsonPath -NotePropertyValue $latestJsonPath -Force
  $Report | Add-Member -NotePropertyName latestFinalizationMarkdownPath -NotePropertyValue $latestMdPath -Force
  $Report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  $Report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $latestJsonPath -Encoding UTF8
  Write-FinalizationMarkdown -Report $Report -Path $mdPath
  Write-FinalizationMarkdown -Report $Report -Path $latestMdPath
  return $Report
}

function New-FinalizationReport {
  $steps = [System.Collections.Generic.List[object]]::new()

  $sameWifi = Invoke-JsonScript -Name "Same-Wi-Fi verifier save" -ScriptName "verify-phone-acceptance.ps1" -Arguments @("-Gate", "same-wifi", "-OutputDir", $OutputDir, "-Save") -AllowFailure
  $steps.Add($sameWifi) | Out-Null

  $tailscale = Invoke-JsonScript -Name "Tailscale verifier save" -ScriptName "verify-phone-acceptance.ps1" -Arguments @("-Gate", "tailscale", "-OutputDir", $OutputDir, "-Save") -AllowFailure
  $steps.Add($tailscale) | Out-Null

  $bundle = Invoke-JsonScript -Name "Evidence bundle" -ScriptName "evidence-bundle.ps1" -Arguments @("-OutputDir", $OutputDir) -AllowFailure
  $steps.Add($bundle) | Out-Null

  $audit = Invoke-JsonScript -Name "Completion audit save" -ScriptName "completion-audit.ps1" -Arguments @("-OutputDir", $OutputDir, "-Save") -AllowFailure
  $steps.Add($audit) | Out-Null

  $remaining = @()
  foreach ($entry in @(
    [pscustomobject]@{ gate = "same-wifi"; step = $sameWifi },
    [pscustomobject]@{ gate = "tailscale"; step = $tailscale },
    [pscustomobject]@{ gate = "bundle"; step = $bundle },
    [pscustomobject]@{ gate = "audit"; step = $audit }
  )) {
    if (-not $entry.step.ok) {
      $fallback = (($entry.step.raw -join " ") -replace "\s+", " ").Trim()
      $remaining += @(Get-FailedCheckRows -Parsed $entry.step.parsed -Fallback $fallback | ForEach-Object {
        [pscustomobject]@{ gate = $entry.gate; name = "$($_.name)"; detail = "$($_.detail)" }
      })
    }
  }

  $report = [pscustomobject]@{
    ok = $sameWifi.ok -and $tailscale.ok -and $bundle.ok -and $audit.ok
    generatedAt = (Get-Date).ToString("o")
    outputDir = "$ResolvedOutputDir"
    sameWifiVerifierOk = [bool]$sameWifi.ok
    tailscaleVerifierOk = [bool]$tailscale.ok
    evidenceBundleOk = [bool]$bundle.ok
    completionAuditOk = [bool]$audit.ok
    remainingFailures = @($remaining)
    artifacts = @(
      New-ArtifactRecord "same-Wi-Fi saved verifier JSON" $(if ($sameWifi.parsed) { "$($sameWifi.parsed.verificationJsonPath)" } else { "" })
      New-ArtifactRecord "Tailscale saved verifier JSON" $(if ($tailscale.parsed) { "$($tailscale.parsed.verificationJsonPath)" } else { "" })
      New-ArtifactRecord "evidence bundle Markdown" $(if ($bundle.parsed) { "$($bundle.parsed.bundleMarkdownPath)" } else { "" })
      New-ArtifactRecord "evidence bundle JSON" $(if ($bundle.parsed) { "$($bundle.parsed.bundleJsonPath)" } else { "" })
      New-ArtifactRecord "completion audit Markdown" $(if ($audit.parsed) { "$($audit.parsed.auditMarkdownPath)" } else { "" })
      New-ArtifactRecord "completion audit JSON" $(if ($audit.parsed) { "$($audit.parsed.auditJsonPath)" } else { "" })
    )
    steps = @($steps | ForEach-Object { ConvertTo-StepSummary -Step $_ })
  }

  return Save-FinalizationReport -Report $report
}

if ($SelfTest) {
  $tempOutput = Join-Path ([System.IO.Path]::GetTempPath()) "remote-physical-finalize-$([guid]::NewGuid().ToString('N'))"
  $oldOutput = $script:ResolvedOutputDir
  $script:ResolvedOutputDir = $tempOutput
  try {
    New-Item -ItemType Directory -Path $tempOutput -Force | Out-Null
    $mockReport = [pscustomobject]@{
      ok = $false
      generatedAt = (Get-Date).ToString("o")
      outputDir = $tempOutput
      sameWifiVerifierOk = $false
      tailscaleVerifierOk = $false
      evidenceBundleOk = $false
      completionAuditOk = $false
      remainingFailures = @(
        [pscustomobject]@{ gate = "same-wifi"; name = "phone proof log exists"; detail = "event=acceptance.phoneMark" }
      )
      artifacts = @()
      steps = @(
        [pscustomobject]@{ name = "Same-Wi-Fi verifier save"; command = "npm run acceptance:verify:save -- -Gate same-wifi"; ok = $false; exitCode = 1; allowedFailure = $true }
      )
    }
    $saved = Save-FinalizationReport -Report $mockReport
    $markdown = Get-Content -Raw -LiteralPath $saved.finalizationMarkdownPath
    $requiredScriptsExist = @(
      "verify-phone-acceptance.ps1",
      "evidence-bundle.ps1",
      "completion-audit.ps1"
    ) | ForEach-Object { Test-Path -LiteralPath (Join-Path $PSScriptRoot $_) }
    $ok = -not ($requiredScriptsExist -contains $false) -and
      (Test-Path -LiteralPath $saved.finalizationJsonPath) -and
      (Test-Path -LiteralPath $saved.finalizationMarkdownPath) -and
      ($markdown -match "Physical Evidence Finalization") -and
      ($markdown -match "npm run acceptance:finalize") -and
      ($markdown -notmatch "acceptance:refresh") -and
      ($markdown -notmatch "acceptance:ready")
    [pscustomobject]@{
      ok = $ok
      writesJsonAndMarkdown = (Test-Path -LiteralPath $saved.finalizationJsonPath) -and (Test-Path -LiteralPath $saved.finalizationMarkdownPath)
      requiredScriptsExist = -not ($requiredScriptsExist -contains $false)
      avoidsReadinessRefresh = ($markdown -notmatch "acceptance:refresh") -and ($markdown -notmatch "acceptance:ready")
    } | ConvertTo-Json -Compress
    if (-not $ok) { exit 1 }
    exit 0
  } finally {
    $script:ResolvedOutputDir = $oldOutput
  }
}

$report = New-FinalizationReport
$report | ConvertTo-Json -Depth 10 -Compress
if (-not $report.ok) { exit 1 }
