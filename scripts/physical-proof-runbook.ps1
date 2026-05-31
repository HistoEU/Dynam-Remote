param(
  [string]$OutputDir = "output\acceptance",
  [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$ResolvedOutputDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $Root $OutputDir }
$script:PinRefreshCache = @{}

function Read-JsonFile {
  param([string]$PathValue)
  if (-not $PathValue -or -not (Test-Path -LiteralPath $PathValue -PathType Leaf)) { return $null }
  try {
    return Get-Content -Raw -LiteralPath $PathValue | ConvertFrom-Json
  } catch {
    return $null
  }
}

function New-ArtifactRecord {
  param(
    [string]$Name,
    [string]$RelativePath
  )

  $path = Join-Path $ResolvedOutputDir $RelativePath
  $item = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
  return [pscustomobject]@{
    name = $Name
    relativePath = $RelativePath
    path = $path
    exists = [bool]$item
    bytes = if ($item) { [int64]$item.Length } else { 0 }
    lastWriteTime = if ($item) { $item.LastWriteTime.ToString("o") } else { "" }
  }
}

function ConvertTo-StringArray {
  param([object]$Values)
  if ($null -eq $Values) { return @() }
  return @($Values | Where-Object { $null -ne $_ } | ForEach-Object { "$_" })
}

function Get-GateRecord {
  param(
    [object]$Container,
    [string]$Gate
  )
  if (-not $Container -or -not $Container.gates) { return $null }
  return @($Container.gates | Where-Object { "$($_.gate)" -eq $Gate } | Select-Object -First 1)
}

function Get-QueryParam {
  param(
    [string]$Url,
    [string]$Name
  )
  if ([string]::IsNullOrWhiteSpace($Url)) { return "" }
  try {
    $uri = [System.Uri]$Url
    foreach ($pair in $uri.Query.TrimStart("?").Split("&", [System.StringSplitOptions]::RemoveEmptyEntries)) {
      $parts = $pair.Split("=", 2)
      if ($parts.Count -eq 2 -and [System.Uri]::UnescapeDataString($parts[0]) -eq $Name) {
        return [System.Uri]::UnescapeDataString($parts[1])
      }
    }
  } catch {
    return ""
  }
  return ""
}

function Invoke-CurrentPinRefresh {
  param([object]$Ready)
  $hostConsole = if ($Ready -and $Ready.hostConsole) { "$($Ready.hostConsole)" } else { "" }
  if ([string]::IsNullOrWhiteSpace($hostConsole)) { return $null }
  $hostKey = Get-QueryParam -Url $hostConsole -Name "key"
  if ([string]::IsNullOrWhiteSpace($hostKey)) { return $null }
  try {
    $uri = [System.Uri]$hostConsole
    $baseUrl = "$($uri.Scheme)://$($uri.Authority)"
    $cacheKey = "$baseUrl|$hostKey"
    if ($script:PinRefreshCache.ContainsKey($cacheKey)) {
      return $script:PinRefreshCache[$cacheKey]
    }
    $pin = Invoke-RestMethod -Uri "$baseUrl/api/refresh-pin" -Method Post -Headers @{ "x-host-key" = $hostKey } -Body "{}" -ContentType "application/json" -TimeoutSec 6
    if ($pin -and $pin.pin) {
      $summary = [pscustomobject]@{
        available = $true
        pin = "$($pin.pin)"
        secondsRemaining = if ($null -ne $pin.secondsRemaining) { [int]$pin.secondsRemaining } else { 0 }
        refreshedAt = (Get-Date).ToString("o")
        source = "host-refresh"
        error = ""
      }
      $script:PinRefreshCache[$cacheKey] = $summary
      return $summary
    }
  } catch {
    return $null
  }
  return $null
}

function Get-PinFallback {
  param(
    [object]$NextGate,
    [object]$Session
  )
  $nextPin = if ($NextGate) { $NextGate.currentPin } else { $null }
  if ($nextPin -and $nextPin.available -and $nextPin.pin) {
    return [pscustomobject]@{
      available = $true
      pin = "$($nextPin.pin)"
      secondsRemaining = if ($null -ne $nextPin.secondsRemaining) { [int]$nextPin.secondsRemaining } else { 0 }
      refreshedAt = "$($nextPin.refreshedAt)"
      source = "$($nextPin.source)"
      error = ""
    }
  }
  $sessionPin = if ($Session) { $Session.shortLivedPin } else { $null }
  if ($sessionPin -and $sessionPin.available -and $sessionPin.pin) {
    return [pscustomobject]@{
      available = $true
      pin = "$($sessionPin.pin)"
      secondsRemaining = if ($null -ne $sessionPin.secondsRemaining) { [int]$sessionPin.secondsRemaining } else { 0 }
      refreshedAt = "$($sessionPin.refreshedAt)"
      source = "prepared-session"
      error = ""
    }
  }
  return [pscustomobject]@{
    available = $false
    pin = ""
    secondsRemaining = 0
    refreshedAt = ""
    source = "unavailable"
    error = "No current PIN could be refreshed or found in the latest operator artifacts."
  }
}

function Get-GatePinSummary {
  param(
    [object]$Ready,
    [object]$NextGate,
    [object]$Session
  )
  $refreshed = Invoke-CurrentPinRefresh -Ready $Ready
  if ($refreshed) { return $refreshed }
  return Get-PinFallback -NextGate $NextGate -Session $Session
}

function New-GateRunbook {
  param(
    [string]$Gate,
    [object]$Next,
    [object]$Ready,
    [object]$Session
  )

  $nextGate = Get-GateRecord -Container $Next -Gate $Gate
  $phoneUrls = if ($nextGate) { ConvertTo-StringArray $nextGate.phoneUrls } elseif ($Ready) { ConvertTo-StringArray $Ready.phoneUrls } else { @() }
  $primaryPhoneUrl = if ($nextGate -and -not [string]::IsNullOrWhiteSpace("$($nextGate.primaryPhoneUrl)")) {
    "$($nextGate.primaryPhoneUrl)"
  } elseif ($Ready -and -not [string]::IsNullOrWhiteSpace("$($Ready.primaryPhoneUrl)")) {
    "$($Ready.primaryPhoneUrl)"
  } elseif ($phoneUrls.Count -gt 0) {
    "$($phoneUrls[0])"
  } else {
    ""
  }

  $actions = if ($nextGate) { ConvertTo-StringArray $nextGate.actions } elseif ($Ready) { ConvertTo-StringArray $Ready.readyActions } else { @("Run npm run acceptance:ready -- -Gate $Gate") }
  $failedChecks = if ($nextGate -and $nextGate.failedChecks) { @($nextGate.failedChecks) } elseif ($Ready -and $Ready.failedChecks) { @($Ready.failedChecks) } else { @() }
  $warnings = if ($nextGate -and $nextGate.warnings) { @($nextGate.warnings) } elseif ($Ready -and $Ready.prepareWarnings) { @($Ready.prepareWarnings) } else { @() }
  $currentPin = Get-GatePinSummary -Ready $Ready -NextGate $nextGate -Session $Session
  $qrCodes = @()
  if ($Session -and $Session.qrCodes) {
    $qrCodes = @($Session.qrCodes | Where-Object { -not [string]::IsNullOrWhiteSpace("$($_.path)") } | ForEach-Object {
      $path = "$($_.path)"
      [pscustomobject]@{
        url = "$($_.url)"
        path = $path
        exists = Test-Path -LiteralPath $path -PathType Leaf
      }
    })
  }

  return [pscustomobject]@{
    gate = $Gate
    status = if ($nextGate) { "$($nextGate.status)" } elseif ($Ready) { "$($Ready.status)" } else { "needs-readiness" }
    primaryPhoneUrl = $primaryPhoneUrl
    phoneUrls = @($phoneUrls)
    runCardHtml = if ($Ready -and -not [string]::IsNullOrWhiteSpace("$($Ready.runCardHtml)")) { "$($Ready.runCardHtml)" } elseif ($nextGate) { "$($nextGate.runCardHtml)" } else { "" }
    hostConsole = if ($Ready -and -not [string]::IsNullOrWhiteSpace("$($Ready.hostConsole)")) { "$($Ready.hostConsole)" } elseif ($nextGate) { "$($nextGate.hostConsole)" } else { "" }
    currentPin = $currentPin
    setupBlockerCount = if ($nextGate -and $null -ne $nextGate.setupBlockerCount) { [int]$nextGate.setupBlockerCount } elseif ($Ready -and $null -ne $Ready.setupBlockerCount) { [int]$Ready.setupBlockerCount } else { 0 }
    physicalBlockerCount = if ($nextGate -and $null -ne $nextGate.physicalBlockerCount) { [int]$nextGate.physicalBlockerCount } elseif ($Ready -and $null -ne $Ready.physicalBlockerCount) { [int]$Ready.physicalBlockerCount } else { @($failedChecks).Count }
    qrCodes = @($qrCodes)
    actions = @($actions)
    failedChecks = @($failedChecks)
    warnings = @($warnings)
  }
}

function Write-RunbookMarkdown {
  param(
    [object]$Runbook,
    [string]$Path
  )

  $gateSections = @($Runbook.gates | ForEach-Object {
    $urlRows = if ($_.phoneUrls -and @($_.phoneUrls).Count -gt 0) { (@($_.phoneUrls) | ForEach-Object { "- $_" }) -join [Environment]::NewLine } else { "- none" }
    $pinRows = if ($_.currentPin -and $_.currentPin.available) {
      "- PIN: $($_.currentPin.pin)`n- Source: $($_.currentPin.source)`n- Refreshed: $($_.currentPin.refreshedAt)`n- Expires in about: $($_.currentPin.secondsRemaining) seconds"
    } else {
      "- unavailable: $($_.currentPin.error)"
    }
    $qrRows = if ($_.qrCodes -and @($_.qrCodes).Count -gt 0) {
      (@($_.qrCodes) | ForEach-Object { "- $($_.path) (exists=$($_.exists), url=$($_.url))" }) -join [Environment]::NewLine
    } else {
      "- none"
    }
    $actionRows = if ($_.actions -and @($_.actions).Count -gt 0) {
      $index = 1
      (@($_.actions) | ForEach-Object {
        $line = "$index. $_"
        $index += 1
        $line
      }) -join [Environment]::NewLine
    } else {
      "1. Run npm run acceptance:ready -- -Gate $($_.gate)"
    }
    $failedRows = if ($_.failedChecks -and @($_.failedChecks).Count -gt 0) {
      (@($_.failedChecks) | ForEach-Object {
        $next = if ($_.nextAction) { " Next: $($_.nextAction)" } else { "" }
        "- $($_.name): $($_.detail)$next"
      }) -join [Environment]::NewLine
    } else {
      "- none"
    }
@"
## $($_.gate)

Status: $($_.status)
Primary phone URL: $($_.primaryPhoneUrl)
Run card: $($_.runCardHtml)
Host console: $($_.hostConsole)
Setup blockers: $($_.setupBlockerCount)
Physical blockers: $($_.physicalBlockerCount)

Current PIN:

$pinRows

Phone URLs:

$urlRows

QR files:

$qrRows

Actions:

$actionRows

Current failed checks:

$failedRows
"@
  })

  $runRows = if ($Runbook.operatorRunNow -and $Runbook.operatorRunNow.steps) {
    $index = 1
    (@($Runbook.operatorRunNow.steps) | ForEach-Object {
      $line = "$index. $_"
      $index += 1
      $line
    }) -join [Environment]::NewLine
  } else {
    "1. Run npm run acceptance:next"
  }

  $failedAuditRows = if ($Runbook.failedAuditIds -and @($Runbook.failedAuditIds).Count -gt 0) {
    (@($Runbook.failedAuditIds) | ForEach-Object { "- $_" }) -join [Environment]::NewLine
  } else {
    "- none"
  }

  $artifactRows = @($Runbook.artifacts | ForEach-Object {
    "| $($_.exists) | $($_.name) | $($_.relativePath) | $($_.bytes) |"
  })
  if ($artifactRows.Count -eq 0) { $artifactRows = @("| none | none | none | none |") }

  $markdown = @"
# Physical Proof Runbook

Generated: $($Runbook.generatedAt)
Status: $($Runbook.status)
Completion ready: $($Runbook.completionReady)

This is the single terminal-friendly runbook for finishing the required real-phone evidence. It does not replace the guided phone run, verifier save commands, or the final no-refresh finalizer.

PINs are short-lived. Before opening the phone URL, rerun the launch command for the gate you are testing so the PIN and copied URL are fresh:

~~~powershell
npm run acceptance:launch -- -Gate same-wifi
npm run acceptance:launch -- -Gate tailscale
~~~

## Run Now

First command:

~~~powershell
$($Runbook.operatorRunNow.firstCommand)
~~~

$runRows

## Gates

$($gateSections -join [Environment]::NewLine)

## Completion Audit Failures

$failedAuditRows

## Final Command Order

~~~powershell
npm run acceptance:verify:save -- -Gate same-wifi
npm run acceptance:verify:save -- -Gate tailscale
npm run acceptance:finalize
~~~

Do not run ``npm run acceptance:refresh`` after both saved verifier commands pass. Use ``npm run acceptance:finalize`` so the final evidence does not get invalidated by a newer readiness artifact.

## Referenced Artifacts

| Exists | Name | Relative Path | Bytes |
| --- | --- | --- | --- |
$($artifactRows -join [Environment]::NewLine)
"@

  $markdown | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-PhysicalProofRunbook {
  New-Item -ItemType Directory -Path $ResolvedOutputDir -Force | Out-Null
  $next = Read-JsonFile (Join-Path $ResolvedOutputDir "phone-acceptance-next-latest.json")
  $sameReady = Read-JsonFile (Join-Path $ResolvedOutputDir "phone-acceptance-ready-same-wifi-latest.json")
  $tailscaleReady = Read-JsonFile (Join-Path $ResolvedOutputDir "phone-acceptance-ready-tailscale-latest.json")
  $sameSession = Read-JsonFile (Join-Path $ResolvedOutputDir "phone-acceptance-session-same-wifi-latest.json")
  $tailscaleSession = Read-JsonFile (Join-Path $ResolvedOutputDir "phone-acceptance-session-tailscale-latest.json")
  $refresh = Read-JsonFile (Join-Path $ResolvedOutputDir "phone-acceptance-refresh-latest.json")
  $audit = Read-JsonFile (Join-Path $ResolvedOutputDir "completion-audit-latest.json")

  $operatorRunNow = if ($next -and $next.operatorRunNow) {
    $next.operatorRunNow
  } else {
    [pscustomobject]@{
      firstCommand = "npm run acceptance:next"
      finalCommand = "npm run acceptance:finalize"
      doNotRefreshAfterProof = $true
      steps = @("Run npm run acceptance:next to rebuild the physical proof checklist.")
    }
  }

  $gates = @(
    New-GateRunbook -Gate "same-wifi" -Next $next -Ready $sameReady -Session $sameSession
    New-GateRunbook -Gate "tailscale" -Next $next -Ready $tailscaleReady -Session $tailscaleSession
  )
  $completionReady = $audit -and $audit.ok -eq $true
  $status = if ($completionReady) { "complete-evidence-present" } elseif ($next -and "$($next.status)" -eq "some-ready") { "same-wifi-ready-tailscale-setup-needed" } else { "physical-proof-needed" }

  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $jsonPath = Join-Path $ResolvedOutputDir "physical-proof-runbook-$timestamp.json"
  $mdPath = Join-Path $ResolvedOutputDir "physical-proof-runbook-$timestamp.md"
  $latestJsonPath = Join-Path $ResolvedOutputDir "physical-proof-runbook-latest.json"
  $latestMdPath = Join-Path $ResolvedOutputDir "physical-proof-runbook-latest.md"

  $runbook = [pscustomobject]@{
    ok = $true
    generatedAt = (Get-Date).ToString("o")
    status = $status
    outputDir = "$ResolvedOutputDir"
    completionReady = [bool]$completionReady
    pinFreshnessWarning = "PINs are short-lived. Rerun npm run acceptance:launch -- -Gate same-wifi or npm run acceptance:launch -- -Gate tailscale immediately before testing."
    onlyPhysicalAuditFailures = if ($refresh) { [bool]$refresh.onlyPhysicalAuditFailures } else { $false }
    failedAuditIds = if ($audit -and $audit.failedIds) { @($audit.failedIds | ForEach-Object { "$_" }) } else { @() }
    operatorRunNow = $operatorRunNow
    gates = @($gates)
    artifacts = @(
      New-ArtifactRecord "physical next-action latest JSON" "phone-acceptance-next-latest.json"
      New-ArtifactRecord "physical next-action latest Markdown" "phone-acceptance-next-latest.md"
      New-ArtifactRecord "same-Wi-Fi readiness latest JSON" "phone-acceptance-ready-same-wifi-latest.json"
      New-ArtifactRecord "Tailscale readiness latest JSON" "phone-acceptance-ready-tailscale-latest.json"
      New-ArtifactRecord "Tailscale bootstrap latest Markdown" "tailscale-bootstrap-latest.md"
      New-ArtifactRecord "acceptance handoff latest HTML" "phone-acceptance-handoff-latest.html"
      New-ArtifactRecord "acceptance dashboard latest HTML" "phone-acceptance-dashboard-latest.html"
      New-ArtifactRecord "evidence bundle latest JSON" "remote-controller-evidence-bundle-latest.json"
      New-ArtifactRecord "completion audit latest JSON" "completion-audit-latest.json"
      New-ArtifactRecord "physical finalization latest JSON" "physical-evidence-finalization-latest.json"
    )
    runbookJsonPath = $jsonPath
    runbookMarkdownPath = $mdPath
    latestRunbookJsonPath = $latestJsonPath
    latestRunbookMarkdownPath = $latestMdPath
  }

  $runbook | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  $runbook | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $latestJsonPath -Encoding UTF8
  Write-RunbookMarkdown -Runbook $runbook -Path $mdPath
  Write-RunbookMarkdown -Runbook $runbook -Path $latestMdPath
  return $runbook
}

if ($SelfTest) {
  $tempOutput = Join-Path ([System.IO.Path]::GetTempPath()) "remote-physical-proof-runbook-$([guid]::NewGuid().ToString('N'))"
  New-Item -ItemType Directory -Path $tempOutput -Force | Out-Null
  $oldOutput = $script:ResolvedOutputDir
  $script:ResolvedOutputDir = $tempOutput
  try {
    [pscustomobject]@{
      ok = $true
      status = "some-ready"
      operatorRunNow = [pscustomobject]@{
        firstCommand = "npm run acceptance:phone -- -Gate same-wifi -SkipStart -RequireReady"
        finalCommand = "npm run acceptance:finalize"
        doNotRefreshAfterProof = $true
        steps = @("Run same-wifi", "After both saved verifiers pass, do not run npm run acceptance:refresh; run npm run acceptance:finalize.")
      }
      gates = @(
        [pscustomobject]@{ gate = "same-wifi"; status = "ready-for-phone"; primaryPhoneUrl = "http://192.168.1.20:4317?acceptance=1&gate=same-wifi&step=physical-phone-proof"; phoneUrls = @("http://192.168.1.20:4317?acceptance=1&gate=same-wifi&step=physical-phone-proof"); runCardHtml = "C:\fake\same.html"; hostConsole = "http://127.0.0.1:4317/host?key=selftest-bad-key"; currentPin = [pscustomobject]@{ available = $true; pin = "123456"; secondsRemaining = 120; refreshedAt = (Get-Date).ToString("o"); source = "next-action"; error = "" }; setupBlockerCount = 0; physicalBlockerCount = 3; actions = @("Run same-wifi"); failedChecks = @([pscustomobject]@{ name = "phone proof log exists"; detail = "event=acceptance.phoneMark" }) },
        [pscustomobject]@{ gate = "tailscale"; status = "setup-needed"; primaryPhoneUrl = ""; phoneUrls = @(); runCardHtml = "C:\fake\tailscale.html"; setupBlockerCount = 2; physicalBlockerCount = 12; actions = @("Install Tailscale"); failedChecks = @([pscustomobject]@{ name = "prepare: tailscale URL"; detail = "missing" }) }
      )
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-next-latest.json") -Encoding UTF8
    [pscustomobject]@{ gate = "same-wifi"; status = "ready-for-phone"; primaryPhoneUrl = "http://192.168.1.20:4317?acceptance=1&gate=same-wifi&step=physical-phone-proof"; phoneUrls = @("http://192.168.1.20:4317?acceptance=1&gate=same-wifi&step=physical-phone-proof"); hostConsole = "http://127.0.0.1:4317/host?key=selftest-bad-key" } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-ready-same-wifi-latest.json") -Encoding UTF8
    [pscustomobject]@{ gate = "tailscale"; status = "setup-needed"; primaryPhoneUrl = ""; phoneUrls = @(); readyActions = @("Install Tailscale") } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-ready-tailscale-latest.json") -Encoding UTF8
    $qrPath = Join-Path $tempOutput "same-qr.svg"
    "<svg xmlns=""http://www.w3.org/2000/svg"" viewBox=""0 0 10 10""><rect width=""10"" height=""10"" fill=""white""/><rect x=""1"" y=""1"" width=""8"" height=""8"" fill=""black""/></svg>" | Set-Content -LiteralPath $qrPath -Encoding UTF8
    [pscustomobject]@{ gate = "same-wifi"; qrCodes = @([pscustomobject]@{ url = "http://192.168.1.20:4317?acceptance=1&gate=same-wifi&step=physical-phone-proof"; path = $qrPath }) } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-session-same-wifi-latest.json") -Encoding UTF8
    [pscustomobject]@{ gate = "tailscale"; qrCodes = @() } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-session-tailscale-latest.json") -Encoding UTF8
    [pscustomobject]@{ ok = $false; onlyPhysicalAuditFailures = $true } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-refresh-latest.json") -Encoding UTF8
    [pscustomobject]@{ ok = $false; failedIds = @("PHYSICAL-001", "PHYSICAL-002", "PHYSICAL-003") } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $tempOutput "completion-audit-latest.json") -Encoding UTF8
    foreach ($artifact in @("phone-acceptance-next-latest.md", "tailscale-bootstrap-latest.md", "phone-acceptance-handoff-latest.html", "phone-acceptance-dashboard-latest.html", "remote-controller-evidence-bundle-latest.json", "physical-evidence-finalization-latest.json")) {
      "self-test artifact" | Set-Content -LiteralPath (Join-Path $tempOutput $artifact) -Encoding UTF8
    }
    $runbook = New-PhysicalProofRunbook
    $markdown = Get-Content -Raw -LiteralPath $runbook.runbookMarkdownPath
    $ok = $runbook.ok -and
      $runbook.status -eq "same-wifi-ready-tailscale-setup-needed" -and
      @($runbook.gates).Count -eq 2 -and
      "$($runbook.operatorRunNow.firstCommand)" -eq "npm run acceptance:phone -- -Gate same-wifi -SkipStart -RequireReady" -and
      "$($runbook.operatorRunNow.finalCommand)" -eq "npm run acceptance:finalize" -and
      $runbook.operatorRunNow.doNotRefreshAfterProof -eq $true -and
      @($runbook.gates | Where-Object { "$($_.gate)" -eq "same-wifi" -and @($_.qrCodes).Count -gt 0 -and @($_.qrCodes | Where-Object { $_.exists -eq $true }).Count -gt 0 }).Count -eq 1 -and
      @($runbook.gates | Where-Object { "$($_.gate)" -eq "same-wifi" -and $_.currentPin.available -eq $true -and "$($_.currentPin.pin)" -eq "123456" }).Count -eq 1 -and
      @($runbook.failedAuditIds).Count -eq 3 -and
      (Test-Path -LiteralPath $runbook.runbookJsonPath) -and
      (Test-Path -LiteralPath $runbook.runbookMarkdownPath) -and
      $markdown -match "QR files" -and
      $markdown -match "same-qr.svg" -and
      $markdown -match "Current PIN" -and
      $markdown -match "PINs are short-lived" -and
      $markdown -match "npm run acceptance:launch -- -Gate same-wifi" -and
      $markdown -match "123456" -and
      $markdown -match "Host console" -and
      $markdown -match 'Do not run `npm run acceptance:refresh`' -and
      $markdown -match 'Use `npm run acceptance:finalize`' -and
      $markdown -notmatch 'Do not run\s+pm run' -and
      $markdown -notmatch 'Use\s+pm run'
    [pscustomobject]@{
      ok = $ok
      status = $runbook.status
      gateCount = @($runbook.gates).Count
      failedAuditCount = @($runbook.failedAuditIds).Count
      writesJsonAndMarkdown = (Test-Path -LiteralPath $runbook.runbookJsonPath) -and (Test-Path -LiteralPath $runbook.runbookMarkdownPath)
    } | ConvertTo-Json -Compress
    if (-not $ok) { exit 1 }
    exit 0
  } finally {
    $script:ResolvedOutputDir = $oldOutput
  }
}

$runbook = New-PhysicalProofRunbook
$runbook | ConvertTo-Json -Depth 8 -Compress
