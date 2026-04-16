# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Deploy-LabDC {
    <#
    .SYNOPSIS
        Deploys and promotes a Domain Controller VM.
        Handles AD DS install, promotion, DNS, DHCP, and post-config.
    .PARAMETER VMName
        Full VM name (e.g. ProdTest-DC01).
    .PARAMETER ShortName
        Short computer name (e.g. DC01).
    .PARAMETER VHDXPath
        Path to the differencing disk VHDX.
    .PARAMETER DCIP
        Static IP for the DC.
    .PARAMETER NetConfig
        Network config object from Get-LabNetworkConfig.
    .PARAMETER OSEntry
        OS catalog entry hashtable (DefaultMemoryGB, DefaultCPU, etc.).
    .PARAMETER SwitchName
        Hyper-V virtual switch name.
    .PARAMETER VMPath
        Path for VM configuration files.
    .PARAMETER AdminPassword
        Plaintext admin password for the lab.
    .PARAMETER DomainName
        FQDN for the domain (e.g. mylab.lab).
    .PARAMETER DomainNetbios
        NetBIOS domain name (e.g. MYLAB).
    .PARAMETER SafeModePassword
        DSRM (Directory Services Restore Mode) password.
    .PARAMETER GuestScriptPath
        Path to the GuestScripts folder.
    .PARAMETER LabName
        Lab name (used for DHCP scope naming).
    .PARAMETER Defaults
        Lab config defaults hashtable.
    .PARAMETER MemoryGB
        Override memory in GB (0 = use OS default).
    .PARAMETER CPU
        Override vCPU count (0 = use OS default).
    .PARAMETER FixNLA
        Whether to apply the NLA dependency fix.
    #>
    param(
        [Parameter(Mandatory)][string]$VMName,
        [Parameter(Mandatory)][string]$ShortName,
        [Parameter(Mandatory)][string]$VHDXPath,
        [Parameter(Mandatory)][string]$DCIP,
        [Parameter(Mandatory)][PSCustomObject]$NetConfig,
        [Parameter(Mandatory)][hashtable]$OSEntry,
        [Parameter(Mandatory)][string]$SwitchName,
        [Parameter(Mandatory)][string]$VMPath,
        [Parameter(Mandatory)][string]$AdminPassword,
        [Parameter(Mandatory)][string]$DomainName,
        [Parameter(Mandatory)][string]$DomainNetbios,
        [Parameter(Mandatory)][string]$SafeModePassword,
        [Parameter(Mandatory)][string]$GuestScriptPath,
        [Parameter(Mandatory)][string]$LabName,
        [Parameter(Mandatory)][hashtable]$Defaults,
        [int]$MemoryGB = 0,
        [int]$CPU = 0,
        [switch]$FixNLA,
        [switch]$NoInternet,
        [switch]$AdditionalDC,
        [string]$PrimaryDCIP = ''
    )

    $memVal = if ($MemoryGB -gt 0) { $MemoryGB } else { $OSEntry.DefaultMemoryGB }
    $cpuVal = if ($CPU -gt 0) { $CPU } else { $OSEntry.DefaultCPU }

    $null = New-LabVM -VMName $VMName -VHDXPath $VHDXPath -SwitchName $SwitchName `
              -VMPath $VMPath -MemoryGB $memVal -ProcessorCount $cpuVal -IsLabDC

    $null = Start-LabVM -VMName $VMName
    $cred = New-Object PSCredential('Administrator',
                (ConvertTo-SecureString $AdminPassword -AsPlainText -Force))
    $domCred = New-Object PSCredential("$DomainNetbios\Administrator",
                   (ConvertTo-SecureString $AdminPassword -AsPlainText -Force))

    Write-LabLog "Waiting for VM to boot..." -Level Info
    $ready = Wait-LabVMReady -VMName $VMName -Credential $cred
    if (-not $ready) { Write-LabLog "$VMName did not become ready." -Level Error; return }

    Send-GuestScript -VMName $VMName -Credential $cred -LocalPath (Join-Path $GuestScriptPath 'Install-DC.ps1')

    # DC state machine (2 states):
    #   Round 1: Install role + set NLA deps + promote -> reboot (forced by AD promotion)
    #   Round 2: Post-config (DNS forwarder, Recycle Bin) -> no reboot
    # Hostname is set by unattend.xml, NLA fix applied before promotion reboot
    $dcArgs = @{
        DomainName        = $DomainName
        DomainNetbiosName = $DomainNetbios
        SafeModePassword  = $SafeModePassword
        StaticIP          = $DCIP
        PrefixLength      = $NetConfig.PrefixLength
        Gateway           = if ($NoInternet) { '' } else { $NetConfig.Gateway }
        ComputerName      = $ShortName
        DisableIPv6       = $Defaults.DisableIPv6
        DNSForwarder      = if ($NoInternet) { '' } else { $Defaults.DNSForwarder }
        FixNLA            = $FixNLA.IsPresent
        AdminPassword     = $AdminPassword
        AdditionalDC      = $AdditionalDC.IsPresent
        PrimaryDCIP       = $PrimaryDCIP
    }

    # Round 1: Install + promote (triggers reboot)
    # Don't use -WaitForReboot here - after promotion the local cred no longer works,
    # we need to wait with both local and domain credentials
    Write-LabLog "Installing AD DS and promoting to DC..." -Level Step
    Invoke-GuestScript -VMName $VMName -Credential $cred `
        -ScriptPath 'C:\LabScripts\Install-DC.ps1' `
        -Arguments $dcArgs

    # Wait for VM to come back after promotion reboot (domain cred required now)
    Write-LabLog "Waiting for DC to come back after promotion..." -Level Info
    Start-Sleep -Seconds 15
    $null = Wait-LabVMReady -VMName $VMName -Credential $domCred -AlternateCredential $cred

    # Verify promotion succeeded
    $promoted = $false
    foreach ($c in @($domCred, $cred)) {
        try {
            $role = Invoke-Command -VMName $VMName -Credential $c -ErrorAction Stop -ScriptBlock {
                (Get-CimInstance Win32_ComputerSystem).DomainRole
            }
            if ($role -ge 4) { $promoted = $true; break }
        } catch { }
    }

    if (-not $promoted) {
        Write-LabLog "DC promotion failed - check VM console" -Level Error
        throw "DC promotion failed for $VMName. Check the VM console and Get-DLabEventLog for details."
    }

    # Round 2: Post-config (no reboot)
    Write-LabLog "Applying post-promotion config..." -Level Step
    Invoke-GuestScript -VMName $VMName -Credential $domCred `
        -ScriptPath 'C:\LabScripts\Install-DC.ps1' `
        -Arguments $dcArgs

    # Verify AD services are fully operational (not just reachable)
    Write-LabLog "Verifying AD services..." -Level Info
    $adReady = $false
    $deadline = (Get-Date).AddMinutes(3)
    while ((Get-Date) -lt $deadline) {
        try {
            $svcOk = Invoke-Command -VMName $VMName -Credential $domCred -ErrorAction Stop -ScriptBlock {
                $ntds = Get-Service NTDS -ErrorAction SilentlyContinue
                $dns  = Get-Service DNS -ErrorAction SilentlyContinue
                ($ntds -and $ntds.Status -eq 'Running') -and ($dns -and $dns.Status -eq 'Running')
            }
            if ($svcOk) { $adReady = $true; break }
        } catch { }
        Start-Sleep -Seconds 5
    }

    if (-not $adReady) {
        Write-LabLog "AD services may not be fully ready - check VM console" -Level Warn
    }

    # DHCP runs on the first DC only. Additional DCs join an existing domain
    # that already has a DHCP server; installing a second one would cause conflicts.
    if ($AdditionalDC) {
        Write-LabLog "Additional DC - skipping DHCP installation (already running on primary DC)." -Level Info
        Write-LabLog "DC ready" -Level OK
        return
    }

    # Install and configure DHCP on the DC
    Write-LabLog "Installing DHCP server..." -Level Step
    Send-GuestScript -VMName $VMName -Credential $domCred -LocalPath (Join-Path $GuestScriptPath 'Install-DHCP.ps1')
    # Build DHCP arguments. Static IPs (gateway + DCs + servers) are all below
    # the DHCP range start, so no exclusion range is needed. The ExcludeStart /
    # ExcludeEnd keys are only added when the segment config provides them
    # (future segments with a different layout may still need exclusions).
    $dhcpArgs = @{
        ScopeID        = $NetConfig.NetworkBase       # 4-octet network address (e.g. 10.74.18.32)
        ScopeStart     = $NetConfig.DHCPScopeStart
        ScopeEnd       = $NetConfig.DHCPScopeEnd
        SubnetMask     = $NetConfig.SubnetMask        # /27: 255.255.255.224
        Gateway        = if ($NoInternet) { '' } else { $NetConfig.Gateway }
        DNSServer      = $DCIP
        DomainName     = $DomainName
        ScopeName      = "$LabName-Clients"
        LeaseDurationH = $Defaults.DHCPLeaseDurationH
    }
    if ($NetConfig.PSObject.Properties['DHCPExcludeStart'] -and $NetConfig.DHCPExcludeStart) {
        $dhcpArgs['ExcludeStart'] = $NetConfig.DHCPExcludeStart
        $dhcpArgs['ExcludeEnd']   = $NetConfig.DHCPExcludeEnd
    }
    Invoke-GuestScript -VMName $VMName -Credential $domCred `
        -ScriptPath 'C:\LabScripts\Install-DHCP.ps1' `
        -Arguments $dhcpArgs

    Write-LabLog "DC ready" -Level OK
}