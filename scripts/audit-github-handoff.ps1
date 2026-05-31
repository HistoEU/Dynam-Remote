param(
  [switch]$RunTests
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

function Test-RelativePath {
  param([string]$Path)
  Test-Path -LiteralPath (Join-Path $Root $Path)
}

function Add-Finding {
  param(
    [System.Collections.Generic.List[object]]$Findings,
    [string]$Check,
    [string]$Status,
    [string]$Detail
  )

  $Findings.Add([pscustomobject]@{
    check = $Check
    status = $Status
    detail = $Detail
  }) | Out-Null
}

$findings = [System.Collections.Generic.List[object]]::new()

$requiredFiles = @(
  ".gitattributes",
  ".gitignore",
  ".github/workflows/ci.yml",
  ".github/PULL_REQUEST_TEMPLATE.md",
  ".github/ISSUE_TEMPLATE/product_workstream.yml",
  ".github/ISSUE_TEMPLATE/bug_report.yml",
  "README.md",
  "MILESTONE_STATUS.md",
  "package.json",
  "package-lock.json",
  "docs/FIRST_CODEX_GITHUB_PROMPT.txt",
  "docs/GITHUB_CREATOR_HANDOFF.md",
  "docs/GITHUB_READY_CHECKLIST.md",
  "docs/TRANSFER_MANIFEST.md",
  "docs/GITHUB_MIGRATION_AND_PARALLEL_CODEX.md",
  "docs/GITHUB_ISSUE_BREAKDOWN.md",
  "docs/CODEX_MULTI_INSTANCE_LAUNCH.md",
  "docs/CODEX_WORKSTREAM_PROMPTS.md",
  "docs/codex_workers/README.md",
  "docs/codex_workers/stabilize-github-migration.txt",
  "docs/codex_workers/browser-pwa-polish.txt",
  "docs/codex_workers/display-monitor-accuracy.txt",
  "docs/codex_workers/host-native-capture-spike.txt",
  "docs/codex_workers/infra-remote-signaling.txt",
  "docs/codex_workers/mobile-android-shell.txt",
  "docs/codex_workers/mobile-ios-shell.txt",
  "docs/codex_workers/product-billing-store-readiness.txt",
  "docs/GOAL_STATUS_LEDGER.md",
  "docs/parallel-work-ledger.md",
  "docs/interfaces/README.md",
  "docs/workstreams/README.md",
  "docs/product_planning/Remote_Controller_Product_Execution_Plan_25_Pages.pdf",
  "docs/product_planning/Remote_Controller_Product_Execution_Plan_25_Pages.docx",
  "docs/product_planning/Remote_Controller_Handoff_and_Transfer_Manual.pdf",
  "docs/product_planning/Remote_Controller_Handoff_and_Transfer_Manual.docx",
  "docs/product_planning/preview_density_audit.txt",
  "scripts/create-source-transfer-bundle.ps1",
  "scripts/audit-source-transfer-bundle.ps1",
  "scripts/audit-github-handoff.ps1",
  "scripts/list-github-handoff-assets.ps1",
  "scripts/bootstrap-github-baseline.ps1",
  "scripts/github-create-labels-milestones-issues.ps1",
  "scripts/create-codex-worktrees.ps1",
  "scripts/verify-user-computer-setup.ps1",
  "src/server.js",
  "public/app.js",
  "public/host.js",
  "public/capture.js",
  "test/protocol.test.js",
  "test/settings-store.test.js",
  "test/session-store.test.js",
  "test/coordinate-mapper.test.js",
  "test/input-adapter.test.js"
)

$missingFiles = @($requiredFiles | Where-Object { -not (Test-RelativePath $_) })
if ($missingFiles.Count -eq 0) {
  Add-Finding $findings "required files" "pass" "$($requiredFiles.Count) required files present"
} else {
  Add-Finding $findings "required files" "fail" ("Missing: " + ($missingFiles -join ", "))
}

$issueFiles = @(Get-ChildItem -LiteralPath (Join-Path $Root "docs/github_issues") -Filter "*.md" -ErrorAction SilentlyContinue | Sort-Object Name)
if ($issueFiles.Count -eq 10) {
  Add-Finding $findings "github issues" "pass" "10 issue files present"
} else {
  Add-Finding $findings "github issues" "fail" "Expected 10 issue files, found $($issueFiles.Count)"
}

$workstreamFiles = @(Get-ChildItem -LiteralPath (Join-Path $Root "docs/workstreams") -Filter "*.md" -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "README.md" } | Sort-Object Name)
if ($workstreamFiles.Count -eq 7) {
  Add-Finding $findings "workstream briefs" "pass" "7 workstream briefs present"
} else {
  Add-Finding $findings "workstream briefs" "fail" "Expected 7 workstream briefs, found $($workstreamFiles.Count)"
}

$workerPromptFiles = @(Get-ChildItem -LiteralPath (Join-Path $Root "docs/codex_workers") -Filter "*.txt" -ErrorAction SilentlyContinue | Sort-Object Name)
if ($workerPromptFiles.Count -eq 8) {
  Add-Finding $findings "worker prompts" "pass" "8 ready-to-paste Codex worker prompts present"
} else {
  Add-Finding $findings "worker prompts" "fail" "Expected 8 worker prompt files, found $($workerPromptFiles.Count)"
}

$interfaceFiles = @(Get-ChildItem -LiteralPath (Join-Path $Root "docs/interfaces") -Filter "*.md" -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "README.md" } | Sort-Object Name)
if ($interfaceFiles.Count -ge 5) {
  Add-Finding $findings "interface contracts" "pass" "$($interfaceFiles.Count) interface contracts present"
} else {
  Add-Finding $findings "interface contracts" "fail" "Expected at least 5 interface contracts, found $($interfaceFiles.Count)"
}

$planPreviewDir = Join-Path $Root "docs/product_planning/page_previews_plan_verified"
$planPreviewCount = @(Get-ChildItem -LiteralPath $planPreviewDir -Filter "*.png" -ErrorAction SilentlyContinue).Count
if ($planPreviewCount -eq 25) {
  Add-Finding $findings "plan previews" "pass" "25 verified plan page previews present"
} else {
  Add-Finding $findings "plan previews" "fail" "Expected 25 verified plan page previews, found $planPreviewCount"
}

$handoffPreviewDir = Join-Path $Root "docs/product_planning/page_previews_handoff_verified"
$handoffPreviewCount = @(Get-ChildItem -LiteralPath $handoffPreviewDir -Filter "*.png" -ErrorAction SilentlyContinue).Count
if ($handoffPreviewCount -ge 1) {
  Add-Finding $findings "handoff previews" "pass" "$handoffPreviewCount verified handoff page previews present"
} else {
  Add-Finding $findings "handoff previews" "fail" "No verified handoff page previews found"
}

$densityPath = Join-Path $Root "docs/product_planning/preview_density_audit.txt"
if (Test-Path -LiteralPath $densityPath) {
  $density = Get-Content -LiteralPath $densityPath -Raw
  $planDensityLines = [regex]::Matches($density, "(?m)^plan page \d{2}: non-background density \d+\.\d+").Count
  if ($density -match "Plan preview page count:\s*25" -and $planDensityLines -eq 25) {
    Add-Finding $findings "density audit" "pass" "25-page plan density audit present with density readings for every plan page"
  } else {
    Add-Finding $findings "density audit" "fail" "Density audit exists but does not prove 25 plan pages with per-page density readings"
  }
} else {
  Add-Finding $findings "density audit" "fail" "Missing preview_density_audit.txt"
}

$scriptFiles = @(
  "scripts/create-source-transfer-bundle.ps1",
  "scripts/audit-source-transfer-bundle.ps1",
  "scripts/audit-github-handoff.ps1",
  "scripts/bootstrap-github-baseline.ps1",
  "scripts/github-create-labels-milestones-issues.ps1",
  "scripts/create-codex-worktrees.ps1",
  "scripts/verify-user-computer-setup.ps1",
  "scripts/list-github-handoff-assets.ps1"
)

$syntaxErrors = @()
foreach ($script in $scriptFiles) {
  $full = Join-Path $Root $script
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($full, [ref]$null, [ref]$errors) | Out-Null
  if ($errors) {
    $syntaxErrors += "$($script): $($errors[0].Message)"
  }
}

if ($syntaxErrors.Count -eq 0) {
  Add-Finding $findings "powershell syntax" "pass" "$($scriptFiles.Count) handoff scripts parse"
} else {
  Add-Finding $findings "powershell syntax" "fail" ($syntaxErrors -join "; ")
}

$zipAuditOutput = $null
$zipAuditFailed = $false
try {
  $zipAuditOutput = & (Join-Path $Root "scripts/audit-source-transfer-bundle.ps1") | Out-String
} catch {
  $zipAuditFailed = $true
  $zipAuditOutput = $_.Exception.Message
}

if ($zipAuditFailed) {
  Add-Finding $findings "source transfer zip" "fail" $zipAuditOutput.Trim()
} else {
  $zipAudit = $zipAuditOutput | ConvertFrom-Json
  if ($zipAudit.missingRequiredCount -eq 0 -and $zipAudit.forbiddenCount -eq 0 -and $zipAudit.sidecarMatches) {
    Add-Finding $findings "source transfer zip" "pass" "ZIP clean, required files present, sidecar hash matches"
  } else {
    Add-Finding $findings "source transfer zip" "fail" "missing=$($zipAudit.missingRequiredCount), forbidden=$($zipAudit.forbiddenCount), sidecarMatches=$($zipAudit.sidecarMatches)"
  }
}

if ($RunTests) {
  $testOutput = $null
  $testFailed = $false
  try {
    $testOutput = & node --test test\protocol.test.js test\settings-store.test.js test\session-store.test.js test\coordinate-mapper.test.js test\input-adapter.test.js 2>&1 | Out-String
  } catch {
    $testFailed = $true
    $testOutput = $_.Exception.Message
  }

  if ($testFailed -or $LASTEXITCODE -ne 0) {
    Add-Finding $findings "protected node tests" "fail" $testOutput.Trim()
  } else {
    Add-Finding $findings "protected node tests" "pass" "Protected Node tests completed"
  }
} else {
  Add-Finding $findings "protected node tests" "skip" "Use -RunTests to include protected Node tests"
}

$failed = @($findings | Where-Object { $_.status -eq "fail" })
$result = [pscustomobject]@{
  root = $Root
  status = if ($failed.Count -eq 0) { "pass" } else { "fail" }
  failedCount = $failed.Count
  findings = @($findings)
}

$result | ConvertTo-Json -Depth 5

if ($failed.Count -gt 0) {
  exit 1
}
