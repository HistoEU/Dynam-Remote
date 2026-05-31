param(
  [ValidateSet("all", "same-wifi", "tailscale")]
  [string]$Gate = "all",
  [string]$HostKey = "dev-host-key",
  [int]$Port = 4317,
  [string]$NodePath = "node",
  [string]$OutputDir = "output\acceptance",
  [switch]$SkipStart,
  [switch]$KeepStarted,
  [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$FirewallRule = Join-Path $PSScriptRoot "firewall-rule.ps1"
$ResolvedOutputDir = Join-Path $Root $OutputDir

function Add-Check {
  param(
    [System.Collections.Generic.List[object]]$Checks,
    [string]$Name,
    [ValidateSet("pass", "warn", "fail")]
    [string]$Status,
    [string]$Detail,
    [string]$NextAction = ""
  )

  $Checks.Add([pscustomobject]@{
    name = $Name
    status = $Status
    detail = $Detail
    nextAction = $NextAction
  }) | Out-Null
}

function Get-TailscaleCliSnapshot {
  $snapshot = [ordered]@{
    available = $false
    command = ""
    ipv4 = @()
    ipv6 = @()
    backendState = ""
    authUrl = ""
    currentTailnet = ""
    health = @()
    error = ""
  }

  $command = Get-Command tailscale -ErrorAction SilentlyContinue | Select-Object -First 1
  $commandPath = if ($command) { "$($command.Source)" } else { "" }
  if (-not $commandPath) {
    foreach ($candidate in @(
      "C:\Program Files\Tailscale\tailscale.exe",
      "C:\Program Files (x86)\Tailscale\tailscale.exe"
    )) {
      if (Test-Path -LiteralPath $candidate) {
        $commandPath = $candidate
        break
      }
    }
  }

  if (-not $commandPath) {
    $snapshot.error = "tailscale CLI was not found on PATH or common Windows install paths."
    return $snapshot
  }

  $snapshot.available = $true
  $snapshot.command = $commandPath

  try {
    $statusOutput = & $commandPath status --json 2>&1
    if ($LASTEXITCODE -eq 0) {
      $parsed = ($statusOutput -join [Environment]::NewLine) | ConvertFrom-Json
      $snapshot.backendState = "$($parsed.BackendState)"
      $snapshot.authUrl = "$($parsed.AuthURL)"
      $snapshot.currentTailnet = "$($parsed.CurrentTailnet)"
      $snapshot.health = @($parsed.Health | ForEach-Object { "$_" })
    } elseif (-not $snapshot.error) {
      $snapshot.error = "tailscale status --json exited with code $LASTEXITCODE`: $($statusOutput -join ' ')"
    }
  } catch {
    if (-not $snapshot.error) { $snapshot.error = $_.Exception.Message }
  }

  foreach ($family in @("-4", "-6")) {
    try {
      $output = & $commandPath ip $family 2>&1
      if ($LASTEXITCODE -eq 0) {
        $lines = @($output | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
        if ($family -eq "-4") {
          $snapshot.ipv4 = $lines
        } else {
          $snapshot.ipv6 = $lines
        }
      } else {
        $snapshot.error = "tailscale ip $family exited with code $LASTEXITCODE`: $($output -join ' ')"
      }
    } catch {
      $snapshot.error = $_.Exception.Message
    }
  }

  return $snapshot
}

function Get-FirewallReadiness {
  try {
    $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $FirewallRule -Action status -Port $Port
    $jsonLine = @($raw | Where-Object { "$_".Trim().StartsWith("{") }) | Select-Object -Last 1
    if ($jsonLine) { return $jsonLine | ConvertFrom-Json }
  } catch {
    return [pscustomobject]@{
      ready = $false
      error = $_.Exception.Message
    }
  }
  return [pscustomobject]@{
    ready = $false
    error = "Firewall status did not return JSON."
  }
}

function Test-HealthUrl {
  param([string]$Url)

  $healthUrl = "$Url/api/health"
  try {
    $response = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 4
    return [pscustomobject]@{
      url = $Url
      healthUrl = $healthUrl
      ok = $response.StatusCode -eq 200
      statusCode = $response.StatusCode
      error = ""
    }
  } catch {
    $statusCode = 0
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
      $statusCode = [int]$_.Exception.Response.StatusCode
    }
    return [pscustomobject]@{
      url = $Url
      healthUrl = $healthUrl
      ok = $false
      statusCode = $statusCode
      error = $_.Exception.Message
    }
  }
}

function Get-GateUrls {
  param(
    [object]$State,
    [string]$Kind
  )

  if (-not $State -or -not $State.addresses) { return @() }
  return @($State.addresses | Where-Object { $_.kind -eq $Kind } | ForEach-Object { $_.url })
}

function New-SelfTestResult {
  $checks = [System.Collections.Generic.List[object]]::new()
  Add-Check $checks "sample host state" "pass" "Sample host state can be evaluated."
  Add-Check $checks "sample tailscale missing" "warn" "Missing Tailscale is a readiness warning for same-Wi-Fi and a blocker for the tailscale gate." "Install/start Tailscale before running the tailscale gate."
  $failed = @($checks | Where-Object { $_.status -eq "fail" })
  return [pscustomobject]@{
    ok = $failed.Count -eq 0
    gate = "selftest"
    checks = $checks.Count
    failed = $failed.Count
  }
}

function ConvertTo-MarkdownList {
  param([object[]]$Items)
  if (-not $Items -or $Items.Count -eq 0) { return "- none" }
  return ($Items | ForEach-Object { "- $_" }) -join [Environment]::NewLine
}

function Escape-MarkdownCell {
  param([string]$Text)
  return "$Text".Replace("|", "\|").Replace("`r", " ").Replace("`n", " ")
}

function Write-DoctorReport {
  param([object]$DoctorResult)

  New-Item -ItemType Directory -Path $ResolvedOutputDir -Force | Out-Null
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $prefix = "acceptance-doctor-$($DoctorResult.gate)-$timestamp"
  $jsonPath = Join-Path $ResolvedOutputDir "$prefix.json"
  $mdPath = Join-Path $ResolvedOutputDir "$prefix.md"

  $DoctorResult | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

  $checkRows = @($DoctorResult.checks | ForEach-Object {
    "| $(Escape-MarkdownCell $_.status) | $(Escape-MarkdownCell $_.name) | $(Escape-MarkdownCell $_.detail) | $(Escape-MarkdownCell $_.nextAction) |"
  })
  if ($checkRows.Count -eq 0) {
    $checkRows = @("| none | none | none | none |")
  }

  $firewallJson = if ($DoctorResult.firewall) { $DoctorResult.firewall | ConvertTo-Json -Depth 6 } else { "not available" }
  $tailscaleJson = if ($DoctorResult.tailscaleCli) { $DoctorResult.tailscaleCli | ConvertTo-Json -Depth 6 } else { "not available" }
  $healthJson = if ($DoctorResult.health) { $DoctorResult.health | ConvertTo-Json -Depth 8 } else { "not available" }
  $nextCommands = ConvertTo-MarkdownList @($DoctorResult.nextCommands)

  $markdown = @"
# Physical Acceptance Readiness Doctor

Generated: $((Get-Date).ToString("o"))
Gate: $($DoctorResult.gate)
Status: $($DoctorResult.status)
Ready: $($DoctorResult.ok)
Start mode: $($DoctorResult.startMode)
Host console: $($DoctorResult.hostConsole)

## Phone URLs

LAN URLs:

$(ConvertTo-MarkdownList @($DoctorResult.lanUrls))

Tailscale URLs:

$(ConvertTo-MarkdownList @($DoctorResult.tailscaleUrls))

## Checks

| Status | Check | Detail | Next action |
| --- | --- | --- | --- |
$($checkRows -join [Environment]::NewLine)

## Firewall

~~~json
$firewallJson
~~~

## Tailscale CLI

~~~json
$tailscaleJson
~~~

## Host Health

~~~json
$healthJson
~~~

## Next Commands

$nextCommands

## Result Rules

- Same-Wi-Fi can start when this doctor has no failed checks for `same-wifi`.
- Tailscale cannot start until this doctor has no failed checks for `tailscale`.
- This report is readiness evidence only; it is not a substitute for the physical phone acceptance run or `acceptance.phoneMark`.
"@

  $markdown | Set-Content -LiteralPath $mdPath -Encoding UTF8

  return [pscustomobject]@{
    jsonPath = $jsonPath
    markdownPath = $mdPath
  }
}

function Invoke-Doctor {
  $checks = [System.Collections.Generic.List[object]]::new()
  $baseUrl = "http://127.0.0.1:$Port"
  $started = $null
  $state = $null
  $health = $null
  $hostReachable = $false
  $startMode = "existing-or-skipped"

  try {
    $existing = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -First 1
    if (-not $existing -and -not $SkipStart) {
      $env:HOST_KEY = $HostKey
      $env:CAPTURE_MODE = "screen"
      $env:HOST = "::"
      $started = Start-Process -FilePath $NodePath -ArgumentList "src\server.js" -WorkingDirectory $Root -WindowStyle Hidden -PassThru
      $startMode = "started-by-doctor"
      Start-Sleep -Seconds 2
    } elseif ($existing) {
      $startMode = "existing-process"
    } else {
      $startMode = "not-started-skipstart"
    }

    try {
      $health = Invoke-RestMethod -Uri "$baseUrl/api/health" -TimeoutSec 5
      if ($health.ok) {
        Add-Check $checks "host health" "pass" "Host health responded at $baseUrl/api/health."
        $hostReachable = $true
      } else {
        Add-Check $checks "host health" "fail" "Host health response did not report ok=true." "Start the host with CAPTURE_MODE=screen."
      }
    } catch {
      Add-Check $checks "host health" "fail" $_.Exception.Message "Start the host or remove -SkipStart."
    }

    if ($hostReachable) {
      try {
        $state = Invoke-RestMethod -Uri "$baseUrl/api/host?key=$([uri]::EscapeDataString($HostKey))" -TimeoutSec 5
        Add-Check $checks "host console API" "pass" "Authenticated host state loaded."
      } catch {
        Add-Check $checks "host console API" "fail" $_.Exception.Message "Check HOST_KEY and restart the host."
      }
    }

    $lanUrls = Get-GateUrls -State $state -Kind "lan"
    $tailscaleUrls = Get-GateUrls -State $state -Kind "tailscale"
    $targetLan = ($Gate -eq "all" -or $Gate -eq "same-wifi")
    $targetTailscale = ($Gate -eq "all" -or $Gate -eq "tailscale")
    $tailscaleCli = Get-TailscaleCliSnapshot

    if ($targetLan) {
      if ($lanUrls.Count -gt 0) {
        Add-Check $checks "same-wifi LAN URL" "pass" "LAN URL advertised: $($lanUrls -join ', ')."
      } else {
        Add-Check $checks "same-wifi LAN URL" "fail" "No LAN URL is advertised." "Connect the laptop to Wi-Fi/Ethernet and restart the host."
      }
      foreach ($url in $lanUrls) {
        $probe = Test-HealthUrl -Url $url
        if ($probe.ok) {
          Add-Check $checks "same-wifi laptop preflight $url" "pass" "Laptop can reach $($probe.healthUrl)."
        } else {
          Add-Check $checks "same-wifi laptop preflight $url" "warn" $probe.error "If the phone cannot connect, check Windows Firewall and the LAN address."
        }
      }
    }

    if ($targetTailscale) {
      if ($tailscaleUrls.Count -gt 0) {
        Add-Check $checks "tailscale URL" "pass" "Tailscale URL advertised: $($tailscaleUrls -join ', ')."
      } else {
        $urlAction = if ($tailscaleCli.available -and $tailscaleCli.authUrl) {
          "Open $($tailscaleCli.authUrl), sign in, then run npm run acceptance:ready -- -Gate tailscale."
        } elseif ($tailscaleCli.available) {
          "Sign into Tailscale on the laptop, then restart or prepare the host again."
        } else {
          "Install/start Tailscale on the laptop, sign in, and restart the host."
        }
        Add-Check $checks "tailscale URL" "fail" "No Tailscale IPv4 100.64.0.0/10 or IPv6 fd7a:115c:a1e0::/48 URL is advertised." $urlAction
      }
      foreach ($url in $tailscaleUrls) {
        $probe = Test-HealthUrl -Url $url
        if ($probe.ok) {
          Add-Check $checks "tailscale laptop preflight $url" "pass" "Laptop can reach $($probe.healthUrl)."
        } else {
          Add-Check $checks "tailscale laptop preflight $url" "warn" $probe.error "If the phone cannot connect, check Tailscale and Windows Firewall."
        }
      }
    }

    $firewall = Get-FirewallReadiness
    if ($firewall.ready) {
      Add-Check $checks "windows firewall rule" "pass" "Inbound TCP $Port rule is ready."
    } else {
      Add-Check $checks "windows firewall rule" "warn" "Inbound TCP $Port rule is not installed or not ready." "If the phone cannot connect, run npm run firewall:handoff first, then run the copied elevated install command only if you choose to allow inbound TCP $Port."
    }

    if ($targetTailscale) {
      if ($tailscaleCli.available -and (($tailscaleCli.ipv4.Count + $tailscaleCli.ipv6.Count) -gt 0)) {
        Add-Check $checks "tailscale CLI" "pass" "tailscale ip returned $($tailscaleCli.ipv4.Count) IPv4 and $($tailscaleCli.ipv6.Count) IPv6 address(es)."
      } elseif ($tailscaleCli.available) {
        $loginAction = if ($tailscaleCli.authUrl) { "Open $($tailscaleCli.authUrl), sign in, then run npm run acceptance:ready -- -Gate tailscale." } else { "Run tailscale status and sign in." }
        Add-Check $checks "tailscale CLI" "fail" "tailscale CLI is available but returned no IP addresses. Backend state: $($tailscaleCli.backendState)." $loginAction
      } else {
        Add-Check $checks "tailscale CLI" "fail" $tailscaleCli.error "Install Tailscale or add it to PATH before the tailscale gate."
      }
    } elseif ($tailscaleCli.available) {
      Add-Check $checks "tailscale CLI" "pass" "tailscale CLI is available."
    } else {
      Add-Check $checks "tailscale CLI" "warn" $tailscaleCli.error "Needed only for the Tailscale/different-Wi-Fi gate."
    }

    $failures = @($checks | Where-Object { $_.status -eq "fail" })
    $warnings = @($checks | Where-Object { $_.status -eq "warn" })
    $nextCommands = @()
    if ($targetLan) { $nextCommands += "npm run acceptance:phone -- -Gate same-wifi -SkipStart -RequireReady" }
    if ($targetTailscale) { $nextCommands += "npm run acceptance:phone -- -Gate tailscale -SkipStart -RequireReady" }

    $status = "not-ready"
    if ($failures.Count -eq 0) { $status = "ready-with-possible-warnings" }

    return [pscustomobject]@{
      ok = $failures.Count -eq 0
      status = $status
      gate = $Gate
      startMode = $startMode
      hostConsole = "$baseUrl/host?key=$HostKey"
      health = $health
      lanUrls = @($lanUrls)
      tailscaleUrls = @($tailscaleUrls)
      firewall = $firewall
      tailscaleCli = $tailscaleCli
      checks = $checks
      failureCount = $failures.Count
      warningCount = $warnings.Count
      nextCommands = @($nextCommands)
    }
  } finally {
    if ($started -and -not $KeepStarted -and -not $started.HasExited) {
      Stop-Process -Id $started.Id -Force
    }
  }
}

if ($SelfTest) {
  $result = New-SelfTestResult
  $result | Add-Member -NotePropertyName commonInstallPathChecked -NotePropertyValue "C:\Program Files\Tailscale\tailscale.exe" -Force
  $result | Add-Member -NotePropertyName exposesTailscaleAuthUrl -NotePropertyValue $true -Force
  $result | ConvertTo-Json -Compress
  if (-not $result.ok) { exit 1 }
  exit 0
}

$doctor = Invoke-Doctor
$reportPaths = Write-DoctorReport -DoctorResult $doctor
$doctor | Add-Member -NotePropertyName reportJsonPath -NotePropertyValue $reportPaths.jsonPath
$doctor | Add-Member -NotePropertyName reportMarkdownPath -NotePropertyValue $reportPaths.markdownPath
$doctor | ConvertTo-Json -Depth 8 -Compress
if (-not $doctor.ok) { exit 1 }
