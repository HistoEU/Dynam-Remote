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
  if (-not $PathValue -or -not (Test-Path -LiteralPath $PathValue)) { return $null }
  return Get-Content -Raw -LiteralPath $PathValue | ConvertFrom-Json
}

function Get-LatestReady {
  param([string]$Gate)
  $latestPath = Join-Path $ResolvedOutputDir "phone-acceptance-ready-$Gate-latest.json"
  $ready = Read-JsonFile -PathValue $latestPath
  return [pscustomobject]@{
    path = if (Test-Path -LiteralPath $latestPath) { $latestPath } else { "" }
    ready = $ready
  }
}

function Get-LatestSession {
  param([object]$Ready)
  if ($Ready -and $Ready.preparedSessionPath) {
    $session = Read-JsonFile -PathValue "$($Ready.preparedSessionPath)"
    if ($session) { return $session }
  }
  return $null
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

function Get-PinSummary {
  param(
    [object]$Ready,
    [object]$Session
  )
  $refreshed = Invoke-CurrentPinRefresh -Ready $Ready
  if ($refreshed) { return $refreshed }
  $pin = if ($Session) { $Session.shortLivedPin } else { $null }
  if ($pin -and $pin.available -and $pin.pin) {
    return [pscustomobject]@{
      available = $true
      pin = "$($pin.pin)"
      secondsRemaining = if ($null -ne $pin.secondsRemaining) { [int]$pin.secondsRemaining } else { 0 }
      refreshedAt = "$($pin.refreshedAt)"
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
      error = "No prepared-session PIN is available. Use the host console New PIN button or regenerate readiness."
    }
}

function ConvertTo-StringArray {
  param([object]$Values)
  if ($null -eq $Values) { return @() }
  return @($Values | Where-Object { $null -ne $_ } | ForEach-Object { "$_" })
}

function ConvertTo-StringList {
  param([object]$Values)
  $list = [System.Collections.Generic.List[string]]::new()
  foreach ($value in @(ConvertTo-StringArray $Values)) {
    $list.Add("$value") | Out-Null
  }
  return ,$list
}

function Get-FirstString {
  param([object]$Values)
  $items = @(ConvertTo-StringArray $Values)
  if ($items.Count -eq 0) { return "" }
  return "$($items[0])"
}

function Get-GuidedPhoneCommand {
  param([string]$Gate)
  return "npm run acceptance:phone -- -Gate $Gate -SkipStart -RequireReady"
}

function New-GatePlan {
  param([string]$Gate)

  $latest = Get-LatestReady -Gate $Gate
  $ready = $latest.ready
  $session = Get-LatestSession -Ready $ready
  $pinSummary = Get-PinSummary -Ready $ready -Session $session
  $qrCodes = if ($session -and $session.qrCodes) { @($session.qrCodes) } else { @() }
  $actions = @()
  $status = "needs-readiness"

  if (-not $ready) {
    $actions = @("Run npm run acceptance:ready -- -Gate $Gate")
  } else {
    $phoneUrls = @(ConvertTo-StringArray $ready.phoneUrls)
    $primaryPhoneUrl = if (-not [string]::IsNullOrWhiteSpace("$($ready.primaryPhoneUrl)")) { "$($ready.primaryPhoneUrl)" } else { Get-FirstString $phoneUrls }
    $readyStatus = if (-not [string]::IsNullOrWhiteSpace("$($ready.status)")) { "$($ready.status)" } else { "" }
    $readyActions = @(ConvertTo-StringArray $ready.readyActions)
    if ($readyStatus -in @("ready-for-phone", "complete") -or ($ready.ok -eq $true -and -not [string]::IsNullOrWhiteSpace($primaryPhoneUrl))) {
      $status = if ($readyStatus -eq "complete") { "complete" } else { "ready-for-phone" }
      $actions = @(
        "Open the run card on the laptop: $($ready.runCardHtml)",
        "Open this URL on the phone: $primaryPhoneUrl",
        "Run the guided checklist: $(Get-GuidedPhoneCommand -Gate $Gate)",
        "Pair with the current PIN, approve on the laptop, complete every manual step, and tap Mark Proof from the controller proof banner or phone Settings.",
        "Save verifier evidence: npm run acceptance:verify:save -- -Gate $Gate",
        "Keep the host running if another physical gate still needs testing; otherwise stop it when all proof work is finished: $($ready.stopCommand)"
      )
    } elseif ($readyStatus -eq "setup-needed" -or $readyActions.Count -gt 0) {
      $status = "setup-needed"
      $actions = @()
      if ($Gate -eq "tailscale") {
        $bootstrapPath = Join-Path $ResolvedOutputDir "tailscale-bootstrap-latest.md"
        $setupCheckPath = Join-Path $ResolvedOutputDir "tailscale-setup-check-latest.md"
        if (Test-Path -LiteralPath $bootstrapPath) {
          $actions += "Review the latest Tailscale bootstrap report: $bootstrapPath"
        } else {
          $actions += "Run npm run tailscale:bootstrap:save to generate exact Tailscale install, service, sign-in, and phone setup steps."
        }
        if (Test-Path -LiteralPath $setupCheckPath) {
          $actions += "Review the latest Tailscale setup check: $setupCheckPath"
        } else {
          $actions += "Run npm run tailscale:check:save to record Tailscale CLI, tailnet IP, advertised URL, auth URL, and firewall readiness."
        }
      }
      $actions += @($readyActions)
      $actions += "Run npm run acceptance:ready -- -Gate $Gate again after setup changes."
    } else {
      $status = "blocked-by-evidence"
      $actions = @(
        "Review the ready artifact: $($latest.path)",
        "Run $(Get-GuidedPhoneCommand -Gate $Gate)",
        "Run npm run acceptance:verify:save -- -Gate $Gate after the physical phone run."
      )
    }
  }

  $failedChecks = if ($ready -and $ready.failedChecks) { @($ready.failedChecks) } else { @() }
  $warnings = if ($ready -and $ready.prepareWarnings) { @($ready.prepareWarnings) } else { @() }
  $warningActions = @($warnings |
    Where-Object {
      -not [string]::IsNullOrWhiteSpace("$($_.nextAction)") -and
      "$($_.nextAction)" -notmatch "^(?i:needed only|informational)"
    } |
    ForEach-Object { "$($_.nextAction)" } |
    Select-Object -Unique)
  $finalPhoneUrls = if ($ready) { ConvertTo-StringList $ready.phoneUrls } else { ConvertTo-StringList @() }
  $finalPrimaryPhoneUrl = if ($ready -and -not [string]::IsNullOrWhiteSpace("$($ready.primaryPhoneUrl)")) { "$($ready.primaryPhoneUrl)" } else { Get-FirstString $finalPhoneUrls }
  return [pscustomobject]@{
    gate = $Gate
    status = $status
    readyPath = $latest.path
    runCardHtml = if ($ready) { "$($ready.runCardHtml)" } else { "" }
    hostConsole = if ($ready) { "$($ready.hostConsole)" } else { "" }
    currentPin = $pinSummary
    qrCodes = @($qrCodes)
    primaryPhoneUrl = $finalPrimaryPhoneUrl
    phoneUrls = $finalPhoneUrls
    setupBlockerCount = if ($ready -and $null -ne $ready.setupBlockerCount) { [int]$ready.setupBlockerCount } else { @($ready.prepareFailures).Count }
    physicalBlockerCount = if ($ready -and $null -ne $ready.physicalBlockerCount) { [int]$ready.physicalBlockerCount } else { @($failedChecks).Count }
    hostHealth = if ($ready) { $ready.hostHealth } else { $null }
    failedChecks = @($failedChecks)
    warnings = @($warnings)
    warningActions = @($warningActions)
    actions = @($actions)
  }
}

function Get-PlanGate {
  param(
    [object[]]$Gates,
    [string]$Gate
  )
  return @($Gates | Where-Object { "$($_.gate)" -eq $Gate } | Select-Object -First 1)
}

function New-OperatorRunNow {
  param([object[]]$Gates)

  $sameWifi = Get-PlanGate -Gates $Gates -Gate "same-wifi"
  $tailscale = Get-PlanGate -Gates $Gates -Gate "tailscale"
  $steps = [System.Collections.Generic.List[string]]::new()
  $firstCommand = ""

  if ($sameWifi -and "$($sameWifi.status)" -eq "ready-for-phone") {
    $firstCommand = "npm run acceptance:phone -- -Gate same-wifi -SkipStart -RequireReady"
    $steps.Add("Run the same-Wi-Fi phone proof now: npm run acceptance:phone -- -Gate same-wifi -SkipStart -RequireReady") | Out-Null
    $steps.Add("After the guided phone run passes and Mark Proof is saved, run npm run acceptance:verify:save -- -Gate same-wifi") | Out-Null
    $steps.Add("Keep the host running after same-Wi-Fi if Tailscale still needs testing; Tailscale uses -SkipStart and expects this host to remain reachable.") | Out-Null
  } elseif ($sameWifi -and "$($sameWifi.status)" -eq "needs-readiness") {
    $firstCommand = "npm run acceptance:ready -- -Gate same-wifi"
    $steps.Add("Prepare same-Wi-Fi phone readiness first: npm run acceptance:ready -- -Gate same-wifi") | Out-Null
  } elseif ($sameWifi -and "$($sameWifi.status)" -ne "complete") {
    $firstCommand = "npm run acceptance:verify:save -- -Gate same-wifi"
    $steps.Add("Re-check same-Wi-Fi saved proof before moving on: npm run acceptance:verify:save -- -Gate same-wifi") | Out-Null
  }

  if ($tailscale -and "$($tailscale.status)" -eq "ready-for-phone") {
    if ([string]::IsNullOrWhiteSpace($firstCommand)) { $firstCommand = "npm run acceptance:phone -- -Gate tailscale -SkipStart -RequireReady" }
    $steps.Add("Run the Tailscale/different-Wi-Fi phone proof: npm run acceptance:phone -- -Gate tailscale -SkipStart -RequireReady") | Out-Null
    $steps.Add("After the guided phone run passes and Mark Proof is saved, run npm run acceptance:verify:save -- -Gate tailscale") | Out-Null
    $steps.Add("Keep the host running until both saved verifiers and npm run acceptance:finalize have passed.") | Out-Null
  } elseif ($tailscale -and "$($tailscale.status)" -eq "setup-needed") {
    if ([string]::IsNullOrWhiteSpace($firstCommand)) { $firstCommand = "npm run tailscale:bootstrap:save" }
    $steps.Add("Set up the free different-Wi-Fi path without mutating this project automatically: npm run tailscale:bootstrap:save") | Out-Null
    $steps.Add("Refresh the Tailscale setup evidence after any sign-in or network change: npm run tailscale:check:save") | Out-Null
    $steps.Add("After Tailscale is installed, running, signed in, and the phone is in the same tailnet, refresh only the Tailscale gate: npm run acceptance:ready -- -Gate tailscale") | Out-Null
    $steps.Add("Then run the Tailscale physical proof and verifier save commands shown for that gate.") | Out-Null
  } elseif ($tailscale -and "$($tailscale.status)" -eq "needs-readiness") {
    if ([string]::IsNullOrWhiteSpace($firstCommand)) { $firstCommand = "npm run acceptance:ready -- -Gate tailscale" }
    $steps.Add("Prepare Tailscale phone readiness: npm run acceptance:ready -- -Gate tailscale") | Out-Null
  } elseif ($tailscale -and "$($tailscale.status)" -ne "complete") {
    if ([string]::IsNullOrWhiteSpace($firstCommand)) { $firstCommand = "npm run acceptance:verify:save -- -Gate tailscale" }
    $steps.Add("Re-check Tailscale saved proof before finalization: npm run acceptance:verify:save -- -Gate tailscale") | Out-Null
  }

  if ([string]::IsNullOrWhiteSpace($firstCommand)) { $firstCommand = "npm run acceptance:finalize" }
  $steps.Add("After both saved verifiers pass, do not run npm run acceptance:refresh; run npm run acceptance:finalize so no newer readiness artifact invalidates the proof.") | Out-Null

  return [pscustomobject]@{
    firstCommand = $firstCommand
    finalCommand = "npm run acceptance:finalize"
    doNotRefreshAfterProof = $true
    steps = @($steps)
  }
}

function Write-NextMarkdown {
  param(
    [object]$Plan,
    [string]$Path
  )

  $sections = @($Plan.gates | ForEach-Object {
    $phoneRows = if ($_.phoneUrls -and @($_.phoneUrls).Count -gt 0) {
      (@($_.phoneUrls) | ForEach-Object { "- $_" }) -join [Environment]::NewLine
    } else {
      "- none"
    }
    $pinRows = if ($_.currentPin -and $_.currentPin.available) {
      "- PIN: $($_.currentPin.pin)`n- Refreshed: $($_.currentPin.refreshedAt)`n- Expires in about: $($_.currentPin.secondsRemaining) seconds"
    } else {
      "- unavailable: $($_.currentPin.error)"
    }
    $qrRows = if ($_.qrCodes -and @($_.qrCodes).Count -gt 0) {
      (@($_.qrCodes) | ForEach-Object { "- $($_.path) -> $($_.url)" }) -join [Environment]::NewLine
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
    $warningRows = if ($_.warnings -and @($_.warnings).Count -gt 0) {
      (@($_.warnings) | ForEach-Object {
        $next = if ($_.nextAction) { " Next: $($_.nextAction)" } else { "" }
        "- $($_.name): $($_.detail)$next"
      }) -join [Environment]::NewLine
    } else {
      "- none"
    }
    $warningActionRows = if ($_.warningActions -and @($_.warningActions).Count -gt 0) {
      (@($_.warningActions) | ForEach-Object { "- $_" }) -join [Environment]::NewLine
    } else {
      "- none"
    }
@"
## $($_.gate)

Status: $($_.status)
Ready artifact: $($_.readyPath)
Run card: $($_.runCardHtml)
Host console: $($_.hostConsole)

Current PIN:

$pinRows

QR files:

$qrRows

Phone URLs:

$phoneRows

Next actions:

$actionRows

Current blockers:

$failedRows

Warnings:

$warningRows

Warning actions:

$warningActionRows

"@
  })

  $runNowRows = if ($Plan.operatorRunNow -and $Plan.operatorRunNow.steps -and @($Plan.operatorRunNow.steps).Count -gt 0) {
    $index = 1
    (@($Plan.operatorRunNow.steps) | ForEach-Object {
      $line = "$index. $_"
      $index += 1
      $line
    }) -join [Environment]::NewLine
  } else {
    "1. Run npm run acceptance:next again after readiness artifacts exist."
  }

  $markdown = @"
# Physical Acceptance Next Actions

Generated: $($Plan.generatedAt)
Overall status: $($Plan.status)

This file is an operator checklist for the two physical proof gates. It does not replace ``npm run acceptance:verify:save`` or the final no-refresh ``npm run acceptance:finalize`` command.

## Run Now

First command:

~~~powershell
$($Plan.operatorRunNow.firstCommand)
~~~

$runNowRows

$($sections -join [Environment]::NewLine)

## Completion Commands

~~~powershell
npm run acceptance:verify:save -- -Gate same-wifi
npm run acceptance:verify:save -- -Gate tailscale
npm run acceptance:finalize
~~~
"@

  $markdown | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-NextPlan {
  New-Item -ItemType Directory -Path $ResolvedOutputDir -Force | Out-Null
  $gates = @(
    New-GatePlan -Gate "same-wifi"
    New-GatePlan -Gate "tailscale"
  )
  $operatorRunNow = New-OperatorRunNow -Gates $gates
  $status = if (@($gates | Where-Object { $_.status -ne "ready-for-phone" }).Count -eq 0) {
    "both-ready-for-phone"
  } elseif (@($gates | Where-Object { $_.status -eq "ready-for-phone" }).Count -gt 0) {
    "some-ready"
  } else {
    "setup-needed"
  }

  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $jsonPath = Join-Path $ResolvedOutputDir "phone-acceptance-next-$timestamp.json"
  $mdPath = Join-Path $ResolvedOutputDir "phone-acceptance-next-$timestamp.md"
  $latestJsonPath = Join-Path $ResolvedOutputDir "phone-acceptance-next-latest.json"
  $latestMdPath = Join-Path $ResolvedOutputDir "phone-acceptance-next-latest.md"

  $plan = [pscustomobject]@{
    ok = $true
    generatedAt = (Get-Date).ToString("o")
    status = $status
    outputDir = "$ResolvedOutputDir"
    operatorRunNow = $operatorRunNow
    gates = @($gates)
    nextJsonPath = $jsonPath
    nextMarkdownPath = $mdPath
    latestNextJsonPath = $latestJsonPath
    latestNextMarkdownPath = $latestMdPath
  }

  $plan | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  $plan | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $latestJsonPath -Encoding UTF8
  Write-NextMarkdown -Plan $plan -Path $mdPath
  Write-NextMarkdown -Plan $plan -Path $latestMdPath
  return $plan
}

if ($SelfTest) {
  $tempOutput = Join-Path ([System.IO.Path]::GetTempPath()) "remote-acceptance-next-$([guid]::NewGuid().ToString('N'))"
  New-Item -ItemType Directory -Path $tempOutput -Force | Out-Null
  $oldOutput = $script:ResolvedOutputDir
  $script:ResolvedOutputDir = $tempOutput
  try {
    [pscustomobject]@{
      ok = $true
      gate = "same-wifi"
      status = "ready-for-phone"
      runCardHtml = "C:\fake\same.html"
      hostConsole = "http://127.0.0.1:4317/host?key=selftest-bad-key"
      preparedSessionPath = Join-Path $tempOutput "phone-acceptance-session-same-wifi-latest.json"
      phoneUrls = @("http://192.168.1.10:4317")
      primaryPhoneUrl = "http://192.168.1.10:4317"
      setupBlockerCount = 0
      physicalBlockerCount = 0
      nextCommand = "npm run acceptance:phone -- -Gate same-wifi -SkipStart -RequireReady"
      stopCommand = "npm run acceptance:stop -- -Gate same-wifi"
      failedChecks = @()
      prepareWarnings = @([pscustomobject]@{ name = "warning: firewall"; detail = "firewall missing"; nextAction = "Run npm run firewall:handoff first if the phone cannot connect, then run the copied elevated install command only if you choose to allow inbound TCP 4317." })
      readyActions = @()
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-ready-same-wifi-latest.json") -Encoding UTF8
    [pscustomobject]@{
      shortLivedPin = [pscustomobject]@{
        available = $true
        pin = "123456"
        secondsRemaining = 120
        refreshedAt = (Get-Date).ToString("o")
        error = ""
      }
      qrCodes = @([pscustomobject]@{
        url = "http://192.168.1.10:4317"
        path = Join-Path $tempOutput "same-qr.svg"
      })
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-session-same-wifi-latest.json") -Encoding UTF8
    [pscustomobject]@{
      ok = $false
      gate = "tailscale"
      status = "setup-needed"
      runCardHtml = "C:\fake\tailscale.html"
      hostConsole = "http://127.0.0.1:4317/host?key=selftest-bad-key"
      phoneUrls = @()
      primaryPhoneUrl = ""
      setupBlockerCount = 1
      physicalBlockerCount = 0
      nextCommand = "npm run acceptance:phone -- -Gate tailscale -SkipStart -RequireReady"
      stopCommand = "npm run acceptance:stop -- -Gate tailscale"
      failedChecks = @([pscustomobject]@{ name = "prepare: tailscale URL"; detail = "missing"; nextAction = "Install Tailscale." })
      prepareWarnings = @()
      readyActions = @("Install Tailscale.")
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-ready-tailscale-latest.json") -Encoding UTF8
    $plan = New-NextPlan
    $ok = $plan.ok -and
      $plan.status -eq "some-ready" -and
      (Test-Path -LiteralPath $plan.nextJsonPath) -and
      (Test-Path -LiteralPath $plan.nextMarkdownPath) -and
      @($plan.gates).Count -eq 2 -and
      ((Get-Content -Raw -LiteralPath $plan.nextMarkdownPath) -match 'does not replace `npm run acceptance:verify:save`') -and
      ((Get-Content -Raw -LiteralPath $plan.nextMarkdownPath) -match '## Run Now') -and
      ((Get-Content -Raw -LiteralPath $plan.nextMarkdownPath) -match 'First command') -and
      ((Get-Content -Raw -LiteralPath $plan.nextMarkdownPath) -match 'Current PIN') -and
      ((Get-Content -Raw -LiteralPath $plan.nextMarkdownPath) -match '123456') -and
      ((Get-Content -Raw -LiteralPath $plan.nextMarkdownPath) -match 'QR files') -and
      ((Get-Content -Raw -LiteralPath $plan.nextMarkdownPath) -match 'same-qr.svg') -and
      ((Get-Content -Raw -LiteralPath $plan.nextMarkdownPath) -match 'Host console') -and
      ((Get-Content -Raw -LiteralPath $plan.nextMarkdownPath) -match '127.0.0.1:4317/host') -and
      ((Get-Content -Raw -LiteralPath $plan.nextMarkdownPath) -match 'do not run npm run acceptance:refresh') -and
      ((Get-Content -Raw -LiteralPath $plan.nextMarkdownPath) -notmatch 'Stop only the prepared same-Wi-Fi host') -and
      ((Get-Content -Raw -LiteralPath $plan.nextMarkdownPath) -notmatch 'Stop only the prepared Tailscale host') -and
      ((Get-Content -Raw -LiteralPath $plan.nextMarkdownPath) -match 'Keep the host running') -and
      ((Get-Content -Raw -LiteralPath $plan.nextMarkdownPath) -match 'Warning actions') -and
      ((Get-Content -Raw -LiteralPath $plan.nextMarkdownPath) -match 'npm run acceptance:finalize') -and
      ((Get-Content -Raw -LiteralPath $plan.nextMarkdownPath) -match 'tailscale:bootstrap:save') -and
      $plan.operatorRunNow -and
      $plan.operatorRunNow.doNotRefreshAfterProof -eq $true -and
      "$($plan.operatorRunNow.firstCommand)" -match "-RequireReady" -and
      "$($plan.operatorRunNow.finalCommand)" -eq "npm run acceptance:finalize"
    [pscustomobject]@{
      ok = $ok
      status = $plan.status
      gateCount = @($plan.gates).Count
      writesJsonAndMarkdown = (Test-Path -LiteralPath $plan.nextJsonPath) -and (Test-Path -LiteralPath $plan.nextMarkdownPath)
      includesPinAndQr = (Get-Content -Raw -LiteralPath $plan.nextMarkdownPath) -match '123456' -and (Get-Content -Raw -LiteralPath $plan.nextMarkdownPath) -match 'same-qr.svg'
      firstCommand = "$($plan.operatorRunNow.firstCommand)"
    } | ConvertTo-Json -Compress
    if (-not $ok) { exit 1 }
    exit 0
  } finally {
    $script:ResolvedOutputDir = $oldOutput
  }
}

$plan = New-NextPlan
$plan | ConvertTo-Json -Depth 10 -Compress
