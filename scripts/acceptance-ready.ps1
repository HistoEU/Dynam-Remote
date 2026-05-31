param(
  [ValidateSet("same-wifi", "tailscale")]
  [string]$Gate = "same-wifi",
  [string]$OutputDir = "output\acceptance",
  [switch]$NoOpen,
  [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$ResolvedOutputDir = Join-Path $Root $OutputDir
$PrepareScript = Join-Path $PSScriptRoot "prepare-phone-acceptance.ps1"
$WatchScript = Join-Path $PSScriptRoot "watch-phone-acceptance.ps1"

function Invoke-JsonScript {
  param(
    [string]$Path,
    [string[]]$Arguments
  )

  $tempPrefix = Join-Path ([System.IO.Path]::GetTempPath()) "remote-acceptance-ready-$([guid]::NewGuid().ToString('N'))"
  $stdoutPath = "$tempPrefix.out"
  $stderrPath = "$tempPrefix.err"
  $argumentList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $Path) + @($Arguments)
  $process = Start-Process -FilePath "powershell" -ArgumentList $argumentList -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -NoNewWindow -PassThru -Wait
  $exitCode = $process.ExitCode
  $raw = @()
  if (Test-Path -LiteralPath $stdoutPath) {
    $raw += @(Get-Content -LiteralPath $stdoutPath -ErrorAction SilentlyContinue)
  }
  if (Test-Path -LiteralPath $stderrPath) {
    $raw += @(Get-Content -LiteralPath $stderrPath -ErrorAction SilentlyContinue)
  }
  Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
  $jsonLine = @($raw | Where-Object { "$_".Trim().StartsWith("{") }) | Select-Object -Last 1
  $parsed = $null
  if ($jsonLine) {
    try {
      $parsed = $jsonLine | ConvertFrom-Json
    } catch {
      $parsed = $null
    }
  }

  return [pscustomobject]@{
    exitCode = $exitCode
    parsed = $parsed
    raw = @($raw | ForEach-Object { "$_" })
  }
}

function Resolve-ArtifactPath {
  param([string]$PathValue)
  if (-not $PathValue) { return "" }
  if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
  return Join-Path $Root $PathValue
}

function Read-JsonFile {
  param([string]$PathValue)
  if (-not $PathValue -or -not (Test-Path -LiteralPath $PathValue)) { return $null }
  return Get-Content -Raw -LiteralPath $PathValue | ConvertFrom-Json
}

function ConvertTo-StringArray {
  param([object]$Values)
  if ($null -eq $Values) { return @() }
  return @($Values | Where-Object { $null -ne $_ } | ForEach-Object { "$_" })
}

function ConvertTo-ReadyIssue {
  param(
    [string]$Prefix,
    [object]$Issue
  )

  $name = if ($Prefix) { "$Prefix`: $($Issue.name)" } else { "$($Issue.name)" }
  return [pscustomobject]@{
    name = $name
    detail = "$($Issue.detail)"
    nextAction = "$($Issue.nextAction)"
  }
}

function Get-ReadinessStatus {
  param(
    [bool]$PreparedOk,
    [bool]$EvidencePassed,
    [int]$PhoneUrlCount,
    [int]$PrepareFailuresCount,
    [int]$ReadyActionsCount
  )

  if ($EvidencePassed) { return "complete" }
  if ($PreparedOk -and $PhoneUrlCount -gt 0 -and $PrepareFailuresCount -eq 0) { return "ready-for-phone" }
  if ($PhoneUrlCount -eq 0 -or $PrepareFailuresCount -gt 0 -or $ReadyActionsCount -gt 0) { return "setup-needed" }
  return "needs-attention"
}

function Invoke-PrepareSession {
  $startedAt = Get-Date
  $argumentList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PrepareScript, "-Gate", $Gate, "-OutputDir", $OutputDir)
  $process = Start-Process -FilePath "powershell" -ArgumentList $argumentList -WindowStyle Hidden -PassThru
  $latestPath = Join-Path $ResolvedOutputDir "phone-acceptance-session-$Gate-latest.json"
  $parsed = $null
  $deadline = (Get-Date).AddSeconds(60)

  do {
    if (Test-Path -LiteralPath $latestPath) {
      $file = Get-Item -LiteralPath $latestPath
      if ($file.LastWriteTime -ge $startedAt.AddSeconds(-2)) {
        $parsed = Read-JsonFile -PathValue $latestPath
        if ($parsed -and $parsed.gate -eq $Gate) { break }
      }
    }

    if ($process.HasExited -and -not $parsed) { break }
    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)

  if (-not $process.HasExited -and $parsed) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
  }

  $exitCode = if ($parsed -and $parsed.ok -eq $true) {
    0
  } elseif ($process.HasExited) {
    $process.ExitCode
  } else {
    124
  }

  return [pscustomobject]@{
    exitCode = $exitCode
    parsed = $parsed
    raw = @()
  }
}

function Save-ReadyStatus {
  param([object]$Status)

  New-Item -ItemType Directory -Path $ResolvedOutputDir -Force | Out-Null
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $path = Join-Path $ResolvedOutputDir "phone-acceptance-ready-$Gate-$timestamp.json"
  $latestPath = Join-Path $ResolvedOutputDir "phone-acceptance-ready-$Gate-latest.json"
  $Status | Add-Member -NotePropertyName readyStatusPath -NotePropertyValue $path -Force
  $Status | Add-Member -NotePropertyName latestReadyStatusPath -NotePropertyValue $latestPath -Force
  $Status | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding UTF8
  $Status | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $latestPath -Encoding UTF8
}

if ($SelfTest) {
  $prepareSelfTest = Invoke-JsonScript -Path $PrepareScript -Arguments @("-SelfTest", "-Gate", $Gate, "-OutputDir", $OutputDir)
  $watchSelfTest = Invoke-JsonScript -Path $WatchScript -Arguments @("-SelfTest", "-Gate", $Gate, "-OutputDir", $OutputDir)
  $scriptText = Get-Content -Raw -LiteralPath $PSCommandPath
  $ok = (Test-Path -LiteralPath $PrepareScript) -and
    (Test-Path -LiteralPath $WatchScript) -and
    ($prepareSelfTest.exitCode -eq 0) -and
    ($watchSelfTest.exitCode -eq 0) -and
    $prepareSelfTest.parsed -and
    $watchSelfTest.parsed -and
    ($prepareSelfTest.parsed.ok -eq $true) -and
    ($watchSelfTest.parsed.ok -eq $true) -and
    (Get-ReadinessStatus -PreparedOk $true -EvidencePassed $false -PhoneUrlCount 1 -PrepareFailuresCount 0 -ReadyActionsCount 0) -eq "ready-for-phone" -and
    (Get-ReadinessStatus -PreparedOk $false -EvidencePassed $false -PhoneUrlCount 0 -PrepareFailuresCount 1 -ReadyActionsCount 1) -eq "setup-needed" -and
    (Get-ReadinessStatus -PreparedOk $true -EvidencePassed $true -PhoneUrlCount 1 -PrepareFailuresCount 0 -ReadyActionsCount 0) -eq "complete" -and
    ($scriptText -match "preliminaryStatus") -and
    ($scriptText -like '*Save-ReadyStatus -Status $preliminaryStatus*')

  [pscustomobject]@{
    ok = $ok
    gate = $Gate
    prepareExists = Test-Path -LiteralPath $PrepareScript
    watchExists = Test-Path -LiteralPath $WatchScript
    prepareSelfTestOk = if ($prepareSelfTest.parsed) { $prepareSelfTest.parsed.ok } else { $false }
    watchSelfTestOk = if ($watchSelfTest.parsed) { $watchSelfTest.parsed.ok } else { $false }
    opensRunCardByDefault = $true
    supportsNoOpen = $true
    savesReadyStatus = $true
    keepsEmptyUrlListsAsArrays = $true
    includesPrepareFailures = $true
    includesNormalizedStatus = $true
    includesPrimaryPhoneUrl = $true
    savesPreliminaryStatusBeforeWatch = $true
  } | ConvertTo-Json -Compress
  if (-not $ok) { exit 1 }
  exit 0
}

$prepare = Invoke-PrepareSession
$prepared = $prepare.parsed
$runCardHtml = ""
$openedRunCard = $false
$openError = ""

if ($prepared -and $prepared.runCardHtml) {
  $runCardHtml = Resolve-ArtifactPath "$($prepared.runCardHtml)"
}

if (-not $NoOpen -and $runCardHtml -and (Test-Path -LiteralPath $runCardHtml)) {
  try {
    Start-Process -FilePath $runCardHtml
    $openedRunCard = $true
  } catch {
    $openError = $_.Exception.Message
  }
}

$prepareFailures = @()
if ($prepared -and $prepared.failures) {
  $prepareFailures = @($prepared.failures | ForEach-Object { ConvertTo-ReadyIssue -Prefix "prepare" -Issue $_ })
}

$prepareWarnings = @()
if ($prepared -and $prepared.warnings) {
  $prepareWarnings = @($prepared.warnings | ForEach-Object { ConvertTo-ReadyIssue -Prefix "warning" -Issue $_ })
}

$phoneUrls = if ($prepared) { @(ConvertTo-StringArray $prepared.phoneUrls) } else { @() }
$secondaryPhoneUrls = if ($prepared) { @(ConvertTo-StringArray $prepared.secondaryPhoneUrls) } else { @() }
$preparedOk = $prepare.exitCode -eq 0
$phoneUrlList = @($phoneUrls)
$primaryPhoneUrl = if ($phoneUrlList.Count -gt 0) { "$($phoneUrlList[0])" } else { "" }
$preliminaryReadyActions = @($prepareFailures | Where-Object { -not [string]::IsNullOrWhiteSpace($_.nextAction) } | ForEach-Object { $_.nextAction } | Select-Object -Unique)
$preliminaryReadinessStatus = Get-ReadinessStatus `
  -PreparedOk $preparedOk `
  -EvidencePassed $false `
  -PhoneUrlCount $phoneUrlList.Count `
  -PrepareFailuresCount (@($prepareFailures).Count) `
  -ReadyActionsCount (@($preliminaryReadyActions).Count)

$preliminaryStatus = [pscustomobject]@{
  ok = $preparedOk
  evidencePassed = $false
  status = $preliminaryReadinessStatus
  gate = $Gate
  checkedAt = (Get-Date).ToString("o")
  openedRunCard = $openedRunCard
  openError = $openError
  runCardHtml = $runCardHtml
  runCardMarkdown = if ($prepared -and $prepared.runCardMarkdown) { Resolve-ArtifactPath "$($prepared.runCardMarkdown)" } else { "" }
  hostConsole = if ($prepared) { "$($prepared.hostConsole)" } else { "" }
  primaryPhoneUrl = $primaryPhoneUrl
  phoneUrls = @($phoneUrls)
  secondaryPhoneUrls = @($secondaryPhoneUrls)
  nextCommand = if ($prepared) { "$($prepared.nextCommand)" } else { "npm run acceptance:prepare -- -Gate $Gate" }
  stopCommand = if ($prepared) { "$($prepared.stopCommand)" } else { "npm run acceptance:stop -- -Gate $Gate" }
  preparedSessionPath = ""
  hostHealth = $null
  prepareFailures = @($prepareFailures)
  prepareWarnings = @($prepareWarnings)
  failedChecks = @($prepareFailures)
  setupBlockerCount = @($prepareFailures).Count
  physicalBlockerCount = 0
  readyActions = @($preliminaryReadyActions)
  prepareExitCode = $prepare.exitCode
  watchExitCode = -1
  preliminary = $true
}

Save-ReadyStatus -Status $preliminaryStatus

$watch = Invoke-JsonScript -Path $WatchScript -Arguments @("-Gate", $Gate, "-OutputDir", $OutputDir, "-Once", "-Save")
$watchResult = $watch.parsed

$watchFailedChecks = @()
if ($watchResult -and $watchResult.failedChecks) {
  $watchFailedChecks = @($watchResult.failedChecks | ForEach-Object {
    [pscustomobject]@{
      name = "$($_.name)"
      detail = "$($_.detail)"
      nextAction = "$($_.nextAction)"
    }
  })
} elseif ($prepare.exitCode -ne 0) {
  $watchFailedChecks = @([pscustomobject]@{
    name = "prepare failed"
    detail = (($prepare.raw -join " ") -replace "\s+", " ").Trim()
    nextAction = "Run npm run acceptance:prepare -- -Gate $Gate and fix the first prepare failure before running phone acceptance."
  })
}

$failedChecks = @($prepareFailures + $watchFailedChecks)
$readyActions = @($failedChecks | Where-Object { -not [string]::IsNullOrWhiteSpace($_.nextAction) } | ForEach-Object { $_.nextAction } | Select-Object -Unique)
$evidencePassed = ($watch.exitCode -eq 0) -and $watchResult -and $watchResult.ok -eq $true
$readinessStatus = Get-ReadinessStatus `
  -PreparedOk $preparedOk `
  -EvidencePassed $evidencePassed `
  -PhoneUrlCount $phoneUrlList.Count `
  -PrepareFailuresCount (@($prepareFailures).Count) `
  -ReadyActionsCount (@($readyActions).Count)

$status = [pscustomobject]@{
  ok = $preparedOk
  evidencePassed = $evidencePassed
  status = $readinessStatus
  gate = $Gate
  checkedAt = (Get-Date).ToString("o")
  openedRunCard = $openedRunCard
  openError = $openError
  runCardHtml = $runCardHtml
  runCardMarkdown = if ($prepared -and $prepared.runCardMarkdown) { Resolve-ArtifactPath "$($prepared.runCardMarkdown)" } else { "" }
  hostConsole = if ($prepared) { "$($prepared.hostConsole)" } else { "" }
  primaryPhoneUrl = $primaryPhoneUrl
  phoneUrls = @($phoneUrls)
  secondaryPhoneUrls = @($secondaryPhoneUrls)
  nextCommand = if ($prepared) { "$($prepared.nextCommand)" } else { "npm run acceptance:prepare -- -Gate $Gate" }
  stopCommand = if ($prepared) { "$($prepared.stopCommand)" } else { "npm run acceptance:stop -- -Gate $Gate" }
  preparedSessionPath = if ($watchResult) { "$($watchResult.preparedSessionPath)" } else { "" }
  hostHealth = if ($watchResult) { $watchResult.hostHealth } else { $null }
  prepareFailures = @($prepareFailures)
  prepareWarnings = @($prepareWarnings)
  failedChecks = @($failedChecks)
  setupBlockerCount = @($prepareFailures).Count
  physicalBlockerCount = @($watchFailedChecks).Count
  readyActions = @($readyActions)
  prepareExitCode = $prepare.exitCode
  watchExitCode = $watch.exitCode
}

Save-ReadyStatus -Status $status
$status | ConvertTo-Json -Depth 10 -Compress
if ($prepare.exitCode -ne 0) { exit 1 }
exit 0
