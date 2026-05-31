param(
  [ValidateSet("same-wifi", "tailscale")]
  [string]$Gate = "same-wifi",
  [string]$EvidencePath = "",
  [string]$Label = "phone-screenshot",
  [string]$Notes = "",
  [string]$OutputDir = "output\acceptance",
  [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$ResolvedOutputDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $Root $OutputDir }
$AllowedExtensions = @(".png", ".jpg", ".jpeg", ".webp", ".heic", ".heif")

function ConvertTo-SafeName {
  param([string]$Value)
  $safe = "$Value".Trim().ToLowerInvariant() -replace "[^a-z0-9._-]+", "-"
  $safe = $safe.Trim("-")
  if ([string]::IsNullOrWhiteSpace($safe)) { return "phone-evidence" }
  return $safe
}

function New-PhoneEvidenceAttachment {
  param(
    [string]$SelectedGate,
    [string]$SourcePath,
    [string]$SelectedLabel,
    [string]$SelectedNotes
  )

  if ([string]::IsNullOrWhiteSpace($SourcePath)) {
    throw "EvidencePath is required. Provide a phone screenshot/photo path."
  }

  $resolvedSource = Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop
  $sourceItem = Get-Item -LiteralPath $resolvedSource
  if ($sourceItem.PSIsContainer) {
    throw "EvidencePath must be a file, not a directory."
  }

  $extension = $sourceItem.Extension.ToLowerInvariant()
  if ($AllowedExtensions -notcontains $extension) {
    throw "Unsupported evidence file extension '$extension'. Allowed: $($AllowedExtensions -join ', ')."
  }

  New-Item -ItemType Directory -Path $ResolvedOutputDir -Force | Out-Null
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $safeLabel = ConvertTo-SafeName $SelectedLabel
  $destName = "phone-evidence-$SelectedGate-$timestamp-$safeLabel$extension"
  $destPath = Join-Path $ResolvedOutputDir $destName
  Copy-Item -LiteralPath $sourceItem.FullName -Destination $destPath -Force
  $hash = Get-FileHash -LiteralPath $destPath -Algorithm SHA256
  $copiedItem = Get-Item -LiteralPath $destPath

  $jsonPath = Join-Path $ResolvedOutputDir "phone-evidence-$SelectedGate-$timestamp.json"
  $latestJsonPath = Join-Path $ResolvedOutputDir "phone-evidence-$SelectedGate-latest.json"
  $record = [pscustomobject]@{
    ok = $true
    gate = $SelectedGate
    label = $safeLabel
    originalName = $sourceItem.Name
    sourcePath = $sourceItem.FullName
    copiedPath = $destPath
    extension = $extension
    bytes = $copiedItem.Length
    sha256 = $hash.Hash
    notes = $SelectedNotes
    capturedBy = "operator-attached"
    createdAt = (Get-Date).ToString("o")
    doesNotReplaceVerifier = $true
    verifierReminder = "Run npm run acceptance:verify:save -- -Gate $SelectedGate after the physical phone checklist and Mark Proof step pass."
    recordJsonPath = $jsonPath
    latestRecordJsonPath = $latestJsonPath
  }

  $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $latestJsonPath -Encoding UTF8
  return $record
}

if ($SelfTest) {
  $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "remote-phone-evidence-$([guid]::NewGuid().ToString('N'))"
  $tempOutput = Join-Path $tempRoot "out"
  New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
  $samplePath = Join-Path $tempRoot "phone shot.PNG"
  [byte[]](137,80,78,71,13,10,26,10,0,0,0,0) | Set-Content -LiteralPath $samplePath -Encoding Byte
  $oldOutput = $script:ResolvedOutputDir
  $script:ResolvedOutputDir = $tempOutput
  try {
    $record = New-PhoneEvidenceAttachment -SelectedGate "same-wifi" -SourcePath $samplePath -SelectedLabel "My Proof Shot!" -SelectedNotes "self-test"
    $ok = $record.ok -and
      $record.gate -eq "same-wifi" -and
      $record.label -eq "my-proof-shot" -and
      $record.doesNotReplaceVerifier -eq $true -and
      (Test-Path -LiteralPath $record.copiedPath) -and
      (Test-Path -LiteralPath $record.recordJsonPath) -and
      (Test-Path -LiteralPath $record.latestRecordJsonPath) -and
      -not [string]::IsNullOrWhiteSpace($record.sha256)
    [pscustomobject]@{
      ok = $ok
      writesRecord = Test-Path -LiteralPath $record.recordJsonPath
      copiesEvidence = Test-Path -LiteralPath $record.copiedPath
      doesNotReplaceVerifier = $record.doesNotReplaceVerifier
    } | ConvertTo-Json -Compress
    if (-not $ok) { exit 1 }
    exit 0
  } finally {
    $script:ResolvedOutputDir = $oldOutput
  }
}

$attachment = New-PhoneEvidenceAttachment -SelectedGate $Gate -SourcePath $EvidencePath -SelectedLabel $Label -SelectedNotes $Notes
$attachment | ConvertTo-Json -Depth 8 -Compress
