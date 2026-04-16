# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs and configures the DHCP Server role on a lab DC.

.DESCRIPTION
    Idempotent - safe to re-run. Creates a DHCP scope for the lab subnet,
    sets standard options (DNS, gateway, domain name), and authorizes DHCP in AD.
    IPv6 DHCP is not configured (disabled lab-wide by default).

.NOTES
    Author  : Tom Stryhn
    Version : 1.0.0
    Target  : Windows Server 2025, after DC promotion
#>

[CmdletBinding()]
param (
    [string]$ScopeID        = '10.104.25.0',
    [string]$ScopeStart     = '10.104.25.64',
    [string]$ScopeEnd       = '10.104.25.253',
    [string]$SubnetMask     = '255.255.255.0',
    [string]$Gateway        = '10.104.25.1',
    [string]$DNSServer      = '10.104.25.5',
    [string]$DomainName     = 'dummy.lab',
    [string]$ScopeName      = 'DummyLab-Clients',
    [int]$LeaseDurationH    = 8,
    [string]$ExcludeStart   = '',
    [string]$ExcludeEnd     = ''
)

function Write-Phase { param([string]$Message); Write-Host "`n>> $Message" -ForegroundColor Cyan }

#region Install DHCP role
Write-Phase "Checking DHCP Server role"
$feature = Get-WindowsFeature -Name DHCP -ErrorAction SilentlyContinue

if ($feature.InstallState -ne 'Installed') {
    Write-Host "   Installing DHCP Server role..." -ForegroundColor Cyan
    $result = Install-WindowsFeature -Name DHCP -IncludeManagementTools -ErrorAction Stop
    if (-not $result.Success) { Write-Error "DHCP role install failed: $($result.ExitCode)"; exit 1 }
    Write-Host "   DHCP role installed." -ForegroundColor Green
} else {
    Write-Host "   DHCP role already installed." -ForegroundColor DarkGray
}

#endregion Install DHCP role

#region Authorize in AD
Write-Phase "Authorizing DHCP server in Active Directory"
try {
    $authorized = Get-DhcpServerInDC -ErrorAction SilentlyContinue |
                  Where-Object { $_.DnsName -eq "$env:COMPUTERNAME.$DomainName" }
    if (-not $authorized) {
        Add-DhcpServerInDC -DnsName "$env:COMPUTERNAME.$DomainName" -ErrorAction Stop
        Write-Host "   DHCP authorized in AD." -ForegroundColor Green
    } else {
        Write-Host "   Already authorized." -ForegroundColor DarkGray
    }
} catch { Write-Warning "Could not authorize DHCP in AD: $_" }

# Suppress post-install notification
try {
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12' `
                     -Name 'ConfigurationState' -Value 2 -ErrorAction SilentlyContinue
} catch {}

#endregion Authorize in AD

#region Create scope
Write-Phase "Configuring DHCP scope: $ScopeID ($ScopeStart - $ScopeEnd)"
$existingScope = Get-DhcpServerv4Scope -ScopeId $ScopeID -ErrorAction SilentlyContinue

if ($existingScope) {
    Write-Host "   Scope $ScopeID already exists." -ForegroundColor DarkGray
} else {
    Add-DhcpServerv4Scope -Name $ScopeName `
                           -StartRange $ScopeStart `
                           -EndRange $ScopeEnd `
                           -SubnetMask $SubnetMask `
                           -LeaseDuration ([TimeSpan]::FromHours($LeaseDurationH)) `
                           -State Active `
                           -ErrorAction Stop
    Write-Host "   Scope created." -ForegroundColor Green
}

#endregion Create scope

#region Exclusion range (only if within scope bounds)
Write-Phase "Checking exclusion range: $ExcludeStart - $ExcludeEnd"
if (-not $ExcludeStart -or -not $ExcludeEnd) {
    Write-Host "   No exclusion range configured - skipped." -ForegroundColor DarkGray
} else {
# Exclusion range must fall within scope bounds (ScopeStart - ScopeEnd).
# If the exclusion range is outside the scope (e.g. .1-.63 vs scope .64-.253),
# skip it - the addresses are already outside the scope and need no exclusion.
$exStartLast = [int]($ExcludeStart -split '\.')[-1]
$exEndLast   = [int]($ExcludeEnd   -split '\.')[-1]
$scStartLast = [int]($ScopeStart   -split '\.')[-1]
$scEndLast   = [int]($ScopeEnd     -split '\.')[-1]

if ($exEndLast -lt $scStartLast -or $exStartLast -gt $scEndLast) {
    Write-Host "   Exclusion range $ExcludeStart-$ExcludeEnd is outside scope $ScopeStart-$ScopeEnd - skipped (not needed)." -ForegroundColor DarkGray
} else {
    # Clamp exclusion to scope bounds
    $clampedStart = if ($exStartLast -lt $scStartLast) { $ScopeStart } else { $ExcludeStart }
    $clampedEnd   = if ($exEndLast   -gt $scEndLast)   { $ScopeEnd   } else { $ExcludeEnd   }
    try {
        $existing = Get-DhcpServerv4ExclusionRange -ScopeId $ScopeID -ErrorAction SilentlyContinue |
                    Where-Object { $_.StartRange -eq $clampedStart -and $_.EndRange -eq $clampedEnd }
        if (-not $existing) {
            Add-DhcpServerv4ExclusionRange -ScopeId $ScopeID -StartRange $clampedStart -EndRange $clampedEnd
            Write-Host "   Exclusion set: $clampedStart - $clampedEnd" -ForegroundColor Green
        } else {
            Write-Host "   Exclusion already set." -ForegroundColor DarkGray
        }
    } catch { Write-Warning "Could not set exclusion range: $_" }
}
} # end else (ExcludeStart/ExcludeEnd provided)

#endregion Exclusion range (only if within scope bounds)

#region Scope options: Router (3), DNS Server (6), Domain Name (15)
Write-Phase "Setting DHCP scope options"
# Option 3 (Router/Gateway) is only set when a gateway is configured.
# No-internet labs omit it so clients have no default route.
$optionMap = @{
    6  = @{ Name = 'DNS Server';  Value = $DNSServer  }
    15 = @{ Name = 'Domain Name'; Value = $DomainName }
}
if ($Gateway) {
    $optionMap[3] = @{ Name = 'Router (Default Gateway)'; Value = $Gateway }
} else {
    Write-Host "   Option 3 (Router): skipped (no-internet lab)" -ForegroundColor DarkGray
}

foreach ($optionId in $optionMap.Keys) {
    try {
        Set-DhcpServerv4OptionValue -ScopeId $ScopeID -OptionId $optionId `
            -Value $optionMap[$optionId].Value -Force -ErrorAction Stop
        Write-Host "   Option $optionId ($($optionMap[$optionId].Name)): $($optionMap[$optionId].Value)" -ForegroundColor Green
    } catch { Write-Warning "Option $optionId failed: $_" }
}

#endregion Scope options: Router (3), DNS Server (6), Domain Name (15)

#region Restart service
Write-Phase "Restarting DHCP Server service"
try {
    Restart-Service -Name 'DHCPServer' -ErrorAction Stop
    Write-Host "   DHCP Server restarted." -ForegroundColor Green
} catch {
    Write-Warning "Could not restart DHCP Server: $_"
}

Write-Host ""
Write-Host "  ===============================================" -ForegroundColor Yellow
Write-Host "   DHCP Setup Complete" -ForegroundColor Yellow
Write-Host "  ===============================================" -ForegroundColor Yellow
Write-Host "   Scope ID        : $ScopeID"
Write-Host "   Scope Range     : $ScopeStart - $ScopeEnd"
Write-Host "   Gateway         : $Gateway"
Write-Host "   DNS Server      : $DNSServer"
Write-Host "   Domain Name     : $DomainName"
Write-Host "  ===============================================" -ForegroundColor Yellow
#endregion Restart service
