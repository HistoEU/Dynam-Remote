param(
  [ValidateSet("same-wifi", "tailscale")]
  [string]$Gate = "same-wifi",
  [string]$HostKey = "dev-host-key",
  [int]$Port = 4317,
  [string]$NodePath = "node",
  [string]$OutputDir = "output\acceptance",
  [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$ResolvedOutputDir = Join-Path $Root $OutputDir
$DoctorScript = Join-Path $PSScriptRoot "acceptance-doctor.ps1"
$QrCliJs = Join-Path $Root "node_modules\qrcode\bin\qrcode"

function Get-PhoneAppVersion {
  $serviceWorkerPath = Join-Path $Root "public\sw.js"
  if (-not (Test-Path -LiteralPath $serviceWorkerPath -PathType Leaf)) {
    throw "Cannot derive phone app version because public\sw.js is missing."
  }
  $source = Get-Content -Raw -LiteralPath $serviceWorkerPath
  $match = [regex]::Match($source, 'remote-controller-shell-v(?<version>[0-9]+)')
  if (-not $match.Success) {
    throw "Cannot derive phone app version from public\sw.js cache name."
  }
  return $match.Groups["version"].Value
}

$PhoneAppVersion = Get-PhoneAppVersion

function Get-ListeningProcessId {
  $connection = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($connection) { return $connection.OwningProcess }
  return $null
}

function Start-HostProcess {
  param(
    [string]$StdOutPath,
    [string]$StdErrPath
  )
  $previousHostKey = $env:HOST_KEY
  $previousCaptureMode = $env:CAPTURE_MODE
  $previousHost = $env:HOST
  $previousRealInput = $env:REAL_INPUT
  $previousQualityDefault = $env:QUALITY_DEFAULT

  try {
    $env:HOST_KEY = $HostKey
    $env:CAPTURE_MODE = "screen"
    $env:REAL_INPUT = "1"
    $env:QUALITY_DEFAULT = "fast"
    $env:HOST = "::"
    "Detached host started by prepare at $((Get-Date).ToString("o")). Runtime evidence is captured through the host log export in acceptance reports." | Set-Content -LiteralPath $StdOutPath -Encoding UTF8
    "" | Set-Content -LiteralPath $StdErrPath -Encoding UTF8
    $process = Start-Process -FilePath $NodePath `
      -ArgumentList "src\server.js" `
      -WorkingDirectory "$Root" `
      -WindowStyle Hidden `
      -PassThru
    Start-Sleep -Seconds 2
    return $process
  } finally {
    if ($null -eq $previousHostKey) { Remove-Item Env:\HOST_KEY -ErrorAction SilentlyContinue } else { $env:HOST_KEY = $previousHostKey }
    if ($null -eq $previousCaptureMode) { Remove-Item Env:\CAPTURE_MODE -ErrorAction SilentlyContinue } else { $env:CAPTURE_MODE = $previousCaptureMode }
    if ($null -eq $previousHost) { Remove-Item Env:\HOST -ErrorAction SilentlyContinue } else { $env:HOST = $previousHost }
    if ($null -eq $previousRealInput) { Remove-Item Env:\REAL_INPUT -ErrorAction SilentlyContinue } else { $env:REAL_INPUT = $previousRealInput }
    if ($null -eq $previousQualityDefault) { Remove-Item Env:\QUALITY_DEFAULT -ErrorAction SilentlyContinue } else { $env:QUALITY_DEFAULT = $previousQualityDefault }
  }
}

function Invoke-Doctor {
  $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $DoctorScript -Gate $Gate -HostKey $HostKey -Port $Port -NodePath $NodePath -OutputDir $OutputDir -SkipStart
  $jsonLine = @($raw | Where-Object { "$_".Trim().StartsWith("{") }) | Select-Object -Last 1
  if (-not $jsonLine) { throw "Acceptance doctor did not return JSON." }
  return $jsonLine | ConvertFrom-Json
}

function ConvertTo-MarkdownList {
  param([object[]]$Items)
  if (-not $Items -or $Items.Count -eq 0) { return "- none" }
  return ($Items | ForEach-Object { "- $_" }) -join [Environment]::NewLine
}

function ConvertTo-CheckRows {
  param([object[]]$Items)
  if (-not $Items -or $Items.Count -eq 0) { return "| none | none |" }
  return (@($Items) | ForEach-Object {
    $detail = "$($_.detail)".Replace("|", "\|").Replace("`r", " ").Replace("`n", " ")
    $next = "$($_.nextAction)".Replace("|", "\|").Replace("`r", " ").Replace("`n", " ")
    "| $detail | $next |"
  }) -join [Environment]::NewLine
}

function ConvertTo-HtmlText {
  param([string]$Text)
  return [System.Net.WebUtility]::HtmlEncode("$Text")
}

function ConvertTo-HtmlList {
  param([object[]]$Items)
  if (-not $Items -or $Items.Count -eq 0) { return "<li>none</li>" }
  return (@($Items) | ForEach-Object { "<li>$(ConvertTo-HtmlText "$_")</li>" }) -join [Environment]::NewLine
}

function Get-ShortLivedPin {
  try {
    $pin = Invoke-RestMethod `
      -Uri "http://127.0.0.1:$Port/api/refresh-pin" `
      -Method Post `
      -Headers @{ "x-host-key" = $HostKey } `
      -Body "{}" `
      -ContentType "application/json" `
      -TimeoutSec 6
    return [pscustomobject]@{
      available = $true
      pin = "$($pin.pin)"
      secondsRemaining = if ($null -ne $pin.secondsRemaining) { [int]$pin.secondsRemaining } else { 0 }
      refreshedAt = (Get-Date).ToString("o")
      error = ""
    }
  } catch {
    return [pscustomobject]@{
      available = $false
      pin = ""
      secondsRemaining = 0
      refreshedAt = ""
      error = $_.Exception.Message
    }
  }
}

function Add-AcceptanceQuery {
  param(
    [string]$Url,
    [string]$SelectedGate
  )

  if ([string]::IsNullOrWhiteSpace($Url)) { return $Url }
  $proofUrl = "$Url"
  if ($proofUrl -notmatch "(\?|&)v=") {
    $versionSeparator = if ($proofUrl.Contains("?")) { "&" } else { "?" }
    $proofUrl = "$proofUrl${versionSeparator}v=$PhoneAppVersion"
  }
  $separator = if ($proofUrl.Contains("?")) { "&" } else { "?" }
  return "$proofUrl${separator}acceptance=1&gate=$([uri]::EscapeDataString($SelectedGate))&step=physical-phone-proof"
}

function Test-VpnLikeAddress {
  param([object]$Address)

  $name = "$($Address.name)"
  return $name -match "(?i)(vpn|nord|lynx|wireguard|zerotier|hamachi|tap|tun|wg)"
}

function Get-PhoneAddressSelection {
  param(
    [object]$State,
    [string]$SelectedGate
  )

  $addresses = if ($State -and $State.addresses) { @($State.addresses) } else { @() }
  if ($SelectedGate -eq "tailscale") {
    $tailscale = @($addresses | Where-Object { $_.kind -eq "tailscale" })
    return [pscustomobject]@{
      phoneUrls = @($tailscale | ForEach-Object { $_.url })
      secondaryPhoneUrls = @()
      allCandidatePhoneUrls = @($tailscale | ForEach-Object { $_.url })
      selectionNote = "Tailscale gate uses only Tailscale URLs so the different-Wi-Fi proof cannot accidentally use a LAN path."
    }
  }

  $lan = @($addresses | Where-Object { $_.kind -eq "lan" })
  $recommended = @($lan | Where-Object { -not (Test-VpnLikeAddress -Address $_) })
  $secondary = @($lan | Where-Object { Test-VpnLikeAddress -Address $_ })
  if ($recommended.Count -eq 0 -and $lan.Count -gt 0) {
    $recommended = $lan
    $secondary = @()
  }

  return [pscustomobject]@{
    phoneUrls = @($recommended | ForEach-Object { $_.url })
    secondaryPhoneUrls = @($secondary | ForEach-Object { "$($_.url) ($($_.name))" })
    allCandidatePhoneUrls = @($lan | ForEach-Object { $_.url })
    selectionNote = "Same-Wi-Fi gate recommends non-VPN LAN adapters first; VPN-like private adapters are shown separately."
  }
}

function Write-RunCard {
  param(
    [object]$Session,
    [string]$Path
  )

  $phoneUrls = ConvertTo-MarkdownList @($Session.phoneUrls)
  $secondaryPhoneUrls = ConvertTo-MarkdownList @($Session.secondaryPhoneUrls)
  $lanUrls = ConvertTo-MarkdownList @($Session.lanUrls)
  $tailscaleUrls = ConvertTo-MarkdownList @($Session.tailscaleUrls)
  $qrList = if ($Session.qrCodes -and @($Session.qrCodes).Count -gt 0) {
    (@($Session.qrCodes) | ForEach-Object { "- $($_.url) -> $($_.path)" }) -join [Environment]::NewLine
  } else {
    "- none"
  }
  $qrErrorList = ConvertTo-MarkdownList @($Session.qrErrors)
  $warningRows = ConvertTo-CheckRows @($Session.warnings)
  $failureRows = ConvertTo-CheckRows @($Session.failures)
  $statusLine = if ($Session.ok) { "Ready to start this gate." } else { "Not ready. Fix the failures before starting this gate." }
  $pinText = if ($Session.shortLivedPin -and $Session.shortLivedPin.available) { "$($Session.shortLivedPin.pin)" } else { "Unavailable" }
  $pinMeta = if ($Session.shortLivedPin -and $Session.shortLivedPin.available) {
    "Refreshed: $($Session.shortLivedPin.refreshedAt). Expires in about $($Session.shortLivedPin.secondsRemaining) seconds."
  } elseif ($Session.shortLivedPin) {
    "Could not refresh PIN: $($Session.shortLivedPin.error)"
  } else {
    "Could not refresh PIN."
  }

  $markdown = @"
# Physical Phone Acceptance Session

Generated: $($Session.generatedAt)
Gate: $($Session.gate)
Status: $statusLine
Host PID: $($Session.pid)
Started by prepare: $($Session.startedByPrepare)
Doctor status: $($Session.doctorStatus)

## Open On Laptop

- Host console: $($Session.hostConsole)
- Doctor report: $($Session.doctorReportMarkdown)
- Doctor JSON: $($Session.doctorReportJson)
- Host stdout log: $(if ($Session.hostStdOutPath) { $Session.hostStdOutPath } else { "not captured for pre-existing host" })
- Host stderr log: $(if ($Session.hostStdErrPath) { $Session.hostStdErrPath } else { "not captured for pre-existing host" })

## Open On Phone

$phoneUrls

## Current PIN

$pinText

$pinMeta

Selection note: $($Session.selectionNote)

## Secondary Phone URLs

$secondaryPhoneUrls

## Scan QR Files

$qrList

QR generation issues:

$qrErrorList

## LAN URLs

$lanUrls

## Tailscale URLs

$tailscaleUrls

## Warnings

| Detail | Next action |
| --- | --- |
$warningRows

## Failures

| Detail | Next action |
| --- | --- |
$failureRows

## Next Commands

Run the guided phone checklist against this running host:

~~~powershell
$($Session.nextCommand)
~~~

Stop this prepared host afterward:

~~~powershell
$($Session.stopCommand)
~~~

## Evidence Reminder

- Pair from the phone URL above.
- Approve the phone on the laptop host console.
- Tap Mark Proof from the controller proof banner or phone Settings before ending the run.
- Keep the generated manual phone run notes, pre/post reports, host logs, this run card, and the verifier output together.
"@

  $markdown | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-HtmlRunCard {
  param(
    [object]$Session,
    [string]$Path
  )

  $statusLine = if ($Session.ok) { "Ready to start this gate." } else { "Not ready. Fix the failures before starting this gate." }
  $pinText = if ($Session.shortLivedPin -and $Session.shortLivedPin.available) { "$($Session.shortLivedPin.pin)" } else { "Unavailable" }
  $pinMeta = if ($Session.shortLivedPin -and $Session.shortLivedPin.available) {
    "Refreshed: $($Session.shortLivedPin.refreshedAt). Expires in about $($Session.shortLivedPin.secondsRemaining) seconds."
  } elseif ($Session.shortLivedPin) {
    "Could not refresh PIN: $($Session.shortLivedPin.error)"
  } else {
    "Could not refresh PIN."
  }
  $phoneUrls = ConvertTo-HtmlList @($Session.phoneUrls)
  $secondaryPhoneUrls = ConvertTo-HtmlList @($Session.secondaryPhoneUrls)
  $lanUrls = ConvertTo-HtmlList @($Session.lanUrls)
  $tailscaleUrls = ConvertTo-HtmlList @($Session.tailscaleUrls)
  $qrCards = if ($Session.qrCodes -and @($Session.qrCodes).Count -gt 0) {
    (@($Session.qrCodes) | ForEach-Object {
      $fileName = [System.IO.Path]::GetFileName("$($_.path)")
      @"
      <article class="qr-card">
        <img src="$(ConvertTo-HtmlText $fileName)" alt="QR code for $(ConvertTo-HtmlText "$($_.url)")">
        <p>$(ConvertTo-HtmlText "$($_.url)")</p>
      </article>
"@
    }) -join [Environment]::NewLine
  } else {
    "<p>none</p>"
  }
  $qrErrors = ConvertTo-HtmlList @($Session.qrErrors)
  $warningRows = if ($Session.warnings -and @($Session.warnings).Count -gt 0) {
    (@($Session.warnings) | ForEach-Object {
      "<tr><td>$(ConvertTo-HtmlText "$($_.detail)")</td><td>$(ConvertTo-HtmlText "$($_.nextAction)")</td></tr>"
    }) -join [Environment]::NewLine
  } else {
    "<tr><td>none</td><td>none</td></tr>"
  }
  $failureRows = if ($Session.failures -and @($Session.failures).Count -gt 0) {
    (@($Session.failures) | ForEach-Object {
      "<tr><td>$(ConvertTo-HtmlText "$($_.detail)")</td><td>$(ConvertTo-HtmlText "$($_.nextAction)")</td></tr>"
    }) -join [Environment]::NewLine
  } else {
    "<tr><td>none</td><td>none</td></tr>"
  }

  $html = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Physical Phone Acceptance Session</title>
  <style>
    :root { color-scheme: dark; font-family: Segoe UI, Arial, sans-serif; background: #101418; color: #f5f7fb; }
    body { margin: 0; padding: 24px; background: #101418; }
    main { max-width: 1120px; margin: 0 auto; }
    h1, h2 { margin: 0 0 12px; }
    h1 { font-size: 30px; }
    h2 { font-size: 18px; margin-top: 28px; color: #b9c7d9; }
    .status { display: inline-block; padding: 6px 10px; border-radius: 6px; background: #123827; color: #7ef0b2; font-weight: 700; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 16px; }
    .panel { border: 1px solid #2b3542; border-radius: 8px; padding: 16px; background: #151b22; }
    .qr-card { background: #ffffff; color: #111827; border-radius: 8px; padding: 16px; text-align: center; }
    .qr-card img { width: min(320px, 100%); height: auto; display: block; margin: 0 auto 12px; }
    .qr-card p { overflow-wrap: anywhere; margin: 0; font-size: 14px; }
    code, pre { background: #0b0f14; color: #e6edf3; border-radius: 6px; padding: 10px; display: block; overflow-x: auto; }
    table { width: 100%; border-collapse: collapse; }
    th, td { border: 1px solid #2b3542; padding: 8px; text-align: left; vertical-align: top; }
    a { color: #8bd3ff; }
    li { margin: 6px 0; overflow-wrap: anywhere; }
  </style>
</head>
<body>
<main>
  <h1>Physical Phone Acceptance Session</h1>
  <p class="status">$(ConvertTo-HtmlText $statusLine)</p>
  <section class="grid">
    <div class="panel">
      <h2>Session</h2>
      <ul>
        <li>Generated: $(ConvertTo-HtmlText "$($Session.generatedAt)")</li>
        <li>Gate: $(ConvertTo-HtmlText "$($Session.gate)")</li>
        <li>Host PID: $(ConvertTo-HtmlText "$($Session.pid)")</li>
        <li>Doctor status: $(ConvertTo-HtmlText "$($Session.doctorStatus)")</li>
      </ul>
    </div>
    <div class="panel">
      <h2>Laptop</h2>
      <ul>
        <li>Host console: <a href="$(ConvertTo-HtmlText "$($Session.hostConsole)")">$(ConvertTo-HtmlText "$($Session.hostConsole)")</a></li>
        <li>Doctor report: $(ConvertTo-HtmlText "$($Session.doctorReportMarkdown)")</li>
        <li>Run card: $(ConvertTo-HtmlText "$($Session.runCardMarkdown)")</li>
      </ul>
    </div>
  </section>

  <h2>Scan On Phone</h2>
  <section class="grid">
    $qrCards
  </section>

  <section class="grid">
    <div class="panel">
      <h2>Current PIN</h2>
      <p style="font-size: 36px; font-weight: 800; letter-spacing: 2px; color: #f4d37b; margin: 0;">$(ConvertTo-HtmlText $pinText)</p>
      <p>$(ConvertTo-HtmlText $pinMeta)</p>
    </div>
    <div class="panel">
      <h2>Recommended Phone URLs</h2>
      <ul>$phoneUrls</ul>
      <p>$(ConvertTo-HtmlText "$($Session.selectionNote)")</p>
    </div>
    <div class="panel">
      <h2>Secondary Phone URLs</h2>
      <ul>$secondaryPhoneUrls</ul>
    </div>
    <div class="panel">
      <h2>LAN URLs</h2>
      <ul>$lanUrls</ul>
    </div>
    <div class="panel">
      <h2>Tailscale URLs</h2>
      <ul>$tailscaleUrls</ul>
    </div>
  </section>

  <h2>Warnings</h2>
  <table><thead><tr><th>Detail</th><th>Next action</th></tr></thead><tbody>$warningRows</tbody></table>
  <h2>Failures</h2>
  <table><thead><tr><th>Detail</th><th>Next action</th></tr></thead><tbody>$failureRows</tbody></table>

  <h2>Next Command</h2>
  <pre>$(ConvertTo-HtmlText "$($Session.nextCommand)")</pre>
  <h2>Stop Command</h2>
  <pre>$(ConvertTo-HtmlText "$($Session.stopCommand)")</pre>
</main>
</body>
</html>
"@

  $html | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-PhoneQrCodes {
  param(
    [object[]]$Urls,
    [string]$SelectedGate,
    [string]$Timestamp
  )

  $qrCodes = @()
  $qrErrors = @()
  if (-not (Test-Path -LiteralPath $QrCliJs)) {
    return [pscustomobject]@{
      qrCodes = @()
      qrErrors = @("qrcode CLI was not found at $QrCliJs.")
    }
  }

  $index = 1
  foreach ($url in @($Urls)) {
    $path = Join-Path $ResolvedOutputDir ("phone-acceptance-qr-{0}-{1}-{2}.svg" -f $SelectedGate, $Timestamp, $index)
    try {
      & $NodePath $QrCliJs --type svg --width 360 --output $path "$url" | Out-Null
      if (-not (Test-Path -LiteralPath $path)) {
        $qrErrors += "Failed to create QR for $url at $path."
      } else {
        $qrCodes += [pscustomobject]@{
          url = "$url"
          path = $path
        }
      }
    } catch {
      $qrErrors += "Failed to create QR for $url`: $($_.Exception.Message)"
    }
    $index += 1
  }

  return [pscustomobject]@{
    qrCodes = @($qrCodes)
    qrErrors = @($qrErrors)
  }
}

if ($SelfTest) {
  $proofUrl = Add-AcceptanceQuery -Url "http://192.168.1.10:4317" -SelectedGate $Gate
  $tempHtml = Join-Path ([System.IO.Path]::GetTempPath()) ("remote-controller-run-card-selftest-{0}.html" -f ([guid]::NewGuid().ToString("N")))
  $htmlRunCardWritten = $false
  $htmlRunCardHasPhoneUrl = $false
  try {
    $sampleSession = [pscustomobject]@{
      ok = $true
      generatedAt = (Get-Date).ToString("o")
      gate = $Gate
      pid = 1234
      doctorStatus = "ready"
      hostConsole = "http://127.0.0.1:4317/host?key=selftest"
      doctorReportMarkdown = "doctor.md"
      runCardMarkdown = "run-card.md"
      phoneUrls = @($proofUrl)
      secondaryPhoneUrls = @("http://10.0.0.2:4317 (secondary)")
      lanUrls = @("http://192.168.1.10:4317")
      tailscaleUrls = @("http://100.64.0.10:4317")
      qrCodes = @()
      qrErrors = @()
      warnings = @()
      failures = @()
      selectionNote = "self-test"
      shortLivedPin = [pscustomobject]@{ available = $true; pin = "123456"; secondsRemaining = 120; refreshedAt = (Get-Date).ToString("o"); error = "" }
      nextCommand = "npm run acceptance:phone -- -Gate $Gate -SkipStart -RequireReady"
      stopCommand = "npm run acceptance:stop -- -Gate $Gate"
    }
    Write-HtmlRunCard -Session $sampleSession -Path $tempHtml
    $htmlRunCardWritten = Test-Path -LiteralPath $tempHtml
    if ($htmlRunCardWritten) {
      $encodedProofUrl = ConvertTo-HtmlText $proofUrl
      $html = Get-Content -LiteralPath $tempHtml -Raw
      $htmlRunCardHasPhoneUrl = $html -match [regex]::Escape($encodedProofUrl)
      $htmlRunCardHasPin = $html -match "123456"
    }
  } finally {
    Remove-Item -LiteralPath $tempHtml -Force -ErrorAction SilentlyContinue
  }
  $ok = $proofUrl -match "acceptance=1" -and
    $proofUrl -match "v=$PhoneAppVersion" -and
    $proofUrl -match "gate=$Gate" -and
    $htmlRunCardWritten -and
    $htmlRunCardHasPhoneUrl -and
    $htmlRunCardHasPin -and
    ((Get-Content -Raw -LiteralPath $PSCommandPath) -match 'REAL_INPUT = "1"') -and
    ((Get-Content -Raw -LiteralPath $PSCommandPath) -match 'QUALITY_DEFAULT = "fast"')
  [pscustomobject]@{
    ok = $ok
    gate = $Gate
    root = "$Root"
    outputDir = "$ResolvedOutputDir"
    doctorExists = Test-Path -LiteralPath $DoctorScript
    qrCliExists = Test-Path -LiteralPath $QrCliJs
    startsScreenCapture = $true
    startsRealInput = $true
    startsFastQuality = $true
    groupsRecommendedPhoneUrls = $true
    phoneAppVersion = $PhoneAppVersion
    gateAwareProofUrl = $proofUrl
    writesHtmlRunCard = $htmlRunCardWritten
    htmlRunCardHasPhoneUrl = $htmlRunCardHasPhoneUrl
    htmlRunCardHasPin = $htmlRunCardHasPin
    nextCommandRequiresReady = $sampleSession.nextCommand -match "-RequireReady"
  } | ConvertTo-Json -Compress
  if (-not $ok) { exit 1 }
  exit 0
}

New-Item -ItemType Directory -Path $ResolvedOutputDir -Force | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$sessionPath = Join-Path $ResolvedOutputDir "phone-acceptance-session-$Gate-$timestamp.json"
$sessionMarkdownPath = Join-Path $ResolvedOutputDir "phone-acceptance-session-$Gate-$timestamp.md"
$sessionHtmlPath = Join-Path $ResolvedOutputDir "phone-acceptance-session-$Gate-$timestamp.html"
$latestPath = Join-Path $ResolvedOutputDir "phone-acceptance-session-$Gate-latest.json"
$latestMarkdownPath = Join-Path $ResolvedOutputDir "phone-acceptance-session-$Gate-latest.md"
$latestHtmlPath = Join-Path $ResolvedOutputDir "phone-acceptance-session-$Gate-latest.html"
$hostStdOutPath = Join-Path $ResolvedOutputDir "phone-acceptance-host-$Gate-$timestamp.out.log"
$hostStdErrPath = Join-Path $ResolvedOutputDir "phone-acceptance-host-$Gate-$timestamp.err.log"

$existingPid = Get-ListeningProcessId
$startedByPrepare = $false
$startedPid = $null

if (-not $existingPid) {
  $process = Start-HostProcess -StdOutPath $hostStdOutPath -StdErrPath $hostStdErrPath
  $startedByPrepare = $true
  $startedPid = $process.Id
} else {
  $startedPid = $existingPid
  $hostStdOutPath = ""
  $hostStdErrPath = ""
}

$doctor = Invoke-Doctor
$state = $null
try {
  $state = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/api/host?key=$([uri]::EscapeDataString($HostKey))" -TimeoutSec 5
} catch {
  $state = $null
}

$phoneSelection = Get-PhoneAddressSelection -State $state -SelectedGate $Gate
$phoneUrls = @($phoneSelection.phoneUrls | ForEach-Object { Add-AcceptanceQuery -Url "$_" -SelectedGate $Gate })
$qrResult = New-PhoneQrCodes -Urls $phoneUrls -SelectedGate $Gate -Timestamp $timestamp
$shortLivedPin = Get-ShortLivedPin

$session = [ordered]@{
  ok = $doctor.ok
  generatedAt = (Get-Date).ToString("o")
  gate = $Gate
  port = $Port
  hostConsole = "http://127.0.0.1:$Port/host?key=$HostKey"
  startedByPrepare = $startedByPrepare
  pid = $startedPid
  doctorStatus = $doctor.status
  doctorReportJson = $doctor.reportJsonPath
  doctorReportMarkdown = $doctor.reportMarkdownPath
  hostStdOutPath = $hostStdOutPath
  hostStdErrPath = $hostStdErrPath
  runCardMarkdown = $sessionMarkdownPath
  runCardHtml = $sessionHtmlPath
  lanUrls = @($doctor.lanUrls)
  tailscaleUrls = @($doctor.tailscaleUrls)
  phoneUrls = @($phoneUrls)
  shortLivedPin = $shortLivedPin
  secondaryPhoneUrls = @($phoneSelection.secondaryPhoneUrls)
  allCandidatePhoneUrls = @($phoneSelection.allCandidatePhoneUrls)
  selectionNote = $phoneSelection.selectionNote
  qrCodes = @($qrResult.qrCodes)
  qrErrors = @($qrResult.qrErrors)
  nextCommand = "npm run acceptance:phone -- -Gate $Gate -SkipStart -RequireReady"
  stopCommand = "npm run acceptance:stop -- -Gate $Gate"
  warnings = @($doctor.checks | Where-Object { $_.status -eq "warn" })
  failures = @($doctor.checks | Where-Object { $_.status -eq "fail" })
}

$session | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $sessionPath -Encoding UTF8
$session | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $latestPath -Encoding UTF8
Write-RunCard -Session ([pscustomobject]$session) -Path $sessionMarkdownPath
Write-RunCard -Session ([pscustomobject]$session) -Path $latestMarkdownPath
Write-HtmlRunCard -Session ([pscustomobject]$session) -Path $sessionHtmlPath
Write-HtmlRunCard -Session ([pscustomobject]$session) -Path $latestHtmlPath

$result = [pscustomobject]$session
$result | Add-Member -NotePropertyName sessionPath -NotePropertyValue $sessionPath
$result | Add-Member -NotePropertyName sessionMarkdownPath -NotePropertyValue $sessionMarkdownPath
$result | Add-Member -NotePropertyName sessionHtmlPath -NotePropertyValue $sessionHtmlPath
$result | Add-Member -NotePropertyName latestPath -NotePropertyValue $latestPath
$result | Add-Member -NotePropertyName latestMarkdownPath -NotePropertyValue $latestMarkdownPath
$result | Add-Member -NotePropertyName latestHtmlPath -NotePropertyValue $latestHtmlPath
$resultJson = $result | ConvertTo-Json -Depth 10 -Compress
[System.Console]::Out.WriteLine($resultJson)

if (-not $doctor.ok) { exit 1 }
