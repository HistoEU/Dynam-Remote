param(
  [string]$OutputDir = "output\acceptance",
  [switch]$Save,
  [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$ResolvedOutputDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $Root $OutputDir }

function ConvertTo-MarkdownCell {
  param([string]$Text)
  return "$Text".Replace("|", "\|").Replace("`r", " ").Replace("`n", " ")
}

function Convert-FixAvailableToString {
  param([object]$Value)
  if ($null -eq $Value) { return "" }
  if ($Value -is [bool]) { return "$Value" }
  try { return ($Value | ConvertTo-Json -Compress -Depth 5) } catch { return "$Value" }
}

function New-DependencyAuditResult {
  param([object]$Audit)

  $vulnerabilityRows = @()
  if ($Audit -and $Audit.vulnerabilities) {
    $vulnerabilityRows = @($Audit.vulnerabilities.PSObject.Properties | ForEach-Object {
      $v = $_.Value
      [pscustomobject]@{
        name = "$($_.Name)"
        severity = "$($v.severity)"
        isDirect = [bool]$v.isDirect
        range = "$($v.range)"
        fixAvailable = Convert-FixAvailableToString $v.fixAvailable
        effects = @($v.effects | ForEach-Object { "$_" })
      }
    })
  }

  $highCritical = @($vulnerabilityRows | Where-Object { $_.severity -eq "high" -or $_.severity -eq "critical" })
  $direct = @($vulnerabilityRows | Where-Object { $_.isDirect })
  $moderate = @($vulnerabilityRows | Where-Object { $_.severity -eq "moderate" })
  $total = $vulnerabilityRows.Count

  $status = "clean"
  if ($highCritical.Count -gt 0) {
    $status = "needs-review"
  } elseif ($total -gt 0) {
    $status = "reviewed-known-risk"
  }

  return [pscustomobject]@{
    ok = $highCritical.Count -eq 0
    generatedAt = (Get-Date).ToString("o")
    status = $status
    policy = "Fail on high/critical advisories. Moderate advisories remain reviewed packaging risk while npm reports no direct upstream fix for the current real-input dependency chain."
    total = $total
    moderate = $moderate.Count
    highCritical = $highCritical.Count
    direct = $direct.Count
    advisories = @($vulnerabilityRows)
    metadata = $Audit.metadata
  }
}

function Invoke-NpmAuditJson {
  Push-Location $Root
  try {
    $lines = [System.Collections.Generic.List[string]]::new()
    & npm audit --json 2>&1 | ForEach-Object {
      $lines.Add("$_") | Out-Null
    }
    $text = ($lines -join [Environment]::NewLine).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
      throw "npm audit returned no JSON output."
    }
    return $text | ConvertFrom-Json
  } finally {
    Pop-Location
  }
}

function Write-DependencyAuditReport {
  param([object]$Result)

  New-Item -ItemType Directory -Path $ResolvedOutputDir -Force | Out-Null
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $jsonPath = Join-Path $ResolvedOutputDir "dependency-audit-$timestamp.json"
  $mdPath = Join-Path $ResolvedOutputDir "dependency-audit-$timestamp.md"
  $latestJsonPath = Join-Path $ResolvedOutputDir "dependency-audit-latest.json"
  $latestMdPath = Join-Path $ResolvedOutputDir "dependency-audit-latest.md"

  $Result | Add-Member -NotePropertyName reportJsonPath -NotePropertyValue $jsonPath -Force
  $Result | Add-Member -NotePropertyName reportMarkdownPath -NotePropertyValue $mdPath -Force
  $Result | Add-Member -NotePropertyName latestReportJsonPath -NotePropertyValue $latestJsonPath -Force
  $Result | Add-Member -NotePropertyName latestReportMarkdownPath -NotePropertyValue $latestMdPath -Force

  $Result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  $Result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $latestJsonPath -Encoding UTF8

  $rows = @($Result.advisories | ForEach-Object {
    "| $(ConvertTo-MarkdownCell $_.severity) | $(ConvertTo-MarkdownCell $_.name) | $(ConvertTo-MarkdownCell $_.isDirect) | $(ConvertTo-MarkdownCell $_.fixAvailable) | $(ConvertTo-MarkdownCell $_.range) |"
  })
  if ($rows.Count -eq 0) { $rows = @("| clean | none | false | false | none |") }

  $markdown = @"
# Dependency Audit

Generated: $($Result.generatedAt)
Status: $($Result.status)
Passes packaging policy: $($Result.ok)
Total advisories: $($Result.total)
Moderate advisories: $($Result.moderate)
High/Critical advisories: $($Result.highCritical)
Direct vulnerable dependencies: $($Result.direct)

Policy: $($Result.policy)

## Advisories

| Severity | Package | Direct | Fix available | Range |
| --- | --- | --- | --- | --- |
$($rows -join [Environment]::NewLine)

## Packaging Rule

- Keep real input host-gated.
- Re-run this report before a packaged daily-use release.
- Do not call the build complete if high or critical advisories appear.
"@

  $markdown | Set-Content -LiteralPath $mdPath -Encoding UTF8
  $markdown | Set-Content -LiteralPath $latestMdPath -Encoding UTF8
}

if ($SelfTest) {
  $sample = @{
    vulnerabilities = @{
      "sample-package" = @{
        severity = "moderate"
        isDirect = $true
        range = "<1.0.0"
        fixAvailable = $false
        effects = @()
      }
    }
    metadata = @{
      vulnerabilities = @{ moderate = 1; high = 0; critical = 0; total = 1 }
    }
  } | ConvertTo-Json -Depth 8 | ConvertFrom-Json
  $result = New-DependencyAuditResult -Audit $sample
  $ok = $result.ok -and $result.status -eq "reviewed-known-risk" -and $result.highCritical -eq 0
  [pscustomobject]@{
    ok = $ok
    status = $result.status
    highCritical = $result.highCritical
    policy = $result.policy
  } | ConvertTo-Json -Compress
  if (-not $ok) { exit 1 }
  exit 0
}

$audit = Invoke-NpmAuditJson
$result = New-DependencyAuditResult -Audit $audit
if ($Save) {
  Write-DependencyAuditReport -Result $result
}
$result | ConvertTo-Json -Depth 10 -Compress
if (-not $result.ok) { exit 1 }
