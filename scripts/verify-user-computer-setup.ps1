param(
  [switch]$Apply
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$OutDir = Join-Path $Root "output\user-computer-setup"
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$Report = Join-Path $OutDir "setup-$Stamp.txt"

function Add-Line {
  param([string]$Line)
  Write-Host $Line
  Add-Content -LiteralPath $Report -Value $Line
}

function Test-CommandAvailable {
  param([string]$Name)
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if ($cmd) {
    Add-Line "OK command $Name => $($cmd.Source)"
    return $true
  }
  Add-Line "MISSING command $Name"
  return $false
}

function Run-Step {
  param(
    [string]$Name,
    [string]$Command
  )
  Add-Line ""
  Add-Line "STEP $Name"
  Add-Line "> $Command"
  if (-not $Apply) {
    Add-Line "DRY RUN skipped. Re-run with -Apply to execute."
    return
  }
  $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = "cmd.exe"
  $startInfo.Arguments = "/d /s /c ""$Command"""
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $process = [System.Diagnostics.Process]::Start($startInfo)
  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  $commandOutput = @()
  if (-not [string]::IsNullOrWhiteSpace($stdout)) { $commandOutput += ($stdout -split "`r?`n") }
  if (-not [string]::IsNullOrWhiteSpace($stderr)) { $commandOutput += ($stderr -split "`r?`n") }
  foreach ($line in ($commandOutput | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
    Add-Line ("  " + $line.ToString())
  }
  if ($process.ExitCode -eq 0) {
    Add-Line "OK $Name"
  } else {
    Add-Line "FAIL $Name"
    throw "Step '$Name' exited with code $($process.ExitCode)."
  }
}

try {
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
} catch {
  $OutDir = Join-Path ([System.IO.Path]::GetTempPath()) "remote-controller-user-computer-setup"
  $Report = Join-Path $OutDir "setup-$Stamp.txt"
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
}
Set-Content -LiteralPath $Report -Value "Remote Controller user computer setup verification $Stamp"

Push-Location $Root
try {
  Add-Line "Root: $Root"
  Add-Line "Mode: $(if ($Apply) { 'APPLY' } else { 'DRY RUN' })"

  Add-Line ""
  Add-Line "Required files"
  $required = @(
    "package.json",
    "package-lock.json",
    "src\server.js",
    "public\app.js",
    "public\host.js",
    "public\capture.js",
    "docs\FIRST_CODEX_GITHUB_PROMPT.txt",
    "docs\GITHUB_CREATOR_HANDOFF.md",
    "docs\GOAL_STATUS_LEDGER.md",
    "docs\TRANSFER_MANIFEST.md",
    "docs\interfaces\README.md",
    "docs\workstreams\README.md",
    "docs\github_issues\01-baseline-repo-and-tag.md"
  )
  foreach ($file in $required) {
    if (Test-Path -LiteralPath (Join-Path $Root $file)) {
      Add-Line "OK file $file"
    } else {
      Add-Line "MISSING file $file"
    }
  }

  Add-Line ""
  Add-Line "Commands"
  $nodeOk = Test-CommandAvailable "node"
  $npmCommand = "npm"
  $npmCmd = Get-Command "npm.cmd" -ErrorAction SilentlyContinue
  if ($npmCmd) {
    Add-Line "OK command npm.cmd => $($npmCmd.Source)"
    $npmCommand = "npm.cmd"
    $npmOk = $true
  } else {
    $npmOk = Test-CommandAvailable "npm"
  }
  $gitOk = Test-CommandAvailable "git"
  Test-CommandAvailable "gh" | Out-Null

  if ($nodeOk) { Run-Step "node version" "node --version" }
  if ($npmOk) { Run-Step "npm version" "$npmCommand --version" }
  if ($gitOk) { Run-Step "git version" "git --version" }

  if ($npmOk) {
    Run-Step "install dependencies" "$npmCommand ci"
  }
  if ($nodeOk) {
    Run-Step "syntax server" "node --check src\server.js"
    Run-Step "syntax app" "node --check public\app.js"
    Run-Step "syntax host" "node --check public\host.js"
    Run-Step "syntax capture" "node --check public\capture.js"
    Run-Step "protected tests" "node --test test\protocol.test.js test\settings-store.test.js test\session-store.test.js test\coordinate-mapper.test.js test\input-adapter.test.js test\rtc-room.test.js test\capture-adapter.test.js"
  }

  Add-Line ""
  Add-Line "Next manual host check:"
  Add-Line '$env:HOST_KEY=''dev-host-key'''
  Add-Line "npm start"
  Add-Line "Open http://127.0.0.1:4317/host?key=dev-host-key"

  Add-Line ""
  Add-Line "Report: $Report"
} finally {
  Pop-Location
}
