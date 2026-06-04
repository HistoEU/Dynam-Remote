param(
  [string]$OutputDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "dist"),
  [string]$PackageName = "DynamRemote-Brother-Test",
  [string]$NodePath = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Staging = Join-Path $OutputDir $PackageName
$ZipPath = Join-Path $OutputDir "$PackageName.zip"

function Copy-Directory {
  param(
    [string]$Source,
    [string]$Destination
  )
  if (-not (Test-Path -LiteralPath $Source)) {
    throw "Required path missing: $Source"
  }
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  & robocopy $Source $Destination /MIR /NFL /NDL /NJH /NJS /NP /R:2 /W:1 | Out-Null
  $exit = $LASTEXITCODE
  if ($exit -gt 7) {
    throw "robocopy failed copying $Source to $Destination with exit code $exit"
  }
}

function Get-NodeSource {
  param([string]$Requested)
  if ($Requested -and (Test-Path -LiteralPath $Requested)) { return $Requested }
  $cmd = Get-Command node -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  throw "Node was not found on this packaging machine."
}

if (Test-Path -LiteralPath $Staging) { Remove-Item -LiteralPath $Staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Staging | Out-Null
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$copyDirs = @("public", "src")
foreach ($dir in $copyDirs) {
  Copy-Directory -Source (Join-Path $Root $dir) -Destination (Join-Path $Staging $dir)
}

Copy-Item -LiteralPath (Join-Path $Root "package-lock.json") -Destination (Join-Path $Staging "package-lock.json") -Force
Copy-Item -LiteralPath (Join-Path $Root "README.md") -Destination (Join-Path $Staging "README-project.md") -Force -ErrorAction SilentlyContinue
Copy-Item -LiteralPath (Join-Path $Root "package.json") -Destination (Join-Path $Staging "package.source.json") -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "Start Remote Controller.bat") -Destination $Staging -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "START HERE - Remote Controller.bat") -Destination $Staging -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "Stop Remote Controller.bat") -Destination $Staging -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "OpenHostLink.bat") -Destination $Staging -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "README-FIRST.txt") -Destination $Staging -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "QUICK-START-DAD.txt") -Destination $Staging -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "START-HERE-FRESH-INSTALL.txt") -Destination $Staging -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "start-local-wifi.ps1") -Destination $Staging -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "stop-local-wifi.ps1") -Destination $Staging -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "smoke-local-wifi.ps1") -Destination $Staging -Force

$runtimeNodeDir = Join-Path $Staging "runtime\node"
New-Item -ItemType Directory -Force -Path $runtimeNodeDir | Out-Null
$resolvedNodePath = Get-NodeSource -Requested $NodePath
Copy-Item -LiteralPath $resolvedNodePath -Destination (Join-Path $runtimeNodeDir "node.exe") -Force

Copy-Directory -Source (Join-Path $Root "node_modules") -Destination (Join-Path $Staging "node_modules")

$rootPackage = Get-Content -Raw -LiteralPath (Join-Path $Root "package.json") | ConvertFrom-Json
$packageManifest = [ordered]@{
  name = "remote-controller-local-wifi"
  version = "$($rootPackage.version)"
  private = $true
  description = "Local Wi-Fi phone-to-laptop remote desktop controller package."
  type = "commonjs"
  scripts = [ordered]@{
    start = "powershell -NoProfile -ExecutionPolicy Bypass -File ./start-local-wifi.ps1"
    stop = "powershell -NoProfile -ExecutionPolicy Bypass -File ./stop-local-wifi.ps1"
    smoke = "powershell -NoProfile -ExecutionPolicy Bypass -File ./smoke-local-wifi.ps1"
  }
  engines = [ordered]@{
    node = ">=20"
  }
  dependencies = $rootPackage.dependencies
  bundledRuntime = [ordered]@{
    node = "runtime/node/node.exe"
    electron = "node_modules/electron/dist/electron.exe"
  }
}
$packageManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Staging "package.json") -Encoding UTF8

$packageInfo = [ordered]@{
  name = $PackageName
  generatedAt = (Get-Date).ToString("o")
  sourceRoot = $Root
  nodeSource = $resolvedNodePath
  launchFile = "START HERE - Remote Controller.bat"
  fallbackLaunchFile = "Start Remote Controller.bat"
  stopFile = "Stop Remote Controller.bat"
  captureEngine = "electron"
  notes = @(
    "Unzip the folder first.",
    "Double-click START HERE - Remote Controller.bat.",
    "Allow Windows Firewall on private networks if prompted.",
    "Use the phone URL and PIN printed in the launcher window."
  )
}
$packageInfo | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Staging "PACKAGE-INFO.json") -Encoding UTF8

if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
$compressed = $false
for ($attempt = 1; $attempt -le 5 -and -not $compressed; $attempt += 1) {
  try {
    if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force -ErrorAction SilentlyContinue }
    Compress-Archive -LiteralPath $Staging -DestinationPath $ZipPath -Force
    $compressed = $true
  } catch {
    if ($attempt -ge 5) { throw }
    Start-Sleep -Seconds (2 * $attempt)
  }
}

$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $ZipPath
[pscustomobject]@{
  ok = $true
  zipPath = $ZipPath
  stagingPath = $Staging
  sha256 = $hash.Hash
  sizeMB = [math]::Round((Get-Item -LiteralPath $ZipPath).Length / 1MB, 2)
} | ConvertTo-Json -Depth 4
