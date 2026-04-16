# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function New-DLabVM {
    <#
    .SYNOPSIS
        Creates a Hyper-V VM with lab-aware defaults.
    .DESCRIPTION
        Wraps the legacy New-LabVM helper and New-VM to provide a clean,
        event-instrumented public interface. Creates a Generation 2 VM with:
          - Dynamic memory (startup = max = specified GB, 512 MB floor)
          - Lab-appropriate vCPU count (scaled up for DC on high-thread hosts)
          - Integration services enabled (for PowerShell Direct)
          - Checkpoints disabled (deployment uses explicit checkpoints only)
          - Secure Boot disabled (lab flexibility)

        The resulting VM is ready for immediate start and guest execution.
        It is idempotent: if the VM already exists, it is reused.

        Live-off-the-land: wraps New-VM, Set-VMProcessor, Set-VMMemory, and
        native integration service/firmware/checkpoint cmdlets.
    .PARAMETER Name
        Full Hyper-V VM name (e.g. 'MyLab-DC01'). Must be unique on the host.
    .PARAMETER VHDXPath
        Full path to the VHDX (typically a differencing disk) for this VM.
    .PARAMETER SwitchName
        Name of the virtual switch to connect the VM to.
    .PARAMETER MemoryGB
        RAM allocation in GB. Enabled dynamic memory with this as both startup
        and maximum. Default: 4.
    .PARAMETER ProcessorCount
        vCPU count. Default: 2. Overridden upward for DC VMs on hosts with
        more than 12 logical processors (minimum 4 vCPUs for DC).
    .PARAMETER VMPath
        Folder where Hyper-V stores the VM configuration (.vmcx, snapshots, etc.).
        If omitted, uses Hyper-V's default path. Should be under the lab storage
        root for easy teardown.
    .PARAMETER IsLabDC
        Switch. When set, marks this as a Domain Controller and scales vCPU count:
        if the host has more than 12 logical processors, the vCPU count is raised
        to at least 4.
    .PARAMETER PassThru
        Return a DLab.VM object. By default, the cmdlet produces no output.
    .EXAMPLE
        New-DLabVM -Name MyLab-DC01 -VHDXPath C:\Dummy.Lab\Labs\MyLab\VMs\DC01.vhdx `
            -SwitchName MyLabSwitch -IsLabDC
    .EXAMPLE
        New-DLabVM -Name MyLab-SRV01 -VHDXPath C:\Dummy.Lab\Labs\MyLab\VMs\SRV01.vhdx `
            -SwitchName MyLabSwitch -MemoryGB 2 -ProcessorCount 2 -PassThru |
            Start-DLabVM
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('DLab.VM')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(Mandatory, Position = 1)]
        [string]$VHDXPath,

        [Parameter(Mandatory, Position = 2)]
        [string]$SwitchName,

        [int]$MemoryGB = 4,

        [int]$ProcessorCount = 2,

        [string]$VMPath = '',

        [switch]$IsLabDC,

        [switch]$PassThru
    )

    if (-not $PSCmdlet.ShouldProcess($Name, 'Create VM')) { return }

    Write-DLabEvent -Level Step -Source 'New-DLabVM' `
        -Message "Creating VM '$Name' (${MemoryGB}GB, $ProcessorCount vCPUs, Switch: $SwitchName)" `
        -Data @{ VMName = $Name; MemoryGB = $MemoryGB; ProcessorCount = $ProcessorCount; IsLabDC = $IsLabDC }

    try {
        $resultVM = New-LabVM `
            -VMName $Name `
            -VHDXPath $VHDXPath `
            -SwitchName $SwitchName `
            -MemoryGB $MemoryGB `
            -ProcessorCount $ProcessorCount `
            -VMPath $VMPath `
            -IsLabDC:$IsLabDC

        Write-DLabEvent -Level Ok -Source 'New-DLabVM' `
            -Message "VM '$Name' created" `
            -Data @{ VMName = $Name; State = $resultVM.State }

        if ($PassThru) {
            Get-DLabVM -VMName $Name
        }
    } catch {
        Write-DLabEvent -Level Error -Source 'New-DLabVM' `
            -Message "Failed to create VM '$Name': $($_.Exception.Message)" `
            -Data @{ VMName = $Name; Error = $_.Exception.Message }
        throw
    }
}
