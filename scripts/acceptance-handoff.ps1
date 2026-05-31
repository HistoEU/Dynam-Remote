param(
  [string]$OutputDir = "output\acceptance",
  [switch]$Open,
  [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$ResolvedOutputDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $Root $OutputDir }

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

function Escape-Html {
  param([object]$Value)
  return [System.Net.WebUtility]::HtmlEncode("$Value")
}

function Resolve-ArtifactPath {
  param([string]$PathValue)
  if ([string]::IsNullOrWhiteSpace($PathValue)) { return "" }
  if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
  return Join-Path $Root $PathValue
}

function ConvertTo-FileHref {
  param([string]$PathValue)
  $resolved = Resolve-ArtifactPath $PathValue
  if ([string]::IsNullOrWhiteSpace($resolved) -or -not (Test-Path -LiteralPath $resolved)) { return "" }
  return "file:///$((Resolve-Path -LiteralPath $resolved) -replace '\\', '/')"
}

function New-LinkHtml {
  param(
    [string]$Text,
    [string]$Href
  )
  if ([string]::IsNullOrWhiteSpace($Href)) { return "<span class=""muted"">not available yet</span>" }
  return "<a href=""$(Escape-Html $Href)"">$(Escape-Html $Text)</a>"
}

function New-UrlRows {
  param([object]$Urls)
  $rows = @(ConvertTo-StringArray $Urls | ForEach-Object {
    $safe = Escape-Html $_
    "<li><a href=""$safe"">$safe</a></li>"
  })
  if ($rows.Count -eq 0) { return "<li><span class=""muted"">No phone URL is ready for this gate.</span></li>" }
  return ($rows -join [Environment]::NewLine)
}

function New-ActionRows {
  param([object]$Actions)
  $index = 1
  $rows = @(ConvertTo-StringArray $Actions | ForEach-Object {
    $line = "<li><span class=""step-index"">$index</span><code>$(Escape-Html $_)</code></li>"
    $index += 1
    $line
  })
  if ($rows.Count -eq 0) { return "<li><span class=""muted"">Run readiness again before starting this gate.</span></li>" }
  return ($rows -join [Environment]::NewLine)
}

function New-CheckRows {
  param([object]$Checks)
  $rows = @($Checks | Where-Object { $null -ne $_ } | ForEach-Object {
    $detail = if ($_.detail) { " <span>$(Escape-Html $_.detail)</span>" } else { "" }
    $next = if ($_.nextAction) { " <em>$(Escape-Html $_.nextAction)</em>" } else { "" }
    "<li><strong>$(Escape-Html $_.name)</strong>$detail$next</li>"
  })
  if ($rows.Count -eq 0) { return "<li><span class=""muted"">none</span></li>" }
  return ($rows -join [Environment]::NewLine)
}

function Get-LatestReady {
  param([string]$Gate)
  Read-JsonFile (Join-Path $ResolvedOutputDir "phone-acceptance-ready-$Gate-latest.json")
}

function Get-LatestSession {
  param([object]$Ready)
  if ($Ready -and $Ready.preparedSessionPath) {
    $session = Read-JsonFile "$($Ready.preparedSessionPath)"
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
  param([object[]]$ReadyItems)
  foreach ($ready in @($ReadyItems | Where-Object { $null -ne $_ })) {
    $hostConsole = "$($ready.hostConsole)"
    if ([string]::IsNullOrWhiteSpace($hostConsole)) { continue }
    $hostKey = Get-QueryParam -Url $hostConsole -Name "key"
    if ([string]::IsNullOrWhiteSpace($hostKey)) { continue }
    try {
      $uri = [System.Uri]$hostConsole
      $baseUrl = "$($uri.Scheme)://$($uri.Authority)"
      $pin = Invoke-RestMethod -Uri "$baseUrl/api/refresh-pin" -Method Post -Headers @{ "x-host-key" = $hostKey } -Body "{}" -ContentType "application/json" -TimeoutSec 6
      if ($pin -and $pin.pin) {
        return [pscustomobject]@{
          available = $true
          pin = "$($pin.pin)"
          secondsRemaining = if ($null -ne $pin.secondsRemaining) { [int]$pin.secondsRemaining } else { 0 }
          refreshedAt = (Get-Date).ToString("o")
          source = "host-refresh"
          error = ""
        }
      }
    } catch {
      # Fall through to the prepared-session PIN if the host is not reachable.
    }
  }
  return $null
}

function Get-SessionPinFallback {
  param([object[]]$Sessions)
  foreach ($session in @($Sessions | Where-Object { $null -ne $_ })) {
    $pin = $session.shortLivedPin
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
  }
  return [pscustomobject]@{
    available = $false
    pin = ""
    secondsRemaining = 0
    refreshedAt = ""
    source = "unavailable"
    error = "No current PIN could be refreshed or found in the prepared session."
  }
}

function Get-HandoffPin {
  param(
    [object[]]$ReadyItems,
    [object[]]$Sessions
  )
  $refreshed = Invoke-CurrentPinRefresh -ReadyItems $ReadyItems
  if ($refreshed) { return $refreshed }
  return Get-SessionPinFallback -Sessions $Sessions
}

function Get-EvidenceGate {
  param(
    [object]$Bundle,
    [string]$Gate
  )
  if (-not $Bundle -or -not $Bundle.gates) { return $null }
  return @($Bundle.gates | Where-Object { $_.gate -eq $Gate } | Select-Object -First 1)
}

function New-GateHandoff {
  param(
    [string]$Gate,
    [object]$Ready,
    [object]$Session,
    [object]$EvidenceGate
  )

  $phoneUrls = if ($Ready) { ConvertTo-StringList $Ready.phoneUrls } else { ConvertTo-StringList @() }
  $phoneUrlList = @($phoneUrls)
  $primaryUrl = if ($Ready -and -not [string]::IsNullOrWhiteSpace("$($Ready.primaryPhoneUrl)")) { "$($Ready.primaryPhoneUrl)" } elseif ($phoneUrlList.Count -gt 0) { "$($phoneUrlList[0])" } else { "" }
  $readyStatus = if ($Ready -and -not [string]::IsNullOrWhiteSpace("$($Ready.status)")) { "$($Ready.status)" } else { "" }
  $guidedCommand = "npm run acceptance:phone -- -Gate $Gate -SkipStart -RequireReady"
  $qrPath = ""
  if ($Session -and $Session.qrCodes) {
    $qr = @($Session.qrCodes | Where-Object { $_.path } | Select-Object -First 1)
    if ($qr) { $qrPath = "$($qr.path)" }
  }

  $actions = @()
  if ($Ready -and ($readyStatus -in @("ready-for-phone", "complete") -or ($Ready.ok -eq $true -and -not [string]::IsNullOrWhiteSpace($primaryUrl)))) {
    $actions = @(
      "Open this handoff page and the host console on the laptop.",
      "Scan the QR code or open the phone URL.",
      "Run $guidedCommand in the laptop terminal.",
      "Pair with the current PIN shown at the top of this handoff, approve the phone on the laptop, complete every guided step, and tap Mark Proof from the controller proof banner.",
      "Run npm run acceptance:verify:save -- -Gate $Gate.",
      "Run npm run acceptance:finalize after both physical gates pass."
    )
  } elseif ($Ready -and $Ready.readyActions) {
    $actions = @($Ready.readyActions)
  } else {
    $actions = @("Run npm run acceptance:ready -- -Gate $Gate, then regenerate this handoff.")
  }

  return [pscustomobject]@{
    gate = $Gate
    status = if ($readyStatus) { $readyStatus } elseif ($Ready -and -not [string]::IsNullOrWhiteSpace($primaryUrl)) { "ready-for-phone" } elseif ($Ready) { "setup-needed" } else { "needs-readiness" }
    readyPath = if ($Ready) { "$($Ready.readyStatusPath)" } else { "" }
    runCardHtml = if ($Ready) { "$($Ready.runCardHtml)" } else { "" }
    watchJsonPath = Join-Path $ResolvedOutputDir "phone-acceptance-watch-$Gate-latest.json"
    watchMarkdownPath = Join-Path $ResolvedOutputDir "phone-acceptance-watch-$Gate-latest.md"
    watchJsonHref = ConvertTo-FileHref (Join-Path $ResolvedOutputDir "phone-acceptance-watch-$Gate-latest.json")
    watchMarkdownHref = ConvertTo-FileHref (Join-Path $ResolvedOutputDir "phone-acceptance-watch-$Gate-latest.md")
    hostConsole = if ($Ready) { "$($Ready.hostConsole)" } else { "" }
    primaryPhoneUrl = $primaryUrl
    phoneUrls = $phoneUrls
    setupBlockerCount = if ($Ready -and $null -ne $Ready.setupBlockerCount) { [int]$Ready.setupBlockerCount } else { @($Ready.prepareFailures).Count }
    physicalBlockerCount = if ($Ready -and $null -ne $Ready.physicalBlockerCount) { [int]$Ready.physicalBlockerCount } else { @($Ready.failedChecks).Count }
    secondaryPhoneUrls = if ($Ready) { ConvertTo-StringList $Ready.secondaryPhoneUrls } else { ConvertTo-StringList @() }
    qrPath = $qrPath
    qrHref = ConvertTo-FileHref $qrPath
    nextCommand = if ($Ready) { $guidedCommand } else { "" }
    stopCommand = if ($Ready) { "$($Ready.stopCommand)" } else { "" }
    failedChecks = [object[]]$(if ($Ready -and $Ready.failedChecks) { @($Ready.failedChecks) } else { @() })
    warnings = [object[]]$(if ($Ready -and $Ready.prepareWarnings) { @($Ready.prepareWarnings) } else { @() })
    verifierOk = if ($EvidenceGate) { [bool]$EvidenceGate.verifierOk } else { $false }
    latestVerifierJsonPath = if ($EvidenceGate) { "$($EvidenceGate.latestVerifierJsonPath)" } else { "" }
    latestVerifierHref = if ($EvidenceGate) { ConvertTo-FileHref "$($EvidenceGate.latestVerifierJsonPath)" } else { "" }
    actions = [string[]]@($actions)
  }
}

function Write-HandoffMarkdown {
  param(
    [object]$Report,
    [string]$Path
  )

  $sections = @($Report.gates | ForEach-Object {
    $urls = if ($_.phoneUrls.Count -gt 0) { (@($_.phoneUrls) | ForEach-Object { "- $_" }) -join [Environment]::NewLine } else { "- none" }
    $warnings = if ($_.warnings -and @($_.warnings).Count -gt 0) {
      (@($_.warnings) | ForEach-Object {
        $nextAction = if ($_.nextAction) { " Next: $($_.nextAction)" } else { "" }
        "- $($_.name): $($_.detail)$nextAction"
      }) -join [Environment]::NewLine
    } else {
      "- none"
    }
    $actions = if ($_.actions.Count -gt 0) {
      $i = 1
      (@($_.actions) | ForEach-Object {
        $line = "$i. $_"
        $i += 1
        $line
      }) -join [Environment]::NewLine
    } else {
      "1. Run npm run acceptance:ready -- -Gate $($_.gate)"
    }
@"
## $($_.gate)

Status: $($_.status)
Primary phone URL: $($_.primaryPhoneUrl)
QR SVG: $($_.qrPath)
Run card: $($_.runCardHtml)
Latest watch Markdown: $($_.watchMarkdownPath)
Latest watch JSON: $($_.watchJsonPath)
Latest verifier JSON: $($_.latestVerifierJsonPath)

Phone URLs:

$urls

Warnings:

$warnings

Actions:

$actions
"@
  })

  $markdown = @"
# Physical Phone Acceptance Handoff

Generated: $($Report.generatedAt)
Status: $($Report.status)

This handoff page is for the real phone run. It does not replace the guided checklist, verifier output, evidence bundle, or completion audit.

## Current PIN

PIN: $(if ($Report.currentPin.available) { $Report.currentPin.pin } else { "unavailable" })
Source: $($Report.currentPin.source)
Refreshed: $($Report.currentPin.refreshedAt)
Expires in about: $($Report.currentPin.secondsRemaining) seconds
If the PIN expires before pairing, use the host console New PIN button or regenerate this handoff.

$($sections -join [Environment]::NewLine)

## Final Commands

~~~powershell
npm run acceptance:verify:save -- -Gate same-wifi
npm run acceptance:verify:save -- -Gate tailscale
npm run acceptance:finalize
~~~
"@

  $markdown | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-HandoffHtml {
  param(
    [object]$Report,
    [string]$Path
  )

  $same = @($Report.gates | Where-Object { $_.gate -eq "same-wifi" } | Select-Object -First 1)
  $tail = @($Report.gates | Where-Object { $_.gate -eq "tailscale" } | Select-Object -First 1)
  $dashboardHref = ConvertTo-FileHref $Report.dashboardHtmlPath
  $bundleHref = ConvertTo-FileHref $Report.evidenceBundleMarkdownPath
  $nextHref = ConvertTo-FileHref $Report.nextMarkdownPath
  $qaHref = ConvertTo-FileHref $Report.qaReportPath
  $qaMarkdownHref = ConvertTo-FileHref $Report.qaReportMarkdownPath
  $pinText = if ($Report.currentPin.available) { "$($Report.currentPin.pin)" } else { "Unavailable" }
  $pinMeta = if ($Report.currentPin.available) {
    "Refreshed from $($Report.currentPin.source) at $($Report.currentPin.refreshedAt). Expires in about $($Report.currentPin.secondsRemaining) seconds."
  } else {
    "$($Report.currentPin.error)"
  }
  $sameQrBlock = if ($same.qrHref) {
    "<img src=""$(Escape-Html $same.qrHref)"" alt=""Same-Wi-Fi phone acceptance QR"">"
  } else {
    "<div class=""qr-missing"">QR not ready yet</div>"
  }
  $tailQrBlock = if ($tail.qrHref) {
    "<img src=""$(Escape-Html $tail.qrHref)"" alt=""Tailscale phone acceptance QR"">"
  } else {
    "<div class=""qr-missing"">QR not ready yet</div>"
  }

  $html = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Physical Phone Acceptance Handoff</title>
  <style>
    :root {
      color-scheme: light;
      --ink: #16202a;
      --muted: #596675;
      --line: #d9e0e8;
      --paper: #f5f7fa;
      --panel: #ffffff;
      --good: #0f766e;
      --warn: #a16207;
      --bad: #b91c1c;
      --link: #1d4ed8;
    }
    * { box-sizing: border-box; }
    body { margin: 0; font-family: "Segoe UI", Arial, sans-serif; color: var(--ink); background: var(--paper); line-height: 1.45; }
    header { background: #fff; border-bottom: 1px solid var(--line); padding: 28px clamp(18px, 4vw, 52px) 20px; }
    main { padding: 24px clamp(18px, 4vw, 52px) 42px; }
    h1 { margin: 0 0 8px; font-size: clamp(26px, 3vw, 40px); letter-spacing: 0; }
    h2 { margin: 0 0 12px; font-size: 22px; letter-spacing: 0; }
    h3 { margin: 18px 0 8px; font-size: 14px; color: var(--muted); text-transform: uppercase; letter-spacing: 0; }
    a { color: var(--link); overflow-wrap: anywhere; }
    code { display: inline-block; max-width: 100%; padding: 3px 6px; border: 1px solid #d7dee8; border-radius: 6px; background: #eef2f7; overflow-wrap: anywhere; white-space: normal; }
    .subtitle { margin: 0; color: var(--muted); max-width: 920px; }
    .grid { display: grid; grid-template-columns: minmax(280px, 420px) minmax(320px, 1fr); gap: 18px; align-items: start; }
    .gate-grid { display: grid; grid-template-columns: minmax(260px, 360px) minmax(320px, 1fr); gap: 18px; align-items: start; }
    .panel { background: var(--panel); border: 1px solid var(--line); border-radius: 8px; padding: 18px; }
    .hero { border-top: 5px solid var(--good); }
    .status { display: inline-flex; align-items: center; min-height: 28px; padding: 3px 9px; border: 1px solid var(--line); border-radius: 999px; font-weight: 700; color: var(--good); background: #effaf7; }
    .setup { color: var(--warn); background: #fff8e6; }
    .blocked { color: var(--bad); background: #fff1f2; }
    .qr-box { display: grid; place-items: center; min-height: 300px; border: 1px solid var(--line); border-radius: 8px; background: #fff; }
    .qr-box img { width: min(100%, 300px); height: auto; }
    .qr-missing { color: var(--muted); font-weight: 700; }
    .primary-url { font-size: 16px; font-weight: 700; overflow-wrap: anywhere; }
    ul, ol { margin: 8px 0 0; padding-left: 22px; }
    li { margin: 7px 0; }
    .action-list { list-style: none; padding-left: 0; }
    .action-list li { display: grid; grid-template-columns: 28px minmax(0, 1fr); gap: 8px; align-items: start; }
    .step-index { width: 24px; height: 24px; border-radius: 999px; display: inline-grid; place-items: center; background: #dfe7f1; font-weight: 700; font-size: 12px; }
    .links { display: flex; flex-wrap: wrap; gap: 10px; margin-top: 12px; }
    .links a { border: 1px solid var(--line); border-radius: 7px; padding: 7px 9px; text-decoration: none; background: #fff; }
    .muted { color: var(--muted); }
    .final { margin-top: 18px; }
    .pin-card { display: flex; flex-wrap: wrap; gap: 14px; align-items: center; margin-top: 16px; }
    .pin-code { font-size: clamp(30px, 6vw, 52px); line-height: 1; font-weight: 850; letter-spacing: 0.08em; color: #7c580f; }
    .pin-help { margin: 0; color: var(--muted); max-width: 760px; }
    @media (max-width: 860px) {
      .grid { grid-template-columns: 1fr; }
      main { padding-inline: 14px; }
    }
  </style>
</head>
<body>
  <header>
    <h1>Physical Phone Acceptance Handoff</h1>
      <p class="subtitle">Generated $(Escape-Html $Report.generatedAt). This is the launch surface for the real phone run; completion still requires guided checklist evidence, saved verifier JSON, and the no-refresh finalizer.</p>
    <div class="links">
      $(New-LinkHtml -Text "dashboard" -Href $dashboardHref)
      $(New-LinkHtml -Text "next actions" -Href $nextHref)
          $(New-LinkHtml -Text "evidence bundle" -Href $bundleHref)
      $(New-LinkHtml -Text "QA report" -Href $qaHref)
    </div>
    <div class="pin-card" aria-label="Current pairing PIN">
      <div>
        <h2>Current PIN</h2>
        <div class="pin-code">$(Escape-Html $pinText)</div>
      </div>
      <p class="pin-help">$(Escape-Html $pinMeta) If it expires before pairing, use the host console New PIN button or regenerate this handoff.</p>
    </div>
  </header>
  <main>
    <section class="panel final">
      <span class="status">$(if ($Report.qaOk) { "QA passed" } else { "QA missing" })</span>
      <h2>Automated QA Evidence</h2>
      <p>Node tests: <strong>$($Report.qaPass) pass / $($Report.qaFail) fail</strong>. Script self-tests: <strong>$($Report.qaSelfTests)</strong>. Host mode: <code>$(Escape-Html $Report.qaHostMode)</code>.</p>
      <div class="links">
        $(New-LinkHtml -Text "QA report JSON" -Href $qaHref)
        $(New-LinkHtml -Text "QA report Markdown" -Href $qaMarkdownHref)
      </div>
    </section>
    <section class="grid">
      <article class="panel hero">
        <span class="status">$(Escape-Html $same.status)</span>
        <h2>Same-Wi-Fi Phone Run</h2>
        <div class="qr-box">$sameQrBlock</div>
        <h3>Phone URL</h3>
        <p class="primary-url">$(Escape-Html $same.primaryPhoneUrl)</p>
        <h3>All Same-Wi-Fi URLs</h3>
        <ul>$(New-UrlRows $same.phoneUrls)</ul>
      </article>
      <article class="panel">
      <h2>Do These In Order</h2>
      <ol class="action-list">$(New-ActionRows $same.actions)</ol>
        <h3>Current Same-Wi-Fi Blockers</h3>
        <ul>$(New-CheckRows $same.failedChecks)</ul>
        <h3>Warnings</h3>
        <ul>$(New-CheckRows $same.warnings)</ul>
        <h3>Evidence Links</h3>
        <div class="links">
          $(New-LinkHtml -Text "run card" -Href (ConvertTo-FileHref $same.runCardHtml))
          $(New-LinkHtml -Text "host console" -Href $same.hostConsole)
          $(New-LinkHtml -Text "watch Markdown" -Href $same.watchMarkdownHref)
          $(New-LinkHtml -Text "latest verifier JSON" -Href $same.latestVerifierHref)
        </div>
      </article>
    </section>
    <section class="panel final">
      <span class="status setup">$(Escape-Html $tail.status)</span>
      <h2>Tailscale / Different-Wi-Fi Gate</h2>
      <div class="gate-grid">
        <div>
          <div class="qr-box">$tailQrBlock</div>
          <h3>Phone URLs</h3>
          <ul>$(New-UrlRows $tail.phoneUrls)</ul>
        </div>
        <div>
          <h3>Setup Or Run Actions</h3>
          <ol class="action-list">$(New-ActionRows $tail.actions)</ol>
          <h3>Current Tailscale Blockers</h3>
          <ul>$(New-CheckRows $tail.failedChecks)</ul>
          <h3>Evidence Links</h3>
          <div class="links">
            $(New-LinkHtml -Text "run card" -Href (ConvertTo-FileHref $tail.runCardHtml))
            $(New-LinkHtml -Text "host console" -Href $tail.hostConsole)
            $(New-LinkHtml -Text "watch Markdown" -Href $tail.watchMarkdownHref)
            $(New-LinkHtml -Text "latest verifier JSON" -Href $tail.latestVerifierHref)
          </div>
        </div>
      </div>
    </section>
  </main>
</body>
</html>
"@

  $html | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-HandoffReport {
  New-Item -ItemType Directory -Path $ResolvedOutputDir -Force | Out-Null
  $bundle = Read-JsonFile (Join-Path $ResolvedOutputDir "remote-controller-evidence-bundle-latest.json")
  $qa = Read-JsonFile (Join-Path $ResolvedOutputDir "qa-report-latest.json")
  $sameReady = Get-LatestReady "same-wifi"
  $tailReady = Get-LatestReady "tailscale"
  $sameSession = Get-LatestSession $sameReady
  $tailSession = Get-LatestSession $tailReady
  $currentPin = Get-HandoffPin -ReadyItems @($sameReady, $tailReady) -Sessions @($sameSession, $tailSession)
  $same = New-GateHandoff -Gate "same-wifi" -Ready $sameReady -Session $sameSession -EvidenceGate (Get-EvidenceGate -Bundle $bundle -Gate "same-wifi")
  $tail = New-GateHandoff -Gate "tailscale" -Ready $tailReady -Session $tailSession -EvidenceGate (Get-EvidenceGate -Bundle $bundle -Gate "tailscale")
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $jsonPath = Join-Path $ResolvedOutputDir "phone-acceptance-handoff-$timestamp.json"
  $htmlPath = Join-Path $ResolvedOutputDir "phone-acceptance-handoff-$timestamp.html"
  $mdPath = Join-Path $ResolvedOutputDir "phone-acceptance-handoff-$timestamp.md"
  $latestJsonPath = Join-Path $ResolvedOutputDir "phone-acceptance-handoff-latest.json"
  $latestHtmlPath = Join-Path $ResolvedOutputDir "phone-acceptance-handoff-latest.html"
  $latestMdPath = Join-Path $ResolvedOutputDir "phone-acceptance-handoff-latest.md"
  $status = if ($same.status -eq "ready-for-phone" -and $tail.status -eq "ready-for-phone") { "both-ready-for-phone" } elseif ($same.status -eq "ready-for-phone") { "same-wifi-ready" } else { "setup-needed" }

  $report = [pscustomobject]@{
    ok = $true
    generatedAt = (Get-Date).ToString("o")
    status = $status
    outputDir = "$ResolvedOutputDir"
    dashboardHtmlPath = Join-Path $ResolvedOutputDir "phone-acceptance-dashboard-latest.html"
    nextMarkdownPath = Join-Path $ResolvedOutputDir "phone-acceptance-next-latest.md"
    evidenceBundleMarkdownPath = Join-Path $ResolvedOutputDir "remote-controller-evidence-bundle-latest.md"
    qaReportPath = Join-Path $ResolvedOutputDir "qa-report-latest.json"
    qaReportMarkdownPath = Join-Path $ResolvedOutputDir "qa-report-latest.md"
    qaGeneratedAt = if ($qa) { "$($qa.generatedAt)" } else { "" }
    qaTimestampedReportPath = if ($qa -and $qa.reportJsonPath) { "$($qa.reportJsonPath)" } else { "" }
    qaTimestampedReportMarkdownPath = if ($qa -and $qa.reportMarkdownPath) { "$($qa.reportMarkdownPath)" } else { "" }
    qaOk = if ($qa) { [bool]$qa.ok } else { $false }
    qaPass = if ($qa -and $qa.nodeTests -and $qa.nodeTests.summary) { [int]$qa.nodeTests.summary.pass } else { 0 }
    qaFail = if ($qa -and $qa.nodeTests -and $qa.nodeTests.summary) { [int]$qa.nodeTests.summary.fail } else { -1 }
    qaSelfTests = if ($qa -and $qa.selfTests) { @($qa.selfTests).Count } else { 0 }
    qaHostMode = if ($qa -and $qa.host) { "$($qa.host.mode)" } else { "" }
    currentPin = $currentPin
    gates = @($same, $tail)
    handoffJsonPath = $jsonPath
    handoffHtmlPath = $htmlPath
    handoffMarkdownPath = $mdPath
    latestHandoffJsonPath = $latestJsonPath
    latestHandoffHtmlPath = $latestHtmlPath
    latestHandoffMarkdownPath = $latestMdPath
  }

  $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $latestJsonPath -Encoding UTF8
  Write-HandoffHtml -Report $report -Path $htmlPath
  Write-HandoffHtml -Report $report -Path $latestHtmlPath
  Write-HandoffMarkdown -Report $report -Path $mdPath
  Write-HandoffMarkdown -Report $report -Path $latestMdPath
  if ($Open) { Start-Process $htmlPath }
  return $report
}

if ($SelfTest) {
  $tempOutput = Join-Path ([System.IO.Path]::GetTempPath()) "remote-acceptance-handoff-$([guid]::NewGuid().ToString('N'))"
  $oldOutput = $script:ResolvedOutputDir
  $script:ResolvedOutputDir = $tempOutput
  try {
    New-Item -ItemType Directory -Path $tempOutput -Force | Out-Null
    $qrPath = Join-Path $tempOutput "same-qr.svg"
    $tailscaleQrPath = Join-Path $tempOutput "tailscale-qr.svg"
    "<svg xmlns=""http://www.w3.org/2000/svg"" viewBox=""0 0 10 10""><rect width=""10"" height=""10"" fill=""white""/><rect x=""1"" y=""1"" width=""8"" height=""8"" fill=""black""/></svg>" | Set-Content -LiteralPath $qrPath -Encoding UTF8
    "<svg xmlns=""http://www.w3.org/2000/svg"" viewBox=""0 0 10 10""><rect width=""10"" height=""10"" fill=""white""/><rect x=""2"" y=""2"" width=""6"" height=""6"" fill=""black""/></svg>" | Set-Content -LiteralPath $tailscaleQrPath -Encoding UTF8
    [pscustomobject]@{
      ok = $true
      gate = "same-wifi"
      status = "ready-for-phone"
      readyStatusPath = Join-Path $tempOutput "phone-acceptance-ready-same-wifi-latest.json"
      preparedSessionPath = Join-Path $tempOutput "phone-acceptance-session-same-wifi-latest.json"
      runCardHtml = Join-Path $tempOutput "same.html"
      hostConsole = "http://127.0.0.1:4317/host?key=selftest-bad-key"
      phoneUrls = @("http://192.168.1.20:4317?acceptance=1&gate=same-wifi&step=physical-phone-proof")
      primaryPhoneUrl = "http://192.168.1.20:4317?acceptance=1&gate=same-wifi&step=physical-phone-proof"
      setupBlockerCount = 0
      physicalBlockerCount = 2
      secondaryPhoneUrls = @()
      shortLivedPin = [pscustomobject]@{
        available = $true
        pin = "123456"
        secondsRemaining = 120
        refreshedAt = (Get-Date).ToString("o")
        error = ""
      }
      nextCommand = "npm run acceptance:phone -- -Gate same-wifi -SkipStart -RequireReady"
      stopCommand = "npm run acceptance:stop -- -Gate same-wifi"
      failedChecks = @([pscustomobject]@{ name = "phone proof log exists"; detail = "event=acceptance.phoneMark"; nextAction = "" })
      prepareWarnings = @()
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-ready-same-wifi-latest.json") -Encoding UTF8
    [pscustomobject]@{
      ok = $false
      gate = "tailscale"
      status = "setup-needed"
      readyStatusPath = Join-Path $tempOutput "phone-acceptance-ready-tailscale-latest.json"
      preparedSessionPath = Join-Path $tempOutput "phone-acceptance-session-tailscale-latest.json"
      runCardHtml = Join-Path $tempOutput "tailscale.html"
      hostConsole = "http://127.0.0.1:4317/host?key=selftest-bad-key"
      phoneUrls = @("http://100.64.0.1:4317?acceptance=1&gate=tailscale&step=physical-phone-proof")
      primaryPhoneUrl = "http://100.64.0.1:4317?acceptance=1&gate=tailscale&step=physical-phone-proof"
      setupBlockerCount = 0
      physicalBlockerCount = 0
      readyActions = @("Scan the Tailscale QR code or open the Tailscale phone URL.")
      failedChecks = @([pscustomobject]@{ name = "prepare: tailscale URL"; detail = "No Tailscale URL is advertised."; nextAction = "Install Tailscale." })
      prepareWarnings = @()
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-ready-tailscale-latest.json") -Encoding UTF8
    [pscustomobject]@{
      qrCodes = @([pscustomobject]@{ url = "http://192.168.1.20:4317?acceptance=1&gate=same-wifi&step=physical-phone-proof"; path = $qrPath })
      shortLivedPin = [pscustomobject]@{
        available = $true
        pin = "123456"
        secondsRemaining = 120
        refreshedAt = (Get-Date).ToString("o")
        error = ""
      }
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-session-same-wifi-latest.json") -Encoding UTF8
    [pscustomobject]@{
      qrCodes = @([pscustomobject]@{ url = "http://100.64.0.1:4317?acceptance=1&gate=tailscale&step=physical-phone-proof"; path = $tailscaleQrPath })
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-session-tailscale-latest.json") -Encoding UTF8
    [pscustomobject]@{
      gates = @(
        [pscustomobject]@{ gate = "same-wifi"; verifierOk = $false; latestVerifierJsonPath = Join-Path $tempOutput "phone-acceptance-verification-same-wifi-latest.json" },
        [pscustomobject]@{ gate = "tailscale"; verifierOk = $false; latestVerifierJsonPath = Join-Path $tempOutput "phone-acceptance-verification-tailscale-latest.json" }
      )
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempOutput "remote-controller-evidence-bundle-latest.json") -Encoding UTF8
    "same" | Set-Content -LiteralPath (Join-Path $tempOutput "same.html") -Encoding UTF8
    "tail" | Set-Content -LiteralPath (Join-Path $tempOutput "tailscale.html") -Encoding UTF8
    "same watch" | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-watch-same-wifi-latest.md") -Encoding UTF8
    "{}" | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-watch-same-wifi-latest.json") -Encoding UTF8
    "tailscale watch" | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-watch-tailscale-latest.md") -Encoding UTF8
    "{}" | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-watch-tailscale-latest.json") -Encoding UTF8
    "verifier" | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-verification-same-wifi-latest.json") -Encoding UTF8
    "verifier" | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-verification-tailscale-latest.json") -Encoding UTF8
    [pscustomobject]@{
      ok = $true
      generatedAt = (Get-Date).ToString("o")
      reportJsonPath = Join-Path $tempOutput "qa-report-20260523-000000.json"
      reportMarkdownPath = Join-Path $tempOutput "qa-report-20260523-000000.md"
      host = [pscustomobject]@{ mode = "milestone-2-screen-capture" }
      nodeTests = [pscustomobject]@{ summary = [pscustomobject]@{ pass = 37; fail = 0 } }
      selfTests = 1..21 | ForEach-Object { [pscustomobject]@{ name = "self-$_"; ok = $true } }
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempOutput "qa-report-latest.json") -Encoding UTF8
    "qa report" | Set-Content -LiteralPath (Join-Path $tempOutput "qa-report-latest.md") -Encoding UTF8
    "qa report" | Set-Content -LiteralPath (Join-Path $tempOutput "qa-report-20260523-000000.json") -Encoding UTF8
    "qa report" | Set-Content -LiteralPath (Join-Path $tempOutput "qa-report-20260523-000000.md") -Encoding UTF8

    $report = New-HandoffReport
    $html = Get-Content -Raw -LiteralPath $report.handoffHtmlPath
    $markdown = Get-Content -Raw -LiteralPath $report.handoffMarkdownPath
    $ok = (Test-Path -LiteralPath $report.handoffHtmlPath) -and
      (Test-Path -LiteralPath $report.latestHandoffHtmlPath) -and
      ($html -match "Physical Phone Acceptance Handoff") -and
      ($html -match "Mark Proof") -and
      ($html -match "same-wifi") -and
      ($html -match "tailscale") -and
      ($html -match "QA report") -and
      ($html -match "watch Markdown") -and
      ($html -match "Current PIN") -and
      ($html -match "123456") -and
      ($html -match "Tailscale phone acceptance QR") -and
      ($html -match [regex]::Escape((Split-Path -Leaf $tailscaleQrPath))) -and
      ($html -match "host console") -and
      ($html -match "127.0.0.1:4317/host") -and
      ($markdown -match "Latest watch Markdown") -and
      ($markdown -match "Current PIN") -and
      ($markdown -match "123456") -and
      ($markdown -match "Final Commands") -and
      ($markdown -match "-RequireReady") -and
      ($markdown -match "npm run acceptance:finalize") -and
      ($html -match "acceptance:finalize")
    [pscustomobject]@{
      ok = $ok
      status = $report.status
      writesLatestHtml = Test-Path -LiteralPath $report.latestHandoffHtmlPath
      includesSameWifiGate = $html -match "same-wifi"
      includesTailscaleGate = $html -match "tailscale"
      includesFinalCommands = $markdown -match "Final Commands"
      includesCurrentPin = $markdown -match "123456"
      includesTailscaleQr = ($html -match "Tailscale phone acceptance QR") -and ($html -match [regex]::Escape((Split-Path -Leaf $tailscaleQrPath)))
      includesHostConsoleLinks = ($html -match "host console") -and ($html -match "127.0.0.1:4317/host")
      includesRequireReady = $markdown -match "-RequireReady"
    } | ConvertTo-Json -Compress
    if (-not $ok) { exit 1 }
    exit 0
  } finally {
    $script:ResolvedOutputDir = $oldOutput
  }
}

$report = New-HandoffReport
$report | ConvertTo-Json -Depth 10 -Compress
