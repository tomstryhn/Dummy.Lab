# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function New-LabCheckpoint {
    <#
    .SYNOPSIS
        Creates a named checkpoint for a lab VM.
    #>
    param([string]$VMName, [string]$CheckpointName)

    Write-Host "  [*] Creating checkpoint '$CheckpointName' for '$VMName'..." -ForegroundColor Cyan
    Set-VM -VMName $VMName -CheckpointType Standard
    Checkpoint-VM -Name $VMName -SnapshotName $CheckpointName -ErrorAction Stop
    Set-VM -VMName $VMName -CheckpointType Disabled
    Write-Host "      Done." -ForegroundColor Green
}
