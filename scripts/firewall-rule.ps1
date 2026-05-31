param(
  [ValidateSet("status", "install", "remove")]
  [string]$Action = "status",
  [string]$RuleName = "Remote Controller Host 4317",
  [int]$Port = 4317,
  [string[]]$Profiles = @("Private", "Domain"),
  [string[]]$RemoteAddress = @("LocalSubnet", "100.64.0.0/10", "fd7a:115c:a1e0::/48"),
  [switch]$SelfTest
)

$ErrorActionPreference = "Stop"

function Test-IsAdmin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-RuleSnapshot {
  param(
    [string]$SelectedRuleName,
    [int]$SelectedPort
  )

  $rules = @(Get-NetFirewallRule -DisplayName $SelectedRuleName -ErrorAction SilentlyContinue)
  $matching = @()
  foreach ($rule in $rules) {
    $portFilter = $rule | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
    $addressFilter = $rule | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue
    $matchesPort = $portFilter -and $portFilter.Protocol -eq "TCP" -and @($portFilter.LocalPort) -contains "$SelectedPort"
    $matching += [pscustomobject]@{
      name = $rule.Name
      displayName = $rule.DisplayName
      enabled = "$($rule.Enabled)"
      direction = "$($rule.Direction)"
      action = "$($rule.Action)"
      profile = "$($rule.Profile)"
      protocol = if ($portFilter) { "$($portFilter.Protocol)" } else { "" }
      localPort = if ($portFilter) { "$($portFilter.LocalPort)" } else { "" }
      remoteAddress = if ($addressFilter) { "$($addressFilter.RemoteAddress)" } else { "" }
      matchesPort = [bool]$matchesPort
      ready = $rule.Enabled -eq "True" -and $rule.Direction -eq "Inbound" -and $rule.Action -eq "Allow" -and $matchesPort
    }
  }

  return [pscustomobject]@{
    ruleName = $SelectedRuleName
    port = $SelectedPort
    isAdmin = Test-IsAdmin
    ruleCount = $rules.Count
    ready = @($matching | Where-Object { $_.ready }).Count -gt 0
    rules = $matching
  }
}

if ($SelfTest) {
  [pscustomobject]@{
    ok = $true
    action = $Action
    ruleName = $RuleName
    port = $Port
    profiles = $Profiles
    remoteAddress = $RemoteAddress
    installWouldRequireAdmin = $true
  } | ConvertTo-Json -Compress
  exit 0
}

if ($Action -eq "status") {
  Get-RuleSnapshot -SelectedRuleName $RuleName -SelectedPort $Port | ConvertTo-Json -Depth 6 -Compress
  exit 0
}

if ($Action -eq "install") {
  if (-not (Test-IsAdmin)) {
    throw "Installing the firewall rule requires an elevated PowerShell session."
  }
  $existing = @(Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue)
  foreach ($rule in $existing) {
    Remove-NetFirewallRule -Name $rule.Name
  }
  New-NetFirewallRule `
    -DisplayName $RuleName `
    -Direction Inbound `
    -Action Allow `
    -Protocol TCP `
    -LocalPort $Port `
    -Profile $Profiles `
    -RemoteAddress $RemoteAddress `
    -Description "Allows the phone remote controller to reach this laptop host on same Wi-Fi or Tailscale only." | Out-Null
  Get-RuleSnapshot -SelectedRuleName $RuleName -SelectedPort $Port | ConvertTo-Json -Depth 6 -Compress
  exit 0
}

if ($Action -eq "remove") {
  if (-not (Test-IsAdmin)) {
    throw "Removing the firewall rule requires an elevated PowerShell session."
  }
  $existing = @(Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue)
  foreach ($rule in $existing) {
    Remove-NetFirewallRule -Name $rule.Name
  }
  Get-RuleSnapshot -SelectedRuleName $RuleName -SelectedPort $Port | ConvertTo-Json -Depth 6 -Compress
}
