# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Deploy-LabMember {
    <#
    .SYNOPSIS
        Deploys a member server VM and joins it to the domain.
    .PARAMETER VMName
        Full VM name (e.g. ProdTest-SRV01).
    .PARAMETER ShortName
        Short computer name (e.g. SRV01).
    .PARAMETER VHDXPath
        Path to the differencing disk VHDX.
    .PARAMETER MemberIP
        Static IP for the member server.
    .PARAMETER NetConfig
        Network config object from Get-LabNetworkConfig.
    .PARAMETER OSEntry
        OS catalog entry hashtable (DefaultMemoryGB, DefaultCPU, etc.).
    .PARAMETER DCIP
        IP of the domain controller (for DNS).
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
    .PARAMETER GuestScriptPath
        Path to the GuestScripts folder.
    .PARAMETER Defaults
        Lab config defaults hashtable.
    .PARAMETER MemoryGB
        Override memory in GB (0 = use OS default).
    .PARAMETER CPU
        Override vCPU count (0 = use OS default).
    #>
    param(
        [Parameter(Mandatory)][string]$VMName,
        [Parameter(Mandatory)][string]$ShortName,
        [Parameter(Mandatory)][string]$VHDXPath,
        [Parameter(Mandatory)][string]$MemberIP,
        [Parameter(Mandatory)][PSCustomObject]$NetConfig,
        [Parameter(Mandatory)][hashtable]$OSEntry,
        [Parameter(Mandatory)][string]$DCIP,
        [Parameter(Mandatory)][string]$SwitchName,
        [Parameter(Mandatory)][string]$VMPath,
        [Parameter(Mandatory)][string]$AdminPassword,
        [Parameter(Mandatory)][string]$DomainName,
        [Parameter(Mandatory)][string]$DomainNetbios,
        [Parameter(Mandatory)][string]$GuestScriptPath,
        [Parameter(Mandatory)][hashtable]$Defaults,
        [int]$MemoryGB = 0,
        [int]$CPU = 0
    )

    $memVal = if ($MemoryGB -gt 0) { $MemoryGB } else { $OSEntry.DefaultMemoryGB }
    $cpuVal = if ($CPU -gt 0) { $CPU } else { $OSEntry.DefaultCPU }

    $null = New-LabVM -VMName $VMName -VHDXPath $VHDXPath -SwitchName $SwitchName `
              -VMPath $VMPath -MemoryGB $memVal -ProcessorCount $cpuVal

    $null = Start-LabVM -VMName $VMName
    $cred = New-Object PSCredential('Administrator',
                (ConvertTo-SecureString $AdminPassword -AsPlainText -Force))

    Write-LabLog "Waiting for $VMName..." -Level Info
    $ready = Wait-LabVMReady -VMName $VMName -Credential $cred
    if (-not $ready) { Write-LabLog "$VMName did not become ready." -Level Error; return }

    Send-GuestScript -VMName $VMName -Credential $cred -LocalPath (Join-Path $GuestScriptPath 'Install-MemberServer.ps1')

    Write-LabLog "Configuring $VMName for domain join..." -Level Step
    Invoke-GuestScript -VMName $VMName -Credential $cred `
        -ScriptPath 'C:\LabScripts\Install-MemberServer.ps1' `
        -Arguments @{
            DomainName     = $DomainName
            DomainPassword = $AdminPassword
            ComputerName   = $ShortName
            StaticIP       = $MemberIP
            Gateway        = $NetConfig.Gateway
            DNSServer      = $DCIP
            DisableIPv6    = $Defaults.DisableIPv6
        }

    # Wait for VM to come back after domain join reboot
    # Domain credentials required now - local admin no longer works after join
    $domCred = New-Object PSCredential("$DomainNetbios\Administrator",
                   (ConvertTo-SecureString $AdminPassword -AsPlainText -Force))
    Write-LabLog "Waiting for $VMName after domain join reboot..." -Level Info
    Start-Sleep -Seconds 15
    $null = Wait-LabVMReady -VMName $VMName -Credential $domCred -AlternateCredential $cred

    # Verify domain membership properly. PartOfDomain alone is fooled by local-SAM fallback
    # when domCred happens to match the local admin password. Cross-check against the
    # actual domain name so we know for sure.
    $joined = $false
    for ($round = 1; $round -le 5; $round++) {
        try {
            $cs = Invoke-Command -VMName $VMName -Credential $domCred -ErrorAction Stop -ScriptBlock {
                Get-CimInstance Win32_ComputerSystem | Select-Object PartOfDomain, Domain
            }
            if ($cs.PartOfDomain -and $cs.Domain -eq $DomainName) {
                Write-LabLog "$VMName joined domain ($($cs.Domain))" -Level OK
                $joined = $true
                break
            }
        } catch { }
        Start-Sleep -Seconds 15
    }

    if (-not $joined) {
        Write-LabLog "$VMName is NOT in domain $DomainName after 5 checks. Join likely failed - check VM console and guest script output." -Level Error
    }

    Write-LabLog "Member server deployment complete" -Level OK
}