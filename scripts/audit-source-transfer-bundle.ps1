param(
  [string]$ZipPath = (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) "dist") "RemoteController-SourceTransfer.zip"),
  [string]$HashPath = "$ZipPath.sha256"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ZipPath)) {
  [pscustomobject]@{
    status = "missing"
    zipPath = [System.IO.Path]::GetFullPath($ZipPath)
    hashPath = [System.IO.Path]::GetFullPath($HashPath)
    message = "The source transfer zip is not present in this checkout. This is expected in a fresh clone because dist is intentionally ignored."
    nextAction = "Package or copy dist\RemoteController-SourceTransfer.zip and its .sha256 sidecar before running the cleanliness audit."
    missingRequiredCount = $null
    forbiddenCount = $null
    sidecarMatches = $false
  } | ConvertTo-Json -Depth 4
  exit 1
}

Add-Type -AssemblyName System.IO.Compression.FileSystem

$requiredSuffixes = @(
  ".gitattributes",
  ".gitignore",
  ".github/workflows/ci.yml",
  "README.md",
  "MILESTONE_STATUS.md",
  "package.json",
  "package-lock.json",
  "docs/GITHUB_READY_CHECKLIST.md",
  "docs/GITHUB_CREATOR_HANDOFF.md",
  "docs/FIRST_CODEX_GITHUB_PROMPT.txt",
  "docs/TRANSFER_MANIFEST.md",
  "docs/GITHUB_MIGRATION_AND_PARALLEL_CODEX.md",
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
  "docs/interfaces/README.md",
  "docs/workstreams/README.md",
  "scripts/create-source-transfer-bundle.ps1",
  "scripts/audit-source-transfer-bundle.ps1",
  "scripts/audit-github-handoff.ps1",
  "scripts/bootstrap-github-baseline.ps1",
  "scripts/github-create-labels-milestones-issues.ps1",
  "scripts/create-codex-worktrees.ps1",
  "scripts/verify-user-computer-setup.ps1",
  "packaging/local-wifi/package-local-wifi.ps1",
  "packaging/local-wifi/Start Remote Controller.bat",
  "packaging/local-wifi/Stop Remote Controller.bat",
  "packaging/local-wifi/start-local-wifi.ps1",
  "packaging/local-wifi/stop-local-wifi.ps1",
  "packaging/local-wifi/smoke-local-wifi.ps1",
  "packaging/local-wifi/README-FIRST.txt",
  "packaging/local-wifi/QUICK-START-DAD.txt",
  "packaging/local-wifi/START-HERE-FRESH-INSTALL.txt",
  "src/server.js",
  "public/app.js",
  "public/host.js",
  "public/capture.js",
  "test/protocol.test.js",
  "test/settings-store.test.js",
  "test/session-store.test.js",
  "test/coordinate-mapper.test.js",
  "test/input-adapter.test.js",
  "test/rtc-room.test.js",
  "test/capture-adapter.test.js",
  "test/github-migration-contracts.test.js",
  "test/local-wifi-packaging.test.js"
)

$forbiddenPatterns = @(
  "(^|[\\/])node_modules([\\/]|$)",
  "(^|[\\/])data([\\/]|$)",
  "(^|[\\/])dist([\\/]|$)",
  "(^|[\\/])output([\\/]|$)",
  "\.log$",
  "\.pid$",
  "\.pyc$",
  "\.disabled$",
  "\.disabled-by-incident-response$",
  "(^|[\\/])__pycache__([\\/]|$)",
  "(^|[\\/])trusted-devices?([\\/\.]|$)",
  "(^|[\\/])host-key([\\/\.]|$)",
  "(^|[\\/])proof([\\/]|$)"
)

$archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ZipPath))
try {
  $names = $archive.Entries |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_.FullName) } |
    ForEach-Object { $_.FullName.Replace("\", "/") }
} finally {
  $archive.Dispose()
}

$missingRequired = foreach ($suffix in $requiredSuffixes) {
  $normalized = $suffix.Replace("\", "/")
  if (-not ($names | Where-Object { $_ -eq $normalized -or $_.EndsWith("/$normalized") })) {
    $suffix
  }
}

$forbidden = foreach ($name in $names) {
  foreach ($pattern in $forbiddenPatterns) {
    if ($name -match $pattern) {
      $name
      break
    }
  }
}

$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $ZipPath
$sidecarHash = $null
if (Test-Path -LiteralPath $HashPath) {
  $line = Get-Content -LiteralPath $HashPath -TotalCount 1
  if ($line -match "^\s*([A-Fa-f0-9]{64})\s+") {
    $sidecarHash = $Matches[1].ToUpperInvariant()
  }
}

$result = [pscustomobject]@{
  status = if (($missingRequired | Measure-Object).Count -eq 0 -and ($forbidden | Sort-Object -Unique | Measure-Object).Count -eq 0 -and $sidecarHash -eq $hash.Hash) { "pass" } else { "fail" }
  zipPath = (Resolve-Path -LiteralPath $ZipPath).Path
  entryCount = ($names | Measure-Object).Count
  sha256 = $hash.Hash
  sidecarHash = $sidecarHash
  sidecarMatches = if ($sidecarHash) { $sidecarHash -eq $hash.Hash } else { $false }
  missingRequiredCount = ($missingRequired | Measure-Object).Count
  missingRequired = @($missingRequired)
  forbiddenCount = ($forbidden | Sort-Object -Unique | Measure-Object).Count
  forbidden = @($forbidden | Sort-Object -Unique)
}

$result | ConvertTo-Json -Depth 4

if ($result.missingRequiredCount -gt 0 -or $result.forbiddenCount -gt 0 -or -not $result.sidecarMatches) {
  exit 1
}
