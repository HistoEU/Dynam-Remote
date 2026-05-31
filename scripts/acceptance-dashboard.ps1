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

function Escape-Html {
  param([object]$Value)
  return [System.Net.WebUtility]::HtmlEncode("$Value")
}

function ConvertTo-FileHref {
  param([string]$PathValue)
  if ([string]::IsNullOrWhiteSpace($PathValue)) { return "" }
  $resolved = if ([System.IO.Path]::IsPathRooted($PathValue)) { $PathValue } else { Join-Path $Root $PathValue }
  return "file:///$((Resolve-Path -LiteralPath $resolved -ErrorAction SilentlyContinue) -replace '\\', '/')"
}

function New-LinkHtml {
  param(
    [string]$Text,
    [string]$Href
  )
  if ([string]::IsNullOrWhiteSpace($Href)) { return "<span class=""muted"">none</span>" }
  $safeText = Escape-Html $Text
  $safeHref = Escape-Html $Href
  return "<a href=""$safeHref"">$safeText</a>"
}

function New-CommandRows {
  param([object]$Actions)
  $rows = @(ConvertTo-StringArray $Actions | ForEach-Object {
    "<li><code>$(Escape-Html $_)</code></li>"
  })
  if ($rows.Count -eq 0) { return "<li><span class=""muted"">No action recorded yet.</span></li>" }
  return ($rows -join [Environment]::NewLine)
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

function Get-EvidenceGate {
  param(
    [object]$Evidence,
    [string]$Gate
  )
  if (-not $Evidence -or -not $Evidence.gates) { return $null }
  return @($Evidence.gates | Where-Object { $_.gate -eq $Gate } | Select-Object -First 1)
}

function New-GateCardHtml {
  param(
    [object]$Gate,
    [object]$EvidenceGate
  )

  $gateName = Escape-Html $Gate.gate
  $status = Escape-Html $Gate.status
  $statusClass = if ($Gate.status -eq "ready-for-phone") { "ready" } elseif ($Gate.status -eq "setup-needed") { "setup" } else { "blocked" }
  $runCardHref = ConvertTo-FileHref "$($Gate.runCardHtml)"
  $readyHref = ConvertTo-FileHref "$($Gate.readyPath)"
  $watchJsonHref = ConvertTo-FileHref (Join-Path $ResolvedOutputDir "phone-acceptance-watch-$($Gate.gate)-latest.json")
  $watchMarkdownHref = ConvertTo-FileHref (Join-Path $ResolvedOutputDir "phone-acceptance-watch-$($Gate.gate)-latest.md")
  $verifierText = if ($EvidenceGate -and $EvidenceGate.verifierOk -eq $true) { "passed" } else { "not passed" }
  $verifierHref = if ($EvidenceGate) { ConvertTo-FileHref "$($EvidenceGate.verifierJsonPath)" } else { "" }
  $latestVerifierHref = if ($EvidenceGate) { ConvertTo-FileHref "$($EvidenceGate.latestVerifierJsonPath)" } else { "" }
  $verifierFailedRows = if ($EvidenceGate -and $EvidenceGate.failedChecks) {
    New-CheckRows $EvidenceGate.failedChecks
  } else {
    "<li><span class=""muted"">No saved verifier checks found. Run <code>npm run evidence:bundle</code>.</span></li>"
  }
  $missing = if ($EvidenceGate -and $EvidenceGate.missingRequiredArtifacts) {
    (ConvertTo-StringArray $EvidenceGate.missingRequiredArtifacts) -join ", "
  } else {
    "none recorded"
  }

@"
<article class="gate-card $statusClass">
  <div class="gate-top">
    <div>
      <p class="label">$gateName</p>
      <h2>$status</h2>
    </div>
    <span class="verifier">verifier: $(Escape-Html $verifierText)</span>
  </div>
  <div class="links">
    $(New-LinkHtml -Text "open run card" -Href $runCardHref)
    $(New-LinkHtml -Text "ready JSON" -Href $readyHref)
  </div>
  <section>
    <h3>Live Proof Watch</h3>
    <div class="links compact-links">
      $(New-LinkHtml -Text "watch Markdown" -Href $watchMarkdownHref)
      $(New-LinkHtml -Text "watch JSON" -Href $watchJsonHref)
    </div>
  </section>
  <section>
    <h3>Verifier Evidence</h3>
    <div class="links compact-links">
      $(New-LinkHtml -Text "latest verifier JSON" -Href $latestVerifierHref)
      $(New-LinkHtml -Text "timestamped verifier JSON" -Href $verifierHref)
    </div>
    <ul>
      $verifierFailedRows
    </ul>
  </section>
  <section>
    <h3>Primary Phone URL</h3>
    <p class="primary-url">$(if ($Gate.primaryPhoneUrl) { Escape-Html $Gate.primaryPhoneUrl } else { "<span class=""muted"">none</span>" })</p>
  </section>
  <section>
    <h3>Phone URLs</h3>
    <ul class="url-list">
      $(New-UrlRows $Gate.phoneUrls)
    </ul>
  </section>
  <section>
    <h3>Next Actions</h3>
    <ol>
      $(New-CommandRows $Gate.actions)
    </ol>
  </section>
  <section>
    <h3>Current Blockers</h3>
    <ul>
      $(New-CheckRows $Gate.failedChecks)
    </ul>
  </section>
  <section>
    <h3>Warnings</h3>
    <ul>
      $(New-CheckRows $Gate.warnings)
    </ul>
  </section>
  <p class="missing">Missing required artifacts: $(Escape-Html $missing)</p>
</article>
"@
}

function New-DashboardModel {
  New-Item -ItemType Directory -Path $ResolvedOutputDir -Force | Out-Null
  $nextPath = Join-Path $ResolvedOutputDir "phone-acceptance-next-latest.json"
  $bundlePath = Join-Path $ResolvedOutputDir "remote-controller-evidence-bundle-latest.json"
  $sameReadyPath = Join-Path $ResolvedOutputDir "phone-acceptance-ready-same-wifi-latest.json"
  $tailscaleReadyPath = Join-Path $ResolvedOutputDir "phone-acceptance-ready-tailscale-latest.json"
  $qaPath = Join-Path $ResolvedOutputDir "qa-report-latest.json"
  $qaMarkdownPath = Join-Path $ResolvedOutputDir "qa-report-latest.md"
  $next = Read-JsonFile $nextPath
  $bundle = Read-JsonFile $bundlePath
  $sameReady = Read-JsonFile $sameReadyPath
  $tailscaleReady = Read-JsonFile $tailscaleReadyPath
  $qa = Read-JsonFile $qaPath

  $gates = if ($next -and $next.gates) { @($next.gates) } else { @() }
  return [pscustomobject]@{
    ok = $true
    generatedAt = (Get-Date).ToString("o")
    status = if ($next) { "$($next.status)" } else { "missing-next-actions" }
    complete = if ($bundle) { [bool]$bundle.ok } else { $false }
    nextPath = $nextPath
    evidenceBundlePath = $bundlePath
    sameWifiReadyPath = $sameReadyPath
    tailscaleReadyPath = $tailscaleReadyPath
    qaReportPath = $qaPath
    qaReportMarkdownPath = $qaMarkdownPath
    qaGeneratedAt = if ($qa) { "$($qa.generatedAt)" } else { "" }
    qaTimestampedReportPath = if ($qa -and $qa.reportJsonPath) { "$($qa.reportJsonPath)" } else { "" }
    qaTimestampedReportMarkdownPath = if ($qa -and $qa.reportMarkdownPath) { "$($qa.reportMarkdownPath)" } else { "" }
    qaOk = if ($qa) { [bool]$qa.ok } else { $false }
    qaPass = if ($qa -and $qa.nodeTests -and $qa.nodeTests.summary) { [int]$qa.nodeTests.summary.pass } else { 0 }
    qaFail = if ($qa -and $qa.nodeTests -and $qa.nodeTests.summary) { [int]$qa.nodeTests.summary.fail } else { -1 }
    qaSelfTests = if ($qa -and $qa.selfTests) { @($qa.selfTests).Count } else { 0 }
    qaHostMode = if ($qa -and $qa.host) { "$($qa.host.mode)" } else { "" }
    sameWifiPhoneUrls = if ($sameReady) { ConvertTo-StringList $sameReady.phoneUrls } else { ConvertTo-StringList @() }
    tailscalePhoneUrls = if ($tailscaleReady) { ConvertTo-StringList $tailscaleReady.phoneUrls } else { ConvertTo-StringList @() }
    gates = @($gates)
    evidenceGates = if ($bundle -and $bundle.gates) { @($bundle.gates) } else { @() }
  }
}

function Write-DashboardHtml {
  param(
    [object]$Dashboard,
    [string]$Path
  )

  $bundleHref = ConvertTo-FileHref $Dashboard.evidenceBundlePath
  $nextHref = ConvertTo-FileHref $Dashboard.nextPath
  $sameHref = ConvertTo-FileHref $Dashboard.sameWifiReadyPath
  $tailscaleHref = ConvertTo-FileHref $Dashboard.tailscaleReadyPath
  $qaHref = ConvertTo-FileHref $Dashboard.qaReportPath
  $qaMarkdownHref = ConvertTo-FileHref $Dashboard.qaReportMarkdownPath
  $gateCards = @($Dashboard.gates | ForEach-Object {
    New-GateCardHtml -Gate $_ -EvidenceGate (Get-EvidenceGate -Evidence ([pscustomobject]@{ gates = $Dashboard.evidenceGates }) -Gate "$($_.gate)")
  })
  if ($gateCards.Count -eq 0) {
    $gateCards = @("<article class=""gate-card blocked""><h2>No latest next-action artifact</h2><p>Run <code>npm run acceptance:next</code>, then regenerate this dashboard.</p></article>")
  }
  $completionState = if ($Dashboard.complete) { "complete evidence present" } else { "physical evidence still required" }

  $html = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Remote Controller Physical Acceptance Dashboard</title>
  <style>
    :root {
      color-scheme: light;
      --ink: #17212b;
      --muted: #5d6978;
      --line: #d8dee6;
      --paper: #f7f8fa;
      --panel: #ffffff;
      --good: #0f766e;
      --warn: #a16207;
      --bad: #b91c1c;
      --link: #1d4ed8;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: "Segoe UI", Arial, sans-serif;
      color: var(--ink);
      background: var(--paper);
      line-height: 1.45;
    }
    header {
      padding: 28px clamp(18px, 4vw, 48px) 18px;
      border-bottom: 1px solid var(--line);
      background: #ffffff;
    }
    main { padding: 24px clamp(18px, 4vw, 48px) 40px; }
    h1 { margin: 0 0 8px; font-size: clamp(24px, 3vw, 38px); letter-spacing: 0; }
    h2 { margin: 2px 0 0; font-size: 22px; letter-spacing: 0; }
    h3 { margin: 18px 0 8px; font-size: 14px; text-transform: uppercase; letter-spacing: 0; color: var(--muted); }
    a { color: var(--link); overflow-wrap: anywhere; }
    code {
      font-family: Consolas, "Liberation Mono", monospace;
      font-size: 0.94em;
      background: #eef2f7;
      border: 1px solid #d7dee8;
      border-radius: 6px;
      padding: 2px 5px;
      overflow-wrap: anywhere;
    }
    .summary {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(210px, 1fr));
      gap: 12px;
      margin-top: 18px;
    }
    .summary-card, .gate-card {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 16px;
    }
    .summary-card strong { display: block; font-size: 18px; margin-top: 4px; }
    .label, .muted { color: var(--muted); }
    .label { margin: 0; font-size: 12px; text-transform: uppercase; letter-spacing: 0; }
    .gate-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
      gap: 16px;
      align-items: start;
    }
    .gate-card.ready { border-top: 5px solid var(--good); }
    .gate-card.setup { border-top: 5px solid var(--warn); }
    .gate-card.blocked { border-top: 5px solid var(--bad); }
    .gate-top {
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      gap: 12px;
    }
    .verifier {
      white-space: nowrap;
      border: 1px solid var(--line);
      border-radius: 999px;
      padding: 5px 9px;
      color: var(--muted);
      font-size: 12px;
    }
    .links {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      margin: 14px 0;
    }
    .compact-links { margin: 6px 0 10px; }
    ul, ol { margin: 0; padding-left: 22px; }
    li + li { margin-top: 7px; }
    .url-list li { overflow-wrap: anywhere; }
    .primary-url { margin: 0; font-weight: 700; overflow-wrap: anywhere; }
    .missing {
      margin: 18px 0 0;
      padding-top: 12px;
      border-top: 1px solid var(--line);
      color: var(--muted);
      overflow-wrap: anywhere;
    }
    .final-commands {
      margin-top: 18px;
      background: #17212b;
      color: #f8fafc;
      border-radius: 8px;
      padding: 16px;
    }
    .final-commands code {
      display: block;
      margin-top: 8px;
      color: #f8fafc;
      background: transparent;
      border: 0;
      padding: 0;
    }
  </style>
</head>
<body>
  <header>
    <p class="label">Physical acceptance</p>
    <h1>Remote Controller Dashboard</h1>
    <p class="muted">Generated $(Escape-Html $Dashboard.generatedAt). This dashboard is a launch surface only; it does not replace verifier evidence or the completion audit.</p>
    <div class="summary">
      <div class="summary-card"><span class="label">Overall status</span><strong>$(Escape-Html $Dashboard.status)</strong></div>
      <div class="summary-card"><span class="label">Completion state</span><strong>$(Escape-Html $completionState)</strong></div>
      <div class="summary-card"><span class="label">Same-Wi-Fi URLs</span><strong>$(@($Dashboard.sameWifiPhoneUrls).Count)</strong></div>
      <div class="summary-card"><span class="label">Tailscale URLs</span><strong>$(@($Dashboard.tailscalePhoneUrls).Count)</strong></div>
      <div class="summary-card"><span class="label">Automated QA</span><strong>$(if ($Dashboard.qaOk) { "passed" } else { "missing" })</strong><span class="muted">$($Dashboard.qaPass) pass / $($Dashboard.qaFail) fail / $($Dashboard.qaSelfTests) self-tests</span></div>
    </div>
  </header>
  <main>
    <section class="links">
      $(New-LinkHtml -Text "latest next actions" -Href $nextHref)
      $(New-LinkHtml -Text "latest evidence bundle" -Href $bundleHref)
      $(New-LinkHtml -Text "same-Wi-Fi ready JSON" -Href $sameHref)
      $(New-LinkHtml -Text "Tailscale ready JSON" -Href $tailscaleHref)
      $(New-LinkHtml -Text "QA report JSON" -Href $qaHref)
      $(New-LinkHtml -Text "QA report Markdown" -Href $qaMarkdownHref)
    </section>
    <section class="gate-grid">
      $($gateCards -join [Environment]::NewLine)
    </section>
    <section class="final-commands">
      <strong>Final command after both physical runs pass</strong>
      <code>npm run acceptance:verify:save -- -Gate same-wifi</code>
      <code>npm run acceptance:verify:save -- -Gate tailscale</code>
      <code>npm run acceptance:finalize</code>
    </section>
  </main>
</body>
</html>
"@
  $html | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-AcceptanceDashboard {
  $dashboard = New-DashboardModel
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $jsonPath = Join-Path $ResolvedOutputDir "phone-acceptance-dashboard-$timestamp.json"
  $htmlPath = Join-Path $ResolvedOutputDir "phone-acceptance-dashboard-$timestamp.html"
  $latestJsonPath = Join-Path $ResolvedOutputDir "phone-acceptance-dashboard-latest.json"
  $latestHtmlPath = Join-Path $ResolvedOutputDir "phone-acceptance-dashboard-latest.html"
  $dashboard | Add-Member -NotePropertyName dashboardJsonPath -NotePropertyValue $jsonPath -Force
  $dashboard | Add-Member -NotePropertyName dashboardHtmlPath -NotePropertyValue $htmlPath -Force
  $dashboard | Add-Member -NotePropertyName latestDashboardJsonPath -NotePropertyValue $latestJsonPath -Force
  $dashboard | Add-Member -NotePropertyName latestDashboardHtmlPath -NotePropertyValue $latestHtmlPath -Force
  $dashboard | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  $dashboard | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $latestJsonPath -Encoding UTF8
  Write-DashboardHtml -Dashboard $dashboard -Path $htmlPath
  Write-DashboardHtml -Dashboard $dashboard -Path $latestHtmlPath
  return $dashboard
}

if ($SelfTest) {
  $tempOutput = Join-Path ([System.IO.Path]::GetTempPath()) "remote-acceptance-dashboard-$([guid]::NewGuid().ToString('N'))"
  New-Item -ItemType Directory -Path $tempOutput -Force | Out-Null
  $oldOutput = $script:ResolvedOutputDir
  $script:ResolvedOutputDir = $tempOutput
  try {
    [pscustomobject]@{
      ok = $true
      status = "some-ready"
      gates = @(
        [pscustomobject]@{
          gate = "same-wifi"
          status = "ready-for-phone"
          readyPath = (Join-Path $tempOutput "phone-acceptance-ready-same-wifi-latest.json")
          runCardHtml = (Join-Path $tempOutput "same.html")
          phoneUrls = @("http://192.168.1.20:4317?acceptance=1&gate=same-wifi&step=physical-phone-proof")
          failedChecks = @([pscustomobject]@{ name = "phone proof log exists"; detail = "event=acceptance.phoneMark" })
          warnings = @()
          actions = @("Open this URL on the phone: http://192.168.1.20:4317?acceptance=1&gate=same-wifi&step=physical-phone-proof")
        },
        [pscustomobject]@{
          gate = "tailscale"
          status = "setup-needed"
          readyPath = (Join-Path $tempOutput "phone-acceptance-ready-tailscale-latest.json")
          runCardHtml = (Join-Path $tempOutput "tailscale.html")
          phoneUrls = @()
          failedChecks = @([pscustomobject]@{ name = "prepare: tailscale URL"; detail = "missing" })
          warnings = @()
          actions = @("Review the latest Tailscale bootstrap report")
        }
      )
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-next-latest.json") -Encoding UTF8
    [pscustomobject]@{
      ok = $false
      gates = @(
        [pscustomobject]@{
          gate = "same-wifi"
          verifierOk = $false
          verifierJsonPath = (Join-Path $tempOutput "phone-acceptance-verification-same-wifi-20260523-000000.json")
          latestVerifierJsonPath = (Join-Path $tempOutput "phone-acceptance-verification-same-wifi-latest.json")
          failedChecks = @([pscustomobject]@{ name = "phone proof log exists"; detail = "event=acceptance.phoneMark" })
          missingRequiredArtifacts = @()
        },
        [pscustomobject]@{
          gate = "tailscale"
          verifierOk = $false
          verifierJsonPath = (Join-Path $tempOutput "phone-acceptance-verification-tailscale-20260523-000000.json")
          latestVerifierJsonPath = (Join-Path $tempOutput "phone-acceptance-verification-tailscale-latest.json")
          failedChecks = @([pscustomobject]@{ name = "verifier error"; detail = "No manual phone acceptance summary JSON was found." })
          missingRequiredArtifacts = @("manual phone summary")
        }
      )
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $tempOutput "remote-controller-evidence-bundle-latest.json") -Encoding UTF8
    "same latest" | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-verification-same-wifi-latest.json") -Encoding UTF8
    "same timestamped" | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-verification-same-wifi-20260523-000000.json") -Encoding UTF8
    "tailscale latest" | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-verification-tailscale-latest.json") -Encoding UTF8
    "tailscale timestamped" | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-verification-tailscale-20260523-000000.json") -Encoding UTF8
    [pscustomobject]@{ phoneUrls = @("http://192.168.1.20:4317?acceptance=1&gate=same-wifi&step=physical-phone-proof") } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-ready-same-wifi-latest.json") -Encoding UTF8
    [pscustomobject]@{ phoneUrls = @() } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $tempOutput "phone-acceptance-ready-tailscale-latest.json") -Encoding UTF8
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
    "same" | Set-Content -LiteralPath (Join-Path $tempOutput "same.html") -Encoding UTF8
    "tailscale" | Set-Content -LiteralPath (Join-Path $tempOutput "tailscale.html") -Encoding UTF8
    $dashboard = New-AcceptanceDashboard
    $html = Get-Content -Raw -LiteralPath $dashboard.dashboardHtmlPath
    $ok = $dashboard.ok -and
      (Test-Path -LiteralPath $dashboard.dashboardJsonPath) -and
      (Test-Path -LiteralPath $dashboard.dashboardHtmlPath) -and
      ($html -match "Remote Controller Dashboard") -and
      ($html -match "acceptance=1&amp;gate=same-wifi") -and
      ($html -match "physical evidence still required") -and
      ($html -match "latest verifier JSON") -and
      ($html -match "watch Markdown") -and
      ($html -match "phone-acceptance-verification-same-wifi-latest") -and
      ($html -match "manual phone summary") -and
      ($html -match "QA report JSON") -and
      ($html -match "acceptance:finalize")
    [pscustomobject]@{
      ok = $ok
      writesJsonAndHtml = (Test-Path -LiteralPath $dashboard.dashboardJsonPath) -and (Test-Path -LiteralPath $dashboard.dashboardHtmlPath)
      status = $dashboard.status
      gateCount = @($dashboard.gates).Count
    } | ConvertTo-Json -Compress
    if (-not $ok) { exit 1 }
    exit 0
  } finally {
    $script:ResolvedOutputDir = $oldOutput
  }
}

$dashboard = New-AcceptanceDashboard
if ($Open) {
  Start-Process -FilePath $dashboard.dashboardHtmlPath | Out-Null
}
$dashboard | ConvertTo-Json -Depth 10 -Compress
