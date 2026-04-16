# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Remove-DLab {
    <#
    .SYNOPSIS
        Tears down an entire Dummy.Lab lab.
    .DESCRIPTION
        Removes every VM in the lab, the virtual switch, the NAT configuration
        (if present), and the lab storage directory (state file, VMs folder,
        Disks folder, Operations folder). Golden images are never touched -
        other labs may reference them.

        The operation is recorded as a DLab.Operation with steps for each
        resource removed. Supports -WhatIf for a dry run that lists resources
        that would be removed without touching anything.

        Idempotent: removing a partially-torn-down lab cleans up whatever
        remains. For safety on multi-tenant hosts, destruction is strictly
        state-driven: only resources recorded in the lab's state.Infrastructure
        and state.VMs are touched. If state is missing or a field is empty,
        the corresponding host resource is NOT searched for by name pattern
        and NOT removed - a Warn event is emitted instead. Use Get-DLabNAT
        / Get-VMSwitch / Get-VM plus the matching Remove-* cmdlet to clean
        up undocumented resources explicitly.

        Undocumented VMs (Hyper-V VMs whose names match the lab's naming
        pattern but are not in state.VMs) are detected and logged as Warn
        events but NOT removed. Operators see them in
        Get-DLabEventLog / Get-DLabOperation.Steps and decide whether
        those VMs belong to the lab (partial deploy leftover) or to a
        different system.
    .PARAMETER Name
        Lab name to remove.
    .PARAMETER KeepStorage
        Do not delete the lab storage directory (Labs\<name>\). Useful when
        you want to preserve operation history and event correlations for
        audit purposes.
    .EXAMPLE
        Remove-DLab -Name PipeTest -WhatIf
    .EXAMPLE
        Remove-DLab -Name PipeTest
    .EXAMPLE
        Remove-DLab -Name PipeTest -PassThru | Select-Object Status, DurationSec
    .NOTES
        Silent on success by default. Use -PassThru to receive the DLab.Operation
        object. The operation is always persisted to disk regardless and can be
        retrieved later with Get-DLabOperation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('DLab.Operation')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('LabName')]
        [string]$Name,

        [switch]$KeepStorage,
        [switch]$PassThru
    )

    begin {
        $cfg = Get-DLabConfigInternal
    }

    process {
        $labName   = $Name
        $statePath = Get-DLabStorePath -Kind LabState -LabName $labName
        $labDir    = Get-DLabStorePath -Kind LabDir   -LabName $labName

        $state = $null
        if (Test-Path $statePath) {
            try { $state = Get-Content $statePath -Raw | ConvertFrom-Json } catch { }
        }

        # Resolve which VMs will be touched. State-driven only: only VMs
        # recorded in state.VMs get removed. VMs matching the lab's naming
        # pattern but absent from state are NOT swept - we emit a Warn event
        # naming them so the operator can clean them up explicitly with
        # Remove-DLabVM (or Remove-VM for non-lab cases). See the docstring
        # for the rationale.
        $vmNames = @()
        if ($state -and $state.PSObject.Properties['VMs'] -and $state.VMs) {
            $vmNames = @($state.VMs | ForEach-Object { $_.Name })
        }
        $vmNames = @($vmNames | Select-Object -Unique)

        # Detect undocumented VMs matching the lab's naming pattern so the
        # operator can see the drift without the cmdlet making decisions.
        # This is observation only, not action.
        $undocumentedVMs = @(Get-VM -ErrorAction SilentlyContinue |
                             Where-Object { $_.Name -match "^$labName-(DC|SRV)" -and $_.Name -notin $vmNames } |
                             ForEach-Object { $_.Name })

        # State-driven resolution: only touch what the lab itself recorded.
        # Every access is strict-mode safe via PSObject.Properties lookups;
        # an empty string means "not recorded" and is treated as "nothing
        # to remove at the infrastructure layer".

        $recordedSwitch = ''
        if ($state -and
            $state.PSObject.Properties['Infrastructure'] -and
            $state.Infrastructure -and
            $state.Infrastructure.PSObject.Properties['SwitchName']) {
            $recordedSwitch = [string]$state.Infrastructure.SwitchName
        }

        $recordedNAT = ''
        if ($state -and
            $state.PSObject.Properties['Infrastructure'] -and
            $state.Infrastructure -and
            $state.Infrastructure.PSObject.Properties['NATName']) {
            $recordedNAT = [string]$state.Infrastructure.NATName
        }

        # Switch and NAT are only candidates for removal if the lab's own
        # state recorded them. No name-pattern fallbacks, no Get-NetNat
        # scan - the risk of stomping a resource owned by another system
        # outweighs the convenience of an orphan sweep.
        $switchName   = $recordedSwitch
        $natName      = $recordedNAT
        $switchExists = $switchName -and [bool](Get-VMSwitch -Name $switchName -ErrorAction SilentlyContinue)
        $natExists    = $natName    -and [bool](Get-NetNat    -Name $natName    -ErrorAction SilentlyContinue)
        $storageExists = Test-Path $labDir

        $resourceSummary = @(
            "VMs: $($vmNames.Count)$(if ($undocumentedVMs.Count -gt 0) { " (+$($undocumentedVMs.Count) undocumented, not removed)" })"
            "Switch: $(if ($switchExists) { $switchName } else { 'none recorded' })"
            "NAT: $(if ($natExists) { $natName } else { 'none recorded' })"
            "Storage: $(if ($storageExists -and -not $KeepStorage) { $labDir } else { 'preserved' })"
        ) -join ' | '

        if (-not $PSCmdlet.ShouldProcess("$labName ($resourceSummary)", 'Tear down lab')) { return }

        # Teardown operations are recorded in the GLOBAL Operations\ folder,
        # not the lab's, because the lab directory (and its Operations\ subfolder)
        # is one of the resources about to be removed. A lab-scoped record
        # would self-delete mid-execution.
        $op = New-DLabOperation -Kind 'Remove-DLab' -Target $labName `
                                -Parameters @{ LabName = $labName; KeepStorage = [bool]$KeepStorage }
        Write-DLabEvent -Level Step -Source 'Remove-DLab' `
            -Message "Tearing down lab $labName" `
            -OperationId $op.OperationId `
            -Data @{ LabName = $labName; Resources = $resourceSummary }

        $removed = 0
        $errors  = @()

        # Remove VMs - state-driven only. Suppress the "already in specified
        # state" warnings that Stop-VM emits when the VM is already off -
        # that's the expected case during teardown and the noise just
        # confuses operators.
        foreach ($vmName in $vmNames) {
            try {
                if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) {
                    Stop-VM -Name $vmName -TurnOff -Force `
                            -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null
                    Remove-VM -Name $vmName -Force -ErrorAction SilentlyContinue | Out-Null
                    Write-DLabEvent -Level Ok -Source 'Remove-DLab' `
                        -Message "Removed VM: $vmName" -OperationId $op.OperationId
                    $removed++
                }
            } catch {
                $errors += "VM ${vmName}: $($_.Exception.Message)"
                Write-DLabEvent -Level Warn -Source 'Remove-DLab' `
                    -Message "VM removal failed for ${vmName}: $($_.Exception.Message)" `
                    -OperationId $op.OperationId
            }
        }

        # Surface any VMs matching the lab's naming pattern that are NOT
        # in state.VMs. These are NOT removed - observation only - so
        # operators can clean them up explicitly with Remove-DLabVM
        # (or Remove-VM for non-lab cases).
        foreach ($undoc in $undocumentedVMs) {
            Write-DLabEvent -Level Warn -Source 'Remove-DLab' `
                -Message "Undocumented VM '$undoc' matches lab naming pattern but is not in state.VMs. Not removed. Remove explicitly with: Remove-DLabVM -LabName $labName -Name <short> (or Remove-VM for non-lab cases)." `
                -OperationId $op.OperationId `
                -Data @{ LabName = $labName; VMName = $undoc }
        }

        # Remove switch
        if ($switchExists) {
            try {
                Remove-VMSwitch -Name $switchName -Force -ErrorAction Stop | Out-Null
                Write-DLabEvent -Level Ok -Source 'Remove-DLab' `
                    -Message "Removed switch: $switchName" -OperationId $op.OperationId
                $removed++
            } catch {
                $errors += "Switch ${switchName}: $($_.Exception.Message)"
            }
        }

        # Remove NAT - state-driven only.
        if ($natExists) {
            try {
                Remove-NetNat -Name $natName -Confirm:$false -ErrorAction Stop | Out-Null
                Write-DLabEvent -Level Ok -Source 'Remove-DLab' `
                    -Message "Removed NAT: $natName" -OperationId $op.OperationId
                $removed++
            } catch {
                $errors += "NAT ${natName}: $($_.Exception.Message)"
                Write-DLabEvent -Level Warn -Source 'Remove-DLab' `
                    -Message "NAT removal failed for ${natName}: $($_.Exception.Message)" `
                    -OperationId $op.OperationId
            }
        } elseif ($natName) {
            # State recorded a NAT name but no live NetNat exists. Log it
            # so operators can see the drift without the cmdlet making
            # assumptions.
            Write-DLabEvent -Level Info -Source 'Remove-DLab' `
                -Message "Recorded NAT '$natName' is not present on host - skipping." `
                -OperationId $op.OperationId
        } elseif (-not $state) {
            # No state file at all. Unable to know what this lab created;
            # warn so the operator can inspect manually.
            Write-DLabEvent -Level Warn -Source 'Remove-DLab' `
                -Message "No state file found for '$labName' - cannot locate recorded NAT or switch. Use Get-DLabNAT / Get-VMSwitch and remove manually if needed." `
                -OperationId $op.OperationId
        }

        # Remove storage (unless -KeepStorage)
        if ($storageExists -and -not $KeepStorage) {
            try {
                Remove-Item -Path $labDir -Recurse -Force -ErrorAction Stop
                Write-DLabEvent -Level Ok -Source 'Remove-DLab' `
                    -Message "Removed storage: $labDir" -OperationId $op.OperationId
                $removed++
            } catch {
                $errors += "Storage ${labDir}: $($_.Exception.Message)"
            }
        }

        if ($errors.Count -gt 0) {
            $finalOp = $op | Complete-DLabOperation -Status Failed `
                           -ErrorMessage ($errors -join '; ') `
                           -Result @{ LabName = $labName; ResourcesRemoved = $removed }
            Write-DLabEvent -Level Warn -Source 'Remove-DLab' `
                -Message "Lab $labName teardown completed with $($errors.Count) error(s)" `
                -OperationId $op.OperationId
        } elseif ($removed -eq 0) {
            $finalOp = $op | Complete-DLabOperation -Status Succeeded `
                           -Result @{ LabName = $labName; ResourcesRemoved = 0 }
            Write-DLabEvent -Level Info -Source 'Remove-DLab' `
                -Message "Nothing to remove for $labName" -OperationId $op.OperationId
        } else {
            $finalOp = $op | Complete-DLabOperation -Status Succeeded `
                           -Result @{ LabName = $labName; ResourcesRemoved = $removed }
            Write-DLabEvent -Level Ok -Source 'Remove-DLab' `
                -Message "Lab $labName removed ($removed resources)" -OperationId $op.OperationId
        }

        if ($PassThru) { $finalOp }
    }
}
