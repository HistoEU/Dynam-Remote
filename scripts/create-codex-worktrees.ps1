param(
  [string]$BaseDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "codex-worktrees"),
  [string]$StartPoint = "main",
  [switch]$Apply
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

function Write-PlanLine {
  param(
    [string]$Label,
    [string]$Value
  )
  Write-Host ("{0,-16} {1}" -f $Label, $Value)
}

$workstreams = @(
  [pscustomobject]@{
    Branch = "stabilize/github-migration"
    Folder = "stabilize-github-migration"
    Brief = "docs/GITHUB_CREATOR_HANDOFF.md"
    Issue = "docs/github_issues/01-baseline-repo-and-tag.md"
    Prompt = "docs/codex_workers/stabilize-github-migration.txt"
    Scope = "GitHub baseline, CI, labels, milestones, issues, release artifact handling"
  },
  [pscustomobject]@{
    Branch = "browser/pwa-polish"
    Folder = "browser-pwa-polish"
    Brief = "docs/workstreams/browser-pwa-stabilization.md"
    Issue = "docs/github_issues/03-browser-pwa-regression-lock.md"
    Prompt = "docs/codex_workers/browser-pwa-polish.txt"
    Scope = "Browser/PWA touchpad, zoom/lens settings, local Wi-Fi controller polish"
  },
  [pscustomobject]@{
    Branch = "display/monitor-accuracy"
    Folder = "display-monitor-accuracy"
    Brief = "docs/workstreams/monitor-accuracy-and-display-switching.md"
    Issue = "docs/github_issues/05-monitor-coordinate-accuracy.md"
    Prompt = "docs/codex_workers/display-monitor-accuracy.txt"
    Scope = "Monitor switching, coordinate mapping, multi-resolution display correctness"
  },
  [pscustomobject]@{
    Branch = "mobile/android-shell"
    Folder = "mobile-android-shell"
    Brief = "docs/workstreams/android-app-shell.md"
    Issue = "docs/github_issues/06-android-shell.md"
    Prompt = "docs/codex_workers/mobile-android-shell.txt"
    Scope = "Android app shell and native mobile wrapper path"
  },
  [pscustomobject]@{
    Branch = "mobile/ios-shell"
    Folder = "mobile-ios-shell"
    Brief = "docs/workstreams/ios-app-shell.md"
    Issue = "docs/github_issues/07-ios-shell.md"
    Prompt = "docs/codex_workers/mobile-ios-shell.txt"
    Scope = "iOS app shell and native mobile wrapper path"
  },
  [pscustomobject]@{
    Branch = "infra/remote-signaling"
    Folder = "infra-remote-signaling"
    Brief = "docs/workstreams/remote-networking-and-relay.md"
    Issue = "docs/github_issues/08-remote-signaling-turn.md"
    Prompt = "docs/codex_workers/infra-remote-signaling.txt"
    Scope = "Paid remote access signaling, relay/TURN cost model, feature flags"
  },
  [pscustomobject]@{
    Branch = "host/native-capture-spike"
    Folder = "host-native-capture-spike"
    Brief = "docs/workstreams/native-capture-and-video-performance.md"
    Issue = "docs/github_issues/09-native-capture-spike.md"
    Prompt = "docs/codex_workers/host-native-capture-spike.txt"
    Scope = "Native capture/video performance spike behind flags"
  },
  [pscustomobject]@{
    Branch = "product/billing-store-readiness"
    Folder = "product-billing-store-readiness"
    Brief = "docs/workstreams/product-billing-store-support.md"
    Issue = "docs/github_issues/10-product-billing-store-support.md"
    Prompt = "docs/codex_workers/product-billing-store-readiness.txt"
    Scope = "Pricing, billing, app store readiness, support and release policy"
  }
)

Write-Host "Remote Controller multi-Codex worktree launch"
Write-Host ""
Write-PlanLine "Repo root:" $Root
Write-PlanLine "Base dir:" $BaseDir
Write-PlanLine "Start point:" $StartPoint
Write-PlanLine "Mode:" ($(if ($Apply) { "APPLY" } else { "DRY RUN" }))
Write-Host ""

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  throw "Git was not found on PATH."
}

if (-not (Test-Path -LiteralPath (Join-Path $Root ".git"))) {
  throw "No .git folder found at $Root. Create the private GitHub repo baseline first."
}

$headExists = $false
try {
  git -C $Root rev-parse --verify HEAD *> $null
  $headExists = $true
} catch {
  $headExists = $false
}

if (-not $headExists) {
  Write-Warning "This repo has no commit yet. Complete docs/GITHUB_CREATOR_HANDOFF.md before applying worktrees."
}

try {
  git -C $Root rev-parse --verify $StartPoint *> $null
} catch {
  Write-Warning "Start point '$StartPoint' was not verified locally. If this is a fresh repo, push/fetch main or use the baseline tag."
}

Write-Host "Planned worktrees:"
Write-Host ""

foreach ($stream in $workstreams) {
  $target = Join-Path $BaseDir $stream.Folder
  $branchExists = $false
  try {
    git -C $Root rev-parse --verify $stream.Branch *> $null
    $branchExists = $true
  } catch {
    $branchExists = $false
  }

  $commandText = if ($branchExists) {
    "git -C `"$Root`" worktree add `"$target`" `"$($stream.Branch)`""
  } else {
    "git -C `"$Root`" worktree add `"$target`" -b `"$($stream.Branch)`" `"$StartPoint`""
  }

  [pscustomobject]@{
    Branch = $stream.Branch
    Folder = $target
    Brief = $stream.Brief
    Issue = $stream.Issue
    Prompt = $stream.Prompt
    Scope = $stream.Scope
    Command = $commandText
  } | Format-List

  if ($Apply) {
    if (-not $headExists) {
      throw "Cannot apply worktrees before the baseline commit exists."
    }

    if (Test-Path -LiteralPath $target) {
      Write-Warning "Skipping existing folder: $target"
      continue
    }

    New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null

    if ($branchExists) {
      git -C $Root worktree add $target $stream.Branch
    } else {
      git -C $Root worktree add $target -b $stream.Branch $StartPoint
    }

    $promptSource = Join-Path $Root $stream.Prompt
    if (Test-Path -LiteralPath $promptSource) {
      Copy-Item -LiteralPath $promptSource -Destination (Join-Path $target "CODEX_START_HERE.txt") -Force
    }
  }
}

Write-Host ""
if ($Apply) {
  Write-Host "Done. Open each worktree folder in a separate Codex instance and paste CODEX_START_HERE.txt."
} else {
  Write-Host "Dry run only. Re-run with -Apply after the GitHub baseline commit and tag exist."
}
