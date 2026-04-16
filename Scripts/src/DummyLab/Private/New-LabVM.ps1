# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function New-LabVM {
    <#
    .SYNOPSIS
        Creates a Hyper-V VM with standard lab settings.
    .PARAMETER VMName
        Name of the VM.
    .PARAMETER VHDXPath
        Full path to the VHDX (differencing disk) for this VM.
    .PARAMETER SwitchName
        Name of the virtual switch to connect to.
    .PARAMETER VMPath
        Folder where Hyper-V stores the VM configuration files (.vmcx, snapshots, etc.).
        Should be under the lab storage root so teardown can clean it up.
        Example: C:\Dummy.Lab\DummyLab\VMs
    .PARAMETER MemoryGB
        Maximum and startup RAM in GB. Dynamic memory enabled with 512 MB floor.
        Default: 4.
    .PARAMETER ProcessorCount
        vCPU count. Default: 2. Overridden to 4 for DC VMs when host has > 12 logical processors.
    .PARAMETER IsLabDC
        Flag this VM as a Domain Controller. Enables CPU scaling: if the host has more than
        12 logical processors, the vCPU count is raised to at least 4.
    .PARAMETER Generation
        VM generation. Default: 2 (required for UEFI / modern OS).
    .PARAMETER WhatIf
        Dry run.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$VMName,

        [Parameter(Mandatory)]
        [string]$VHDXPath,

        [Parameter(Mandatory)]
        [string]$SwitchName,

        [string]$VMPath         = '',   # If empty, Hyper-V uses its system default
        [int]$MemoryGB          = 4,
        [int]$ProcessorCount    = 2,
        [switch]$IsLabDC,
        [int]$Generation        = 2,
        [switch]$WhatIf
    )

    # CPU scaling: DC on a host with > 12 logical processors gets at least 4 vCPUs
    $resolvedCPU = $ProcessorCount
    if ($IsLabDC) {
        $hostThreads = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
        if ($hostThreads -gt 12) {
            $resolvedCPU = [Math]::Max($ProcessorCount, 4)
            Write-Host "  [~] Host has $hostThreads threads, DC vCPU raised to $resolvedCPU" -ForegroundColor DarkGray
        }
    }

    $existing = Get-VM -Name $VMName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  [~] VM '$VMName' already exists (State: $($existing.State))." -ForegroundColor DarkGray
        return $existing
    }

    if ($WhatIf) {
        $dcTag = if ($IsLabDC) { ' [DC]' } else { '' }
        Write-Host "  [?] WhatIf: Would create VM '$VMName'$dcTag | Gen$Generation | ${MemoryGB}GB RAM (dynamic) | $resolvedCPU vCPUs | Switch: $SwitchName" -ForegroundColor DarkCyan
        if ($VMPath) { Write-Host "             VM config path: $VMPath" -ForegroundColor DarkCyan }
        return $null
    }

    Write-Host "  [+] Creating VM '$VMName'..." -ForegroundColor Cyan

    $memBytes  = $MemoryGB * 1GB

    # Build New-VM params - only include -Path if explicitly specified
    $newVMParams = @{
        Name               = $VMName
        Generation         = $Generation
        MemoryStartupBytes = $memBytes
        VHDPath            = $VHDXPath
        SwitchName         = $SwitchName
        ErrorAction        = 'Stop'
    }
    if ($VMPath) {
        # Ensure the per-VM subfolder exists
        $vmFolder = Join-Path $VMPath $VMName
        if (-not (Test-Path $vmFolder)) {
            New-Item -ItemType Directory -Path $vmFolder -Force | Out-Null
        }
        $newVMParams['Path'] = $VMPath
    }

    $vm = New-VM @newVMParams

    # Processor
    Set-VMProcessor -VMName $VMName -Count $resolvedCPU

    # Dynamic memory - 512 MB floor, configured GB ceiling
    Set-VMMemory -VMName $VMName `
        -DynamicMemoryEnabled $true `
        -StartupBytes $memBytes `
        -MinimumBytes 512MB `
        -MaximumBytes $memBytes

    # Enable ALL integration services
    Get-VMIntegrationService -VMName $VMName | ForEach-Object {
        $svc = $_
        if (-not $svc.Enabled) {
            Enable-VMIntegrationService -VMName $VMName -Name $svc.Name -ErrorAction SilentlyContinue
        }
    }

    # Checkpoints off - deployment uses explicit checkpoints via New-LabCheckpoint only
    Set-VM -VMName $VMName -CheckpointType Disabled

    # Secure boot off - lab flexibility
    Set-VMFirmware -VMName $VMName -EnableSecureBoot Off -ErrorAction SilentlyContinue

    Write-Host "      VM '$VMName' created: ${MemoryGB}GB dynamic | $resolvedCPU vCPUs | integration services on | checkpoints off" -ForegroundColor Green
    if ($VMPath) { Write-Host "      Config: $VMPath" -ForegroundColor DarkGray }
    return $vm
}
