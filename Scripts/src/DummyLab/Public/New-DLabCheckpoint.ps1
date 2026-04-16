# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function New-DLabCheckpoint {
    <#
    .SYNOPSIS
        Creates a checkpoint (snapshot) for a lab VM.
    .DESCRIPTION
        Wraps the native Checkpoint-VM cmdlet with event instrumentation.
        Temporarily enables checkpoints on the VM, creates the named checkpoint,
        then disables checkpoints again (deployment policy: only explicit
        checkpoints via this cmdlet are allowed).

        Live-off-the-land: wraps Checkpoint-VM and Set-VM.
    .PARAMETER VMName
        Full Hyper-V VM name.
    .PARAMETER SnapshotName
        Name for the checkpoint. If omitted, Hyper-V generates a default name.
    .PARAMETER PassThru
        Return the checkpoint object. By default, the cmdlet produces no output.
    .EXAMPLE
        New-DLabCheckpoint -VMName MyLab-DC01 -SnapshotName 'Before DNS Config'
    .EXAMPLE
        New-DLabCheckpoint -VMName MyLab-SRV01 -SnapshotName 'Clean' -PassThru
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType('DLab.Checkpoint')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string]$VMName,

        [Parameter(Position = 1)]
        [string]$SnapshotName = ''
    )

    process {
        if (-not $PSCmdlet.ShouldProcess($VMName, "Create checkpoint '$SnapshotName'")) { return }

        $snapLabel = if ($SnapshotName) { "'$SnapshotName'" } else { "(auto-named)" }
        Write-DLabEvent -Level Step -Source 'New-DLabCheckpoint' `
            -Message "Creating checkpoint $snapLabel for VM '$VMName'" `
            -Data @{ VMName = $VMName; SnapshotName = $SnapshotName }

        try {
            # Temporarily enable checkpoints
            Set-VM -VMName $VMName -CheckpointType Standard -ErrorAction Stop

            # Create the checkpoint
            $checkpointParams = @{
                Name        = $VMName
                ErrorAction = 'Stop'
            }
            if ($SnapshotName) {
                $checkpointParams['SnapshotName'] = $SnapshotName
            }
            $checkpoint = Checkpoint-VM @checkpointParams

            # Disable checkpoints again
            Set-VM -VMName $VMName -CheckpointType Disabled -ErrorAction Stop

            Write-DLabEvent -Level Ok -Source 'New-DLabCheckpoint' `
                -Message "Checkpoint $snapLabel created for VM '$VMName'" `
                -Data @{ VMName = $VMName; SnapshotName = if ($checkpoint) { $checkpoint.Name } else { $SnapshotName } }

            if ($PSBoundParameters.ContainsKey('PassThru')) {
                $checkpoint
            }
        } catch {
            Write-DLabEvent -Level Error -Source 'New-DLabCheckpoint' `
                -Message "Failed to create checkpoint for VM '$VMName': $($_.Exception.Message)" `
                -Data @{ VMName = $VMName; Error = $_.Exception.Message }
            throw
        }
    }
}
