# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configures a member server and joins it to the lab domain.

.DESCRIPTION
    State-machine script - run repeatedly:

      State 1 - Hostname wrong   -> Rename, reboot.
      State 2 - Not domain joined -> Set static IP, disable IPv6, wait for DC, join domain, reboot.
      State 3 - Domain member     -> Post-join config and summary.

.NOTES
    Author  : Tom Stryhn
    Version : 1.0.0
    Target  : Windows Server 2025, clean/sysprepped
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Lab-only credentials - intentional plaintext for automation')]
[CmdletBinding()]
param (
    [string]$ComputerName    = 'SRV01',
    [string]$DomainName      = 'dummy.lab',
    [string]$DomainAdmin     = 'Administrator',
    [string]$DomainPassword  = 'Qwerty*12345',
    [string]$StaticIP        = '10.104.25.20',
    [int]$PrefixLength       = 24,
    [string]$Gateway         = '10.104.25.1',
    [string]$DNSServer       = '10.104.25.5',
    [bool]$DisableIPv6       = $true,
    [int]$DCWaitTimeoutMin   = 10
)

function Write-Phase { param([string]$Message); Write-Host "`n>> $Message" -ForegroundColor Cyan }

function Disable-IPv6OnAllAdapters {
    Write-Phase "Disabling IPv6"
    Get-NetAdapterBinding -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue |
        Where-Object { $_.Enabled } |
        ForEach-Object { Disable-NetAdapterBinding -Name $_.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue }
    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters'
    if (Test-Path $regPath) { Set-ItemProperty -Path $regPath -Name 'DisabledComponents' -Value 0xFF -Type DWord -Force }
    Write-Host "   IPv6 disabled." -ForegroundColor Green
}

function Set-StaticIP {
    param([string]$IP, [int]$Prefix, [string]$GW, [string]$DNS)
    $adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Loopback' } |
               Sort-Object ifIndex | Select-Object -First 1
    if (-not $adapter) { Write-Error "No active adapter."; exit 1 }
    $idx = $adapter.ifIndex
    Set-NetIPInterface -InterfaceIndex $idx -Dhcp Disabled -ErrorAction SilentlyContinue
    Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -ne '127.0.0.1' } | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    Remove-NetRoute -InterfaceIndex $idx -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
    New-NetIPAddress -InterfaceIndex $idx -IPAddress $IP -PrefixLength $Prefix -DefaultGateway $GW -ErrorAction Stop | Out-Null
    Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses @($DNS)
    Write-Host "   Static IP: $IP/$Prefix  GW: $GW  DNS: $DNS" -ForegroundColor Green
}

function Wait-DCReachable {
    param(
        [string]$DCAddress,
        [string]$DomainName,
        [int]$TimeoutMin
    )
    $deadline = (Get-Date).AddMinutes($TimeoutMin)
    Write-Host "   Waiting for DC at $DCAddress..." -ForegroundColor Cyan

    # Phase 1: ICMP reachability
    $pingOk = $false
    while ((Get-Date) -lt $deadline) {
        if (Test-Connection -ComputerName $DCAddress -Count 1 -Quiet -ErrorAction SilentlyContinue) {
            Write-Host "   DC pings." -ForegroundColor DarkGray
            $pingOk = $true
            break
        }
        Start-Sleep -Seconds 10
    }
    if (-not $pingOk) {
        Write-Error "DC at $DCAddress not pingable after $TimeoutMin minutes."
        return $false
    }

    # Phase 2: AD services ready (LDAP + DNS SRV records + DC locator)
    # Ping-alive is not enough - fresh DCs answer ICMP before LDAP/Kerberos
    # is serving. LDAP anonymous bind is not enough either - it succeeds as
    # soon as the LDAP port listens, well before a join-capable state.
    # The canonical "can this client actually perform a domain join right
    # now" test is nltest /dsgetdc. If it returns success, every service
    # Add-Computer needs (Kerberos, NetLogon, SMB to SYSVOL, RPC) is ready.
    Write-Host "   Verifying AD services..." -ForegroundColor Cyan
    while ((Get-Date) -lt $deadline) {
        # Flush the DNS client cache so we don't serve stale negative
        # lookups from early in the DC's boot
        Clear-DnsClientCache -ErrorAction SilentlyContinue

        $ldapOk = $false
        try {
            $null = [System.DirectoryServices.DirectoryEntry]::new("LDAP://$DCAddress").NativeObject
            $ldapOk = $true
        } catch { }

        $srvOk = $false
        try {
            $srv = Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.$DomainName" -Type SRV `
                    -Server $DCAddress -ErrorAction Stop
            if ($srv) { $srvOk = $true }
        } catch { }

        # Authoritative test: ask Windows' DC locator to find a DC for the
        # domain. nltest exit code 0 means DC was found and is join-capable.
        $dcLocatorOk = $false
        try {
            $null = nltest.exe /dsgetdc:$DomainName /force 2>&1
            if ($LASTEXITCODE -eq 0) { $dcLocatorOk = $true }
        } catch { }

        if ($ldapOk -and $srvOk -and $dcLocatorOk) {
            Write-Host "   AD services ready (LDAP + SRV + DC locator)." -ForegroundColor Green
            # Small settle before callers proceed to Add-Computer
            Start-Sleep -Seconds 5
            return $true
        }
        Start-Sleep -Seconds 10
    }
    Write-Error "DC at $DCAddress not serving AD after $TimeoutMin minutes."
    return $false
}

# Relaunch in PS 5.1 if needed
if ($PSVersionTable.PSVersion.Major -ge 7) {
    Write-Warning "Relaunching in Windows PowerShell 5.1..."
    $script = $MyInvocation.MyCommand.Path
    Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$script`" -ComputerName '$ComputerName' -DomainName '$DomainName' -StaticIP '$StaticIP'" `
        -Wait -NoNewWindow
    exit $LASTEXITCODE
}

# State detection
$cs             = Get-CimInstance Win32_ComputerSystem
$isDomainMember = $cs.PartOfDomain -and $cs.Domain -eq $DomainName

Write-Phase "State: Hostname=$env:COMPUTERNAME | DomainMember=$isDomainMember"

#region STATE 1: Rename
if ($env:COMPUTERNAME -ne $ComputerName -and -not $isDomainMember) {
    Write-Phase "STATE 1: Renaming '$env:COMPUTERNAME' -> '$ComputerName'"
    Rename-Computer -NewName $ComputerName -Force
    Write-Host "   Rebooting. Re-run after restart." -ForegroundColor Yellow
    Restart-Computer -Force; exit 0
}

#endregion STATE 1: Rename

#region STATE 2: Network + Domain Join
if (-not $isDomainMember) {
    Write-Phase "STATE 2: Network and domain join"
    if ($DisableIPv6) { Disable-IPv6OnAllAdapters }

    # Wait for network adapter to be ready
    $retries = 0
    while ($retries -lt 10) {
        $adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Loopback' }
        if ($adapter) { break }
        $retries++
        Write-Host "   Waiting for network adapter..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 3
    }

    Set-StaticIP -IP $StaticIP -Prefix $PrefixLength -GW $Gateway -DNS $DNSServer

    # Verify the IP was actually set
    Start-Sleep -Seconds 2
    $currentIP = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                  Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.PrefixOrigin -ne 'WellKnown' }).IPAddress
    if ($currentIP -ne $StaticIP) {
        Write-Warning "Static IP verification failed. Expected $StaticIP, got $currentIP. Retrying..."
        Set-StaticIP -IP $StaticIP -Prefix $PrefixLength -GW $Gateway -DNS $DNSServer
    }

    if (-not (Wait-DCReachable -DCAddress $DNSServer -DomainName $DomainName -TimeoutMin $DCWaitTimeoutMin)) {
        Write-Error "Cannot reach DC. Ensure DC01 is up and the switch is configured."
        exit 1
    }

    Write-Phase "Joining domain '$DomainName'"
    $cred = New-Object PSCredential("$DomainName\$DomainAdmin",
                (ConvertTo-SecureString $DomainPassword -AsPlainText -Force))

    # Retry loop - Add-Computer can fail transiently during the first minute
    # even after initial readiness checks pass (Kerberos key replication, time
    # sync catching up, cached negative DNS lookups).
    $joined   = $false
    $maxTries = 5
    for ($try = 1; $try -le $maxTries; $try++) {
        # Clear any cached negative DNS responses from the previous attempt
        Clear-DnsClientCache -ErrorAction SilentlyContinue

        # Force a fresh DC locator query. If the DC cannot be found right
        # now, there's no point trying Add-Computer yet.
        $null = nltest.exe /dsgetdc:$DomainName /force 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "DC locator lookup failed pre-attempt ${try}/${maxTries} (nltest exit $LASTEXITCODE)"
            if ($try -lt $maxTries) {
                Start-Sleep -Seconds 15
                continue
            }
        }

        try {
            Add-Computer -DomainName $DomainName -Credential $cred -Force -ErrorAction Stop
            $joined = $true
            break
        } catch {
            Write-Warning "Add-Computer attempt ${try}/${maxTries} failed: $($_.Exception.Message)"
            if ($try -lt $maxTries) {
                Write-Host "   Retrying in 15s..." -ForegroundColor DarkYellow
                Start-Sleep -Seconds 15
                # Force time resync between attempts (Kerberos failures)
                w32tm /resync /force 2>&1 | Out-Null
            }
        }
    }

    if (-not $joined) {
        Write-Error "Domain join failed after $maxTries attempts."
        exit 1
    }

    Write-Host "   Domain join successful. Rebooting." -ForegroundColor Green
    Restart-Computer -Force; exit 0
}

#endregion STATE 2: Network + Domain Join

#region STATE 3: Post-join config
if ($isDomainMember) {
    Write-Phase "STATE 3: Post-join config"

    $adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Loopback' } |
               Sort-Object ifIndex | Select-Object -First 1
    if ($adapter) {
        $current = (Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                    Where-Object { $_.IPAddress -ne '127.0.0.1' }).IPAddress
        if ($current -ne $StaticIP) {
            Set-StaticIP -IP $StaticIP -Prefix $PrefixLength -GW $Gateway -DNS $DNSServer
        } else {
            Write-Host "   IP $StaticIP confirmed." -ForegroundColor Green
        }
    }

    if ($DisableIPv6) { Disable-IPv6OnAllAdapters }

    Write-Host ""
    Write-Host "  ===============================================" -ForegroundColor Yellow
    Write-Host "   Member Server Setup Complete" -ForegroundColor Yellow
    Write-Host "  ===============================================" -ForegroundColor Yellow
    Write-Host "   Hostname     : $env:COMPUTERNAME"
    Write-Host "   Domain       : $DomainName"
    Write-Host "   IP Address   : $StaticIP"
    Write-Host "   DNS Server   : $DNSServer"
    Write-Host "  ===============================================" -ForegroundColor Yellow
}
#endregion STATE 3: Post-join config
