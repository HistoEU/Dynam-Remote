param(
  [string]$OutputDir = (Join-Path (Split-Path -Parent $PSScriptRoot) "dist"),
  [string]$Name = "RemoteController-SourceTransfer"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Stage = Join-Path $OutputDir $Name
$Zip = Join-Path $OutputDir "$Name.zip"

if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Stage | Out-Null
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$items = @(
  ".github",
  ".gitattributes",
  ".gitignore",
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

foreach ($item in $items) {
  $source = Join-Path $Root $item
  if (Test-Path -LiteralPath $source) {
    Copy-Item -LiteralPath $source -Destination (Join-Path $Stage $item) -Recurse -Force
  }
}

Get-ChildItem -LiteralPath $Stage -Recurse -Force |
  Where-Object {
    $_.Name -like "*.disabled" -or
    $_.Name -like "*.disabled-by-incident-response" -or
    $_.Name -eq "__pycache__" -or
    $_.Name -like "*.pyc" -or
    $_.Name -like "*.log" -or
    $_.Name -like "*.pid"
  } |
  Remove-Item -Recurse -Force

Set-Content -LiteralPath (Join-Path $Stage "TRANSFER_BUNDLE_README.txt") -Value @"
Remote Controller source transfer bundle.

This bundle is source-only. It intentionally excludes node_modules, runtime data, logs, smoke output, local keys, and generated package extractions.

After unpacking on the new computer:
1. Install Node.js 20 or newer.
2. Run: npm ci
3. Run the tests listed in docs\TRANSFER_MANIFEST.md.
4. Start the host with: `$env:HOST_KEY='dev-host-key'; npm start
"@

if (Test-Path -LiteralPath $Zip) { Remove-Item -LiteralPath $Zip -Force }
Compress-Archive -LiteralPath $Stage -DestinationPath $Zip -Force
$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $Zip
$HashSidecar = "$Zip.sha256"
Set-Content -LiteralPath $HashSidecar -Value "$($hash.Hash)  $(Split-Path -Leaf $Zip)"
[pscustomobject]@{
  zipPath = $Zip
  hashPath = $HashSidecar
  stagingPath = $Stage
  sha256 = $hash.Hash
  sizeMB = [math]::Round((Get-Item -LiteralPath $Zip).Length / 1MB, 2)
} | ConvertTo-Json
