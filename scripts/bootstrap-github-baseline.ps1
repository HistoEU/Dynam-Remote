param(
  [string]$RemoteUrl = "",
  [switch]$Apply
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$SourceItems = @(
  ".gitignore",
  ".gitattributes",
  ".github",
  "docs",
  "packaging",
  "public",
  "scripts",
  "src",
  "test",
  "README.md",
  "MILESTONE_STATUS.md",
  "package.json",
  "package-lock.json"
)
$CommitMessage = "baseline: local wifi controller v76 planning handoff"
$Tag = "v0.1-local-wifi-baseline-v76"

function Invoke-Step {
  param([string]$Command)
  if ($Apply) {
    Write-Host "> $Command"
    Invoke-Expression $Command
  } else {
    Write-Host $Command
  }
}

Push-Location $Root
try {
  if (-not $Apply) {
    Write-Host "Dry run. Re-run with -Apply to initialize, stage, commit, tag, and optionally push."
    Write-Host ""
  }

  Invoke-Step "git init"
  Invoke-Step "git status --ignored"

  $quoted = $SourceItems | ForEach-Object { '"' + $_ + '"' }
  Invoke-Step ("git add " + ($quoted -join " "))
  Invoke-Step "git diff --cached --name-only"
  Invoke-Step "git commit -m `"$CommitMessage`""
  Invoke-Step "git tag $Tag"

  if ($RemoteUrl) {
    Invoke-Step "git remote add origin `"$RemoteUrl`""
    Invoke-Step "git branch -M main"
    Invoke-Step "git push -u origin main"
    Invoke-Step "git push origin $Tag"
  } else {
    Write-Host ""
    Write-Host "No remote URL was provided. After creating the private GitHub repo, run:"
    Write-Host "git remote add origin <PRIVATE_GITHUB_REPO_URL>"
    Write-Host "git branch -M main"
    Write-Host "git push -u origin main"
    Write-Host "git push origin $Tag"
  }
} finally {
  Pop-Location
}
