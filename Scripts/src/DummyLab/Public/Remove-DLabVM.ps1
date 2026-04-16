# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Remove-DLabVM {
    <#
    .SYNOPSIS
        Removes a VM from a Dummy.Lab lab.
    .DESCRIPTION
        Performs a coordinated teardown of a single lab VM:
          1. Removes the AD computer object from the DC (best-effort).
          2. Stops the VM.
          3. Removes the VM from Hyper-V.
          4. Deletes the differencing disk.
          5. Removes the VM entry from the lab state file.

        Every step emits an event. The operation is recorded as a DLab.Operation
        and can be queried with Get-DLabOperation.

        Idempotent: passing a name that no longer exists in Hyper-V still
        cleans up state, disk, and AD object residue.
    .PARAMETER LabName
        Lab containing the VM.
    .PARAMETER Name
        VM short name (e.g. 'SRV01') or full VM name (e.g. 'PipeTest-SRV01').
        Both forms are accepted.
    .PARAMETER SkipADCleanup
        Do not attempt to remove the AD computer object (for example if the
        DC is unavailable or the lab has no DC).
    .EXAMPLE
        Remove-DLabVM -LabName PipeTest -Name SRV01 -WhatIf
    .EXAMPLE
        Get-DLabVM -LabName PipeTest -Role Server | Remove-DLabVM -Confirm:$false
    .EXAMPLE
        Remove-DLabVM -LabName PipeTest -Name SRV01 -PassThru | Select-Object Status, DurationSec
    .NOTES
        Silent on success by default. Use -PassThru to receive the DLab.Operation
        object for further inspection or logging. The operation is always persisted
        to disk regardless and can be retrieved later with Get-DLabOperation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('DLab.Operation')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$LabName,

        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('ShortName', 'VMName')]
        [string]$Name,

        [switch]$SkipADCleanup,
        [switch]$PassThru
    )

    begin {
        $cfg = Get-DLabConfigInternal
    }

    process {
        # Normalise names
        $fullName = if ($Name -like "$LabName-*") { $Name } else { "$LabName-$Name" }
        $shortName = $fullName -replace "^$LabName-", ''
        $statePath = Get-DLabStorePath -Kind LabState -LabName $LabName

        if (-not (Test-Path $statePath)) {
            Write-Error "Lab not found: $LabName"
            return
        }

        if (-not $PSCmdlet.ShouldProcess($fullName, "Remove VM from lab $LabName")) { return }

        $op = New-DLabOperation -Kind 'Remove-DLabVM' -Target $fullName -LabName $LabName `
                                -Parameters @{ LabName = $LabName; Name = $shortName; SkipADCleanup = [bool]$SkipADCleanup }
        Write-DLabEvent -Level Step -Source 'Remove-DLabVM' `
            -Message "Removing $fullName from $LabName" `
            -OperationId $op.OperationId `
            -Data @{ LabName = $LabName; VMName = $fullName }

        $encounteredError = $null

        try {
            $state = Read-LabState -Path $statePath

            # Step 1: AD cleanup (best-effort)
            if (-not $SkipADCleanup -and $state.VMs) {
                $dcVM = @($state.VMs | Where-Object { $_.Role -eq 'DC' } | Select-Object -First 1)
                if ($dcVM -and $dcVM[0]) {
                    $adminPwd  = $cfg.AdminPassword
                    $netbios   = if ($state.PSObject.Properties['DomainNetbios']) { $state.DomainNetbios } else { $LabName }
                    $domCred = New-Object PSCredential("$netbios\Administrator",
                                   (ConvertTo-SecureString $adminPwd -AsPlainText -Force))
                    try {
                        Invoke-Command -VMName $dcVM[0].Name -Credential $domCred -ErrorAction Stop -ScriptBlock {
                            param($cn)
                            Import-Module ActiveDirectory -ErrorAction SilentlyContinue
                            $obj = Get-ADComputer -Identity $cn -ErrorAction SilentlyContinue
                            if ($obj) {
                                $obj | Remove-ADObject -Recursive -Confirm:$false -ErrorAction Stop
                            }
                        } -ArgumentList $shortName
                        Write-DLabEvent -Level Ok -Source 'Remove-DLabVM' `
                            -Message "AD object removed for $shortName" `
                            -OperationId $op.OperationId
                    } catch {
                        Write-DLabEvent -Level Warn -Source 'Remove-DLabVM' `
                            -Message "AD cleanup failed for ${shortName}: $($_.Exception.Message)" `
                            -OperationId $op.OperationId
                    }
                }
            }

            # Step 2+3: Stop and remove the VM. Suppress "already in specified
            # state" warning from Stop-VM on an already-off VM - expected case.
            $hvVM = Get-VM -Name $fullName -ErrorAction SilentlyContinue
            if ($hvVM) {
                Stop-VM -Name $fullName -TurnOff -Force `
                        -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null
                Remove-VM -Name $fullName -Force -ErrorAction SilentlyContinue | Out-Null
                Write-DLabEvent -Level Ok -Source 'Remove-DLabVM' `
                    -Message "Hyper-V VM removed: $fullName" `
                    -OperationId $op.OperationId
            } else {
                Write-DLabEvent -Level Info -Source 'Remove-DLabVM' `
                    -Message "VM $fullName not present in Hyper-V (already removed?)" `
                    -OperationId $op.OperationId
            }

            # Step 4: Differencing disk
            $labDir   = Get-DLabStorePath -Kind LabDir -LabName $LabName
            $diskPath = Join-Path (Join-Path $labDir 'Disks') "$fullName-osdisk.vhdx"
            if (Test-Path $diskPath) {
                Remove-Item -Path $diskPath -Force -ErrorAction SilentlyContinue
                Write-DLabEvent -Level Ok -Source 'Remove-DLabVM' `
                    -Message "Differencing disk removed: $diskPath" `
                    -OperationId $op.OperationId
            }

            # Step 5: State update (atomic)
            $null = Update-LabStateLocked -Path $statePath -UpdateScript {
                param($s)
                if ($s.VMs) {
                    $s.VMs = @($s.VMs | Where-Object { $_.Name -ne $fullName })
                }
                $s
            }
            Write-DLabEvent -Level Ok -Source 'Remove-DLabVM' `
                -Message "State updated, $fullName entry removed" `
                -OperationId $op.OperationId

        } catch {
            $encounteredError = $_.Exception.Message
            Write-DLabEvent -Level Error -Source 'Remove-DLabVM' `
                -Message "Remove failed: $encounteredError" `
                -OperationId $op.OperationId
        }

        if ($encounteredError) {
            $finalOp = $op | Complete-DLabOperation -Status Failed -ErrorMessage $encounteredError
        } else {
            $finalOp = $op | Complete-DLabOperation -Status Succeeded -Result @{ VMName = $fullName }
            Write-DLabEvent -Level Ok -Source 'Remove-DLabVM' `
                -Message "$fullName removed successfully" `
                -OperationId $op.OperationId
        }

        if ($PassThru) { $finalOp }
    }
}
