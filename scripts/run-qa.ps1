param(
  [string]$NodePath = "node",
  [string]$HostKey = "dev-host-key",
  [int]$Port = 4317,
  [string]$OutputDir = "output\acceptance",
  [switch]$ReuseExisting,
  [switch]$FreshHost,
  [switch]$Save
)

$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$resolvedOutputDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $root $OutputDir }
$existing = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -First 1
$qaPort = $Port
$preservedExistingPid = $null
$started = $null
$startedAt = Get-Date
$health = $null
$hostState = $null
$nodeTestOutput = @()
$nodeTestExitCode = $null
$selfTestResults = [System.Collections.Generic.List[object]]::new()
$previousEnv = @{
  BASE_URL = $env:BASE_URL
  HOST_KEY = $env:HOST_KEY
  CAPTURE_MODE = $env:CAPTURE_MODE
  PORT = $env:PORT
}

function Get-FreePort {
  param([int]$StartPort)

  for ($candidate = $StartPort; $candidate -lt ($StartPort + 100); $candidate += 1) {
    $listener = Get-NetTCPConnection -LocalPort $candidate -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $listener) { return $candidate }
  }
  throw "Could not find a free local QA port starting at $StartPort."
}

function Invoke-SelfTest {
  param(
    [string]$Name,
    [string]$Script
  )

  $scriptPath = Join-Path $root $Script
  $raw = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -SelfTest 2>&1)
  $exitCode = $LASTEXITCODE
  $parsed = $null
  $jsonLine = @($raw | Where-Object { "$_".Trim().StartsWith("{") }) | Select-Object -Last 1
  if ($jsonLine) {
    try {
      $parsed = $jsonLine | ConvertFrom-Json
    } catch {
      $parsed = $null
    }
  }
  $ok = ($exitCode -eq 0) -and $parsed -and $parsed.ok -eq $true
  $selfTestResults.Add([pscustomobject]@{
    name = $Name
    script = $Script
    ok = [bool]$ok
    exitCode = $exitCode
    output = @($raw | ForEach-Object { "$_" })
  }) | Out-Null
  if (-not $ok) {
    throw "Self-test failed: $Name"
  }
}

function Get-NodeTestSummary {
  param([string[]]$Output)

  $summary = [ordered]@{
    tests = $null
    pass = $null
    fail = $null
    durationMs = $null
  }
  foreach ($line in @($Output)) {
    if ($line -match "tests\s+(\d+)") { $summary.tests = [int]$Matches[1] }
    if ($line -match "pass\s+(\d+)") { $summary.pass = [int]$Matches[1] }
    if ($line -match "fail\s+(\d+)") { $summary.fail = [int]$Matches[1] }
    if ($line -match "duration_ms\s+([0-9.]+)") { $summary.durationMs = [double]$Matches[1] }
  }
  return [pscustomobject]$summary
}

function Get-ArtifactRecord {
  param(
    [string]$Name,
    [string]$RelativePath
  )

  $path = Join-Path $resolvedOutputDir $RelativePath
  $item = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
  return [pscustomobject]@{
    name = $Name
    relativePath = $RelativePath
    path = $path
    exists = [bool]$item
    bytes = if ($item) { [int64]$item.Length } else { 0 }
    lastWriteTime = if ($item) { $item.LastWriteTime.ToString("o") } else { $null }
  }
}

function Get-RootArtifactRecord {
  param(
    [string]$Name,
    [string]$RelativePath
  )

  $path = Join-Path $root $RelativePath
  $item = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
  return [pscustomobject]@{
    name = $Name
    relativePath = $RelativePath
    path = $path
    exists = [bool]$item
    bytes = if ($item) { [int64]$item.Length } else { 0 }
    lastWriteTime = if ($item) { $item.LastWriteTime.ToString("o") } else { $null }
  }
}

function Get-QaArtifactSnapshot {
  return @(
    Get-ArtifactRecord -Name "acceptance dashboard latest HTML" -RelativePath "phone-acceptance-dashboard-latest.html"
    Get-ArtifactRecord -Name "acceptance dashboard latest JSON" -RelativePath "phone-acceptance-dashboard-latest.json"
    Get-ArtifactRecord -Name "acceptance handoff latest HTML" -RelativePath "phone-acceptance-handoff-latest.html"
    Get-ArtifactRecord -Name "acceptance handoff latest Markdown" -RelativePath "phone-acceptance-handoff-latest.md"
    Get-ArtifactRecord -Name "acceptance handoff latest JSON" -RelativePath "phone-acceptance-handoff-latest.json"
    Get-ArtifactRecord -Name "physical proof runbook latest Markdown" -RelativePath "physical-proof-runbook-latest.md"
    Get-ArtifactRecord -Name "physical proof runbook latest JSON" -RelativePath "physical-proof-runbook-latest.json"
    Get-ArtifactRecord -Name "same-Wi-Fi physical proof launch latest Markdown" -RelativePath "physical-proof-launch-same-wifi-latest.md"
    Get-ArtifactRecord -Name "same-Wi-Fi physical proof launch latest JSON" -RelativePath "physical-proof-launch-same-wifi-latest.json"
    Get-ArtifactRecord -Name "Tailscale physical proof launch latest Markdown" -RelativePath "physical-proof-launch-tailscale-latest.md"
    Get-ArtifactRecord -Name "Tailscale physical proof launch latest JSON" -RelativePath "physical-proof-launch-tailscale-latest.json"
    Get-ArtifactRecord -Name "evidence bundle latest Markdown" -RelativePath "remote-controller-evidence-bundle-latest.md"
    Get-ArtifactRecord -Name "evidence bundle latest JSON" -RelativePath "remote-controller-evidence-bundle-latest.json"
    Get-ArtifactRecord -Name "acceptance refresh latest Markdown" -RelativePath "phone-acceptance-refresh-latest.md"
    Get-ArtifactRecord -Name "acceptance refresh latest JSON" -RelativePath "phone-acceptance-refresh-latest.json"
    Get-ArtifactRecord -Name "firewall handoff latest Markdown" -RelativePath "firewall-handoff-install-latest.md"
    Get-ArtifactRecord -Name "firewall handoff latest JSON" -RelativePath "firewall-handoff-install-latest.json"
    Get-ArtifactRecord -Name "physical finalization latest Markdown" -RelativePath "physical-evidence-finalization-latest.md"
    Get-ArtifactRecord -Name "physical finalization latest JSON" -RelativePath "physical-evidence-finalization-latest.json"
    Get-ArtifactRecord -Name "completion audit latest Markdown" -RelativePath "completion-audit-latest.md"
    Get-ArtifactRecord -Name "completion audit latest JSON" -RelativePath "completion-audit-latest.json"
    Get-ArtifactRecord -Name "live phone visual proof latest JSON" -RelativePath "live-phone-visual-proof-latest.json"
    Get-ArtifactRecord -Name "live phone visual proof latest PNG" -RelativePath "live-phone-visual-proof-latest.png"
    Get-RootArtifactRecord -Name "active finalization manual DOCX" -RelativePath "docs\Remote_Controller_Finalization_Plan.docx"
    Get-RootArtifactRecord -Name "active finalization traceability Markdown" -RelativePath "docs\FINALIZATION_TRACEABILITY.md"
    Get-RootArtifactRecord -Name "legacy build manual traceability Markdown" -RelativePath "docs\TRACEABILITY_AUDIT.md"
  )
}

function Save-QaReport {
  param([object]$Report)

  New-Item -ItemType Directory -Path $resolvedOutputDir -Force | Out-Null
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $jsonPath = Join-Path $resolvedOutputDir "qa-report-$timestamp.json"
  $mdPath = Join-Path $resolvedOutputDir "qa-report-$timestamp.md"
  $latestJsonPath = Join-Path $resolvedOutputDir "qa-report-latest.json"
  $latestMdPath = Join-Path $resolvedOutputDir "qa-report-latest.md"
  $Report | Add-Member -NotePropertyName reportJsonPath -NotePropertyValue $jsonPath -Force
  $Report | Add-Member -NotePropertyName reportMarkdownPath -NotePropertyValue $mdPath -Force
  $Report | Add-Member -NotePropertyName latestReportJsonPath -NotePropertyValue $latestJsonPath -Force
  $Report | Add-Member -NotePropertyName latestReportMarkdownPath -NotePropertyValue $latestMdPath -Force
  $Report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  $Report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $latestJsonPath -Encoding UTF8

  $selfRows = @($Report.selfTests | ForEach-Object {
    "| $($_.ok) | $($_.name) | $($_.script) |"
  })
  if ($selfRows.Count -eq 0) { $selfRows = @("| none | none | none |") }

  $artifactRows = @($Report.artifacts | ForEach-Object {
    "| $($_.exists) | $($_.name) | $($_.relativePath) | $($_.bytes) | $($_.lastWriteTime) |"
  })
  if ($artifactRows.Count -eq 0) { $artifactRows = @("| none | none | none | none | none |") }

  $markdown = @"
# QA Report

Generated: $($Report.generatedAt)
OK: $($Report.ok)
Node path: $($Report.nodePath)
Host mode: $($Report.host.mode)
Host health reachable: $($Report.host.reachable)
Node tests: $($Report.nodeTests.summary.tests)
Node pass: $($Report.nodeTests.summary.pass)
Node fail: $($Report.nodeTests.summary.fail)

This report records the automated/local QA gate. It does not replace the real same-Wi-Fi or Tailscale phone evidence.

## Self-Tests

| OK | Name | Script |
| --- | --- | --- |
$($selfRows -join [Environment]::NewLine)

## Operator Artifact Snapshot

| Exists | Name | Relative Path | Bytes | Last Write |
| --- | --- | --- | --- | --- |
$($artifactRows -join [Environment]::NewLine)

## Physical Gates

- Same-Wi-Fi physical phone proof is still required.
- Tailscale/different-Wi-Fi physical phone proof is still required.
"@
  $markdown | Set-Content -LiteralPath $mdPath -Encoding UTF8
  $markdown | Set-Content -LiteralPath $latestMdPath -Encoding UTF8
}

try {
  if ($existing -and $FreshHost -and -not $ReuseExisting) {
    Stop-Process -Id $existing -Force
    Start-Sleep -Milliseconds 400
    $existing = $null
  }

  if ($existing -and -not $ReuseExisting -and -not $FreshHost) {
    $preservedExistingPid = $existing
    $qaPort = Get-FreePort -StartPort ($Port + 1)
    $existing = $null
  }

  if (-not $existing) {
    $env:HOST_KEY = $HostKey
    $env:CAPTURE_MODE = "screen"
    $env:PORT = "$qaPort"
    $started = Start-Process -FilePath $NodePath -ArgumentList "src\server.js" -WorkingDirectory $root -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 2
  }

  $env:BASE_URL = "http://127.0.0.1:$qaPort"

  $health = Invoke-RestMethod -Uri "http://127.0.0.1:$qaPort/api/health"
  if (-not $health.ok) {
    throw "Health check failed."
  }
  $hostState = Invoke-RestMethod -Uri "http://127.0.0.1:$qaPort/api/host?key=$([uri]::EscapeDataString($HostKey))"

  Push-Location $root
  try {
    $nodeTestLines = [System.Collections.Generic.List[string]]::new()
    & $NodePath --test 2>&1 | ForEach-Object {
      $line = "$_"
      $nodeTestLines.Add($line) | Out-Null
      $line
    }
    $nodeTestExitCode = $LASTEXITCODE
    $nodeTestOutput = @($nodeTestLines)
    if ($nodeTestExitCode -ne 0) {
      throw "Automated tests failed with exit code $nodeTestExitCode."
    }

    foreach ($selfTest in @(
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
    )) {
      Invoke-SelfTest -Name $selfTest.name -Script $selfTest.script
    }
  } finally {
    Pop-Location
  }

  if ($Save) {
    $summary = Get-NodeTestSummary -Output $nodeTestOutput
    $report = [pscustomobject]@{
      ok = $true
      generatedAt = (Get-Date).ToString("o")
      startedAt = $startedAt.ToString("o")
      nodePath = $NodePath
      host = [pscustomobject]@{
        reachable = [bool]($health -and $health.ok)
        mode = if ($hostState -and $hostState.app) { "$($hostState.app.mode)" } else { "" }
        source = if ($hostState -and $hostState.streamStats) { "$($hostState.streamStats.source)" } else { "" }
        port = $qaPort
        baseUrl = "http://127.0.0.1:$qaPort"
        preservedExistingPid = if ($preservedExistingPid) { [int]$preservedExistingPid } else { 0 }
        preservedLiveHost = [bool]$preservedExistingPid
        reusedExisting = [bool]($existing -and -not $started)
        startedByQa = [bool]$started
      }
      nodeTests = [pscustomobject]@{
        exitCode = $nodeTestExitCode
        summary = $summary
        output = @($nodeTestOutput | ForEach-Object { "$_" })
      }
      selfTests = @($selfTestResults)
      artifacts = @(Get-QaArtifactSnapshot)
    }
    Save-QaReport -Report $report
  }
} finally {
  if ($started -and -not $started.HasExited) {
    Stop-Process -Id $started.Id -Force
  }
  $env:BASE_URL = $previousEnv.BASE_URL
  $env:HOST_KEY = $previousEnv.HOST_KEY
  $env:CAPTURE_MODE = $previousEnv.CAPTURE_MODE
  $env:PORT = $previousEnv.PORT
}
