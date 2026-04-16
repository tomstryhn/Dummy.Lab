# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs and configures a Domain Controller for a lab domain.

.DESCRIPTION
    State-machine script - run repeatedly, it detects where it is and does the next step:

      State 1 - Not a DC  -> Set IP, disable IPv6, install AD DS, set NLA deps, promote (reboot).
      State 2 - Is a DC   -> Post-promotion config (DNS forwarder, AD Recycle Bin, verify).

    Hostname is set by unattend.xml before first boot.
    Promotion reboot applies NLA service dependencies set in State 1.

.NOTES
    Author  : Tom Stryhn
    Version : 1.0.0
    Target  : Windows Server 2019/2022/2025 (sysprepped, hostname set by unattend)
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Lab-only credentials - intentional plaintext for automation')]
[CmdletBinding()]
param (
    [string]$DomainName        = 'dummy.lab',
    [string]$DomainNetbiosName = 'Dummy',
    [string]$SafeModePassword  = 'Qwerty*12345',
    [string]$AdminPassword     = '',
    [string]$DNSForwarder      = '8.8.8.8',
    [string]$StaticIP          = '10.104.25.5',
    [int]$PrefixLength         = 24,
    [string]$Gateway           = '10.104.25.1',
    [string]$ComputerName      = 'DC01',
    [bool]$DisableIPv6         = $true,
    [bool]$FixNLA              = $false,
    [bool]$AdditionalDC        = $false,
    [string]$PrimaryDCIP       = ''
)

function Write-Phase { param([string]$Message); Write-Host "`n>> $Message" -ForegroundColor Cyan }

function Disable-IPv6OnAllAdapters {
    Get-NetAdapterBinding -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue |
        Where-Object { $_.Enabled } |
        ForEach-Object {
            Disable-NetAdapterBinding -Name $_.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
        }
    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters'
    if (Test-Path $regPath) {
        Set-ItemProperty -Path $regPath -Name 'DisabledComponents' -Value 0xFF -Type DWord -Force
    }
}

function Set-StaticIP {
    param([string]$IP, [int]$Prefix, [string]$GW, [string]$DNS1, [string]$DNS2 = '')
    $adapter = Get-NetAdapter | Where-Object {
        $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Loopback'
    } | Sort-Object ifIndex | Select-Object -First 1

    if (-not $adapter) { Write-Error "No active adapter found."; exit 1 }

    $idx = $adapter.ifIndex
    Set-NetIPInterface -InterfaceIndex $idx -Dhcp Disabled -ErrorAction SilentlyContinue
    Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -ne '127.0.0.1' } | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    Remove-NetRoute -InterfaceIndex $idx -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue

    if ($GW) {
        New-NetIPAddress -InterfaceIndex $idx -IPAddress $IP -PrefixLength $Prefix -DefaultGateway $GW -ErrorAction Stop | Out-Null
    } else {
        New-NetIPAddress -InterfaceIndex $idx -IPAddress $IP -PrefixLength $Prefix -ErrorAction Stop | Out-Null
    }
    $primary = if ($DNS1) { $DNS1 } else { '127.0.0.1' }
    $dns = @($primary); if ($DNS2 -and $DNS2 -ne $primary) { $dns += $DNS2 }
    Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses $dns
}

# Relaunch in Windows PowerShell 5.1 if running in PS7+
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $script = $MyInvocation.MyCommand.Path
    Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$script`" -DomainName '$DomainName' -DomainNetbiosName '$DomainNetbiosName' -StaticIP '$StaticIP' -Gateway '$Gateway' -ComputerName '$ComputerName' -AdditionalDC `$$AdditionalDC -PrimaryDCIP '$PrimaryDCIP' -AdminPassword '$AdminPassword'" `
        -Wait -NoNewWindow
    exit $LASTEXITCODE
}

# State detection
$isDC          = (Get-CimInstance Win32_ComputerSystem).DomainRole -ge 4
$addsFeature   = Get-WindowsFeature -Name AD-Domain-Services -ErrorAction SilentlyContinue
$addsInstalled = ($null -ne $addsFeature) -and ($addsFeature.InstallState -eq 'Installed')

#region State 1: Install + Promote (single pass)
if (-not $isDC) {
    Write-Phase "STATE 1: Configuring DC for '$DomainName'"

    # Network - additional DCs point DNS at the primary DC so the domain is
    # reachable during promotion. First DCs point at themselves (127.0.0.1).
    if ($DisableIPv6) { Disable-IPv6OnAllAdapters }
    $dns1 = if ($AdditionalDC -and $PrimaryDCIP) { $PrimaryDCIP } else { '127.0.0.1' }
    Set-StaticIP -IP $StaticIP -Prefix $PrefixLength -GW $Gateway -DNS1 $dns1

    # Install AD DS role if not already present
    if (-not $addsInstalled) {
        Write-Phase "Installing AD DS role..."
        $result = Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools -ErrorAction Stop
        if (-not $result.Success) { Write-Error "Feature install failed: $($result.ExitCode)"; exit 1 }

        # If role install demands a reboot (rare on modern Server), do it and come back
        if ($result.RestartNeeded -eq 'Yes') {
            Write-Phase "Role install requires reboot - restarting..."
            Restart-Computer -Force; exit 0
        }
    }

    # NLA fix - optional, off by default so the lab matches a real deployment
    # Adds DNS and NTDS as dependencies so NLA waits for AD services before
    # determining network profile. Prevents "Unidentified Network" / Public firewall.
    if ($FixNLA) {
        Write-Phase "Setting NLA service dependencies (FixNLA enabled)..."
        & sc.exe config nlasvc depend= NSI/RpcSs/TcpIp/Dhcp/Eventlog/DNS/NTDS 2>&1 | Out-Null
    }

    # Promote to DC - this triggers an automatic reboot
    Write-Phase "Promoting to Domain Controller..."
    try { Import-Module ADDSDeployment -ErrorAction Stop }
    catch { Write-Error "ADDSDeployment module unavailable: $_"; exit 1 }

    $secPwd = ConvertTo-SecureString $SafeModePassword -AsPlainText -Force

    if ($AdditionalDC) {
        Write-Phase "Joining existing domain '$DomainName' as additional DC..."
        $joinPwd = if ($AdminPassword) { $AdminPassword } else { $SafeModePassword }
        $domCred = New-Object PSCredential("$DomainNetbiosName\Administrator",
                       (ConvertTo-SecureString $joinPwd -AsPlainText -Force))
        Install-ADDSDomainController `
            -DomainName $DomainName `
            -Credential $domCred `
            -SafeModeAdministratorPassword $secPwd `
            -InstallDns:$true `
            -CreateDnsDelegation:$false `
            -DatabasePath 'C:\Windows\NTDS' `
            -LogPath 'C:\Windows\NTDS' `
            -SysvolPath 'C:\Windows\SYSVOL' `
            -NoRebootOnCompletion:$false `
            -Force
    } else {
        Write-Phase "Creating new forest '$DomainName'..."
        Install-ADDSForest `
            -DomainName $DomainName `
            -DomainNetbiosName $DomainNetbiosName `
            -SafeModeAdministratorPassword $secPwd `
            -ForestMode 'WinThreshold' `
            -DomainMode 'WinThreshold' `
            -InstallDns:$true `
            -CreateDnsDelegation:$false `
            -DatabasePath 'C:\Windows\NTDS' `
            -LogPath 'C:\Windows\NTDS' `
            -SysvolPath 'C:\Windows\SYSVOL' `
            -NoRebootOnCompletion:$false `
            -Force
    }

    # Unreachable - promotion triggers immediate reboot
    exit 0
}
#endregion State 1

#region State 2: Post-Promotion Config (no reboot needed)
if ($isDC) {
    Write-Phase "STATE 2: Post-promotion config for '$DomainName'"
    Import-Module ActiveDirectory -ErrorAction Stop

    # Verify static IP
    $adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Loopback' } |
               Sort-Object ifIndex | Select-Object -First 1
    if ($adapter) {
        $current = (Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                    Where-Object { $_.IPAddress -ne '127.0.0.1' }).IPAddress
        # After promotion this machine is a DNS server and must resolve its own
        # zone first (127.0.0.1). Additional DCs use the primary DC as secondary
        # for redundancy; first DCs use the external forwarder as secondary.
        $dns2 = if ($AdditionalDC -and $PrimaryDCIP) { $PrimaryDCIP } else { $DNSForwarder }
        if ($current -ne $StaticIP -or ($AdditionalDC -and $PrimaryDCIP)) {
            Set-StaticIP -IP $StaticIP -Prefix $PrefixLength -GW $Gateway -DNS1 '127.0.0.1' -DNS2 $dns2
        }
    }

    if ($DisableIPv6) { Disable-IPv6OnAllAdapters }

    # DNS Forwarder (skipped when empty - no internet labs have no upstream DNS)
    if ($DNSForwarder) {
        Write-Phase "Setting DNS forwarder: $DNSForwarder"
        try {
            $existing = Get-DnsServerForwarder -ErrorAction SilentlyContinue
            if ($existing.IPAddress -notcontains $DNSForwarder) {
                Add-DnsServerForwarder -IPAddress $DNSForwarder -PassThru | Out-Null
            }
        } catch { Write-Warning "Could not set DNS forwarder: $_" }
    } else {
        Write-Phase "DNS forwarder: skipped (no-internet lab)"
    }
}
#endregion State 2
