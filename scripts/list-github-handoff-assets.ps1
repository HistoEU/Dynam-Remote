$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

Write-Host "Remote Controller GitHub handoff assets"
Write-Host ""

$files = @(
  "docs\FIRST_CODEX_GITHUB_PROMPT.txt",
  "docs\USER_COMPUTER_SETUP.md",
  "docs\GOAL_STATUS_LEDGER.md",
  "docs\GITHUB_CREATOR_HANDOFF.md",
  "docs\TRANSFER_MANIFEST.md",
  "docs\GITHUB_MIGRATION_AND_PARALLEL_CODEX.md",
  "docs\CODEX_MULTI_INSTANCE_LAUNCH.md",
  "docs\GITHUB_READY_CHECKLIST.md",
  "docs\GITHUB_ISSUE_BREAKDOWN.md",
  "docs\CODEX_WORKSTREAM_PROMPTS.md",
  "docs\codex_workers\README.md",
  "docs\parallel-work-ledger.md",
  "docs\product_planning\Remote_Controller_Handoff_and_Transfer_Manual.pdf",
  "docs\product_planning\Remote_Controller_Product_Execution_Plan_25_Pages.pdf"
)

foreach ($file in $files) {
  $path = Join-Path $Root $file
  if (Test-Path -LiteralPath $path) {
    $item = Get-Item -LiteralPath $path
    [pscustomobject]@{
      Type = "handoff"
      Path = $file
      SizeKB = [math]::Round($item.Length / 1KB, 1)
    }
  } else {
    [pscustomobject]@{
      Type = "missing"
      Path = $file
      SizeKB = ""
    }
  }
}

Get-ChildItem -LiteralPath (Join-Path $Root "docs\github_issues") -Filter "*.md" |
  Sort-Object Name |
  ForEach-Object {
    [pscustomobject]@{
      Type = "issue"
      Path = "docs\github_issues\$($_.Name)"
      SizeKB = [math]::Round($_.Length / 1KB, 1)
    }
  }

Get-ChildItem -LiteralPath (Join-Path $Root "docs\codex_workers") -Filter "*.txt" |
  Sort-Object Name |
  ForEach-Object {
    [pscustomobject]@{
      Type = "worker-prompt"
      Path = "docs\codex_workers\$($_.Name)"
      SizeKB = [math]::Round($_.Length / 1KB, 1)
    }
  }

Write-Host ""
Write-Host "Start prompt:"
Write-Host "docs\FIRST_CODEX_GITHUB_PROMPT.txt"
Write-Host ""
Write-Host "Multi-Codex launch:"
Write-Host "docs\CODEX_MULTI_INSTANCE_LAUNCH.md"
Write-Host "scripts\create-codex-worktrees.ps1"
Write-Host ""
Write-Host "Readiness audits:"
Write-Host "docs\GITHUB_READY_CHECKLIST.md"
Write-Host "scripts\audit-source-transfer-bundle.ps1"
Write-Host "scripts\audit-github-handoff.ps1"
