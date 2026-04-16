# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

#
# Phase 5 of the golden-image build: Sysprep.
#
# Runs the guest prep script in -Phase Sysprep, then waits for the VM to
# shut down. Sysprep is the gate between "this is a working VM" and "this
# is a reusable template": after this phase the VHDX must not be booted
# again before Protect.

function Invoke-GoldenImageSysprep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Plan
    )

    Write-LabLog 'Phase 5: Cleanup + Sysprep' -Level Step

    $cred = $Plan.AdminCredential

    # Send the prep script unconditionally. When -SkipUpdates was used, Phase 4
    # returned early before Send-GuestScript ran, so the script is not in the VM.
    $prepScript = Join-Path $Plan.GuestPath 'Invoke-GoldenImagePrep.ps1'
    Send-GuestScript -VMName $Plan.TempVMName -Credential $cred -LocalPath $prepScript

    Invoke-GuestScript -VMName $Plan.TempVMName -Credential $cred `
        -ScriptPath 'C:\LabScripts\Invoke-GoldenImagePrep.ps1' `
        -Arguments @{ Phase = 'Sysprep' }

    Write-LabLog 'Waiting for VM to shut down after Sysprep...' -Level Info
    $deadline = (Get-Date).AddMinutes(15)
    while ((Get-Date) -lt $deadline) {
        $state = (Get-VM -Name $Plan.TempVMName -ErrorAction SilentlyContinue).State
        if ($state -eq 'Off') {
            Write-LabLog 'VM shut down (Sysprep complete)' -Level OK
            return
        }
        Start-Sleep -Seconds 5
    }

    # Timeout: force stop rather than leave the VM running. A generalised VM
    # left booted risks breaking the sysprep seal on the next logon.
    Write-LabLog 'VM did not shut down within 15 minutes, forcing stop.' -Level Warn
    Stop-VM -Name $Plan.TempVMName -TurnOff -Force
}
