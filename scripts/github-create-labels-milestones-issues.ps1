param(
  [string]$Repo = "",
  [switch]$Apply
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$IssueDir = Join-Path $Root "docs\github_issues"

$Labels = @(
  @{ name = "workstream:repo"; color = "0E8A16"; description = "Repository, GitHub, CI, transfer, and release hygiene" },
  @{ name = "workstream:browser"; color = "1D76DB"; description = "Browser/PWA mobile and desktop controller work" },
  @{ name = "workstream:android"; color = "3DDC84"; description = "Android app shell and Android client work" },
  @{ name = "workstream:ios"; color = "A2AAAD"; description = "iOS app shell and iPhone client work" },
  @{ name = "workstream:remote"; color = "5319E7"; description = "Paid remote signaling, NAT traversal, and relay work" },
  @{ name = "workstream:capture"; color = "FBCA04"; description = "Native capture, video, encode, and performance work" },
  @{ name = "workstream:display"; color = "006B75"; description = "Monitor switching, coordinate mapping, and display identity" },
  @{ name = "workstream:product"; color = "D93F0B"; description = "Product, pricing, store, legal, support, and beta readiness" },
  @{ name = "needs-interface-note"; color = "BFD4F2"; description = "Requires a shared interface note before implementation" },
  @{ name = "needs-physical-device"; color = "C5DEF5"; description = "Requires real phone, monitor, or machine verification" },
  @{ name = "needs-performance-proof"; color = "F9D0C4"; description = "Requires latency, FPS, bandwidth, or benchmark evidence" },
  @{ name = "blocked-external"; color = "E99695"; description = "Blocked by external account, service, device, or permission" },
  @{ name = "release-gate"; color = "B60205"; description = "Must pass before a release or public handoff" }
)

$Milestones = @(
  @{ title = "M0 - Baseline Transfer"; description = "Move current project to the user's computer and GitHub safely." },
  @{ title = "M1 - Free Local Wi-Fi Stabilization"; description = "Make the free local edition reliable enough for GitHub release." },
  @{ title = "M2 - Mobile App Shells"; description = "Prove Android and iOS app direction without destabilizing host." },
  @{ title = "M3 - Paid Remote Architecture"; description = "Prove remote signaling, P2P-first flow, TURN fallback, and cost model." },
  @{ title = "M4 - High-Speed Native Capture"; description = "Decide and prototype native capture/encode path." },
  @{ title = "M5 - Closed Beta Readiness"; description = "Prepare paid beta and store review." }
)

function Invoke-Or-Print {
  param([string[]]$GhArgs)
  $printable = "gh " + (($GhArgs | ForEach-Object {
    if ($_ -match "\s") { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
  }) -join " ")
  if ($Apply) {
    & gh @GhArgs
  } else {
    Write-Host $printable
  }
}

function Get-BacktickValues {
  param([string]$Line)
  $matches = [regex]::Matches($Line, '`([^`]+)`')
  @($matches | ForEach-Object { $_.Groups[1].Value })
}

function Get-IssueMeta {
  param([System.IO.FileInfo]$File)
  $lines = Get-Content -LiteralPath $File.FullName
  $title = ($lines | Where-Object { $_ -like "# Issue *" } | Select-Object -First 1) -replace "^# ",""
  $labelLine = $lines | Where-Object { $_ -like "Labels:*" } | Select-Object -First 1
  $milestoneLine = $lines | Where-Object { $_ -like "Milestone:*" } | Select-Object -First 1
  $labels = Get-BacktickValues $labelLine
  $milestone = (Get-BacktickValues $milestoneLine | Select-Object -First 1)
  [pscustomobject]@{
    File = $File
    Title = $title
    Labels = $labels
    Milestone = $milestone
  }
}

if (-not (Test-Path -LiteralPath $IssueDir)) {
  throw "Missing issue directory: $IssueDir"
}

if ($Apply) {
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI 'gh' was not found. Install GitHub CLI or run without -Apply for dry-run output."
  }
  if (-not $Repo) {
    $Repo = (& gh repo view --json nameWithOwner --jq ".nameWithOwner").Trim()
  }
  if (-not $Repo) {
    throw "Could not determine GitHub repo. Pass -Repo owner/name."
  }
  Write-Host "Applying GitHub setup to $Repo"
} else {
  Write-Host "Dry run. Re-run with -Apply to create labels, milestones, and issues."
  if ($Repo) { Write-Host "Target repo: $Repo" }
}

Write-Host ""
Write-Host "Labels"
foreach ($label in $Labels) {
  $args = @("label", "create", $label.name, "--color", $label.color, "--description", $label.description, "--force")
  if ($Repo) { $args += @("--repo", $Repo) }
  Invoke-Or-Print $args
}

Write-Host ""
Write-Host "Milestones"
foreach ($milestone in $Milestones) {
  $args = @("api", "repos/$Repo/milestones", "-f", "title=$($milestone.title)", "-f", "description=$($milestone.description)")
  if (-not $Repo) {
    Write-Host "gh api repos/<owner>/<repo>/milestones -f title=""$($milestone.title)"" -f description=""$($milestone.description)"""
  } else {
    Invoke-Or-Print $args
  }
}

Write-Host ""
Write-Host "Issues"
Get-ChildItem -LiteralPath $IssueDir -Filter "*.md" |
  Sort-Object Name |
  ForEach-Object {
    $meta = Get-IssueMeta $_
    $args = @("issue", "create", "--title", $meta.Title, "--body-file", $_.FullName)
    foreach ($label in $meta.Labels) { $args += @("--label", $label) }
    if ($meta.Milestone) { $args += @("--milestone", $meta.Milestone) }
    if ($Repo) { $args += @("--repo", $Repo) }
    Invoke-Or-Print $args
  }

Write-Host ""
if ($Apply) {
  Write-Host "GitHub labels, milestones, and issues attempted. Review output above for any already-exists or permission errors."
} else {
  Write-Host "Dry run complete. No GitHub changes were made."
}
