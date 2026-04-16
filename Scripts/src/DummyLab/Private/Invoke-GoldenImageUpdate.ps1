# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

#
# Phase 4 of the golden-image build: Patch.
#
# Sends the guest prep script into the VM, runs it in -Phase Updates,
# verifies the .updates-done marker after each round. Loops up to five
# rounds to catch multi-stage Windows Update dependencies. Network is
# re-verified before every round because reboots during patching often
# drop the static configuration.
#
# If the plan already flipped to unpatched (e.g. internet dropped after
# Boot), this phase is a no-op that returns 'Skipped' so the orchestrator
# can mark the step as skipped rather than failed.

function Invoke-GoldenImageUpdate {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Plan
    )

    if (-not $Plan.InstallUpdates) {
        Write-LabLog 'Phase 4: Patch - skipped (unpatched build).' -Level Info
        return 'Skipped'
    }

    Write-LabLog 'Phase 4: Windows Updates' -Level Step

    $cred       = $Plan.AdminCredential
    $prepScript = Join-Path $Plan.GuestPath 'Invoke-GoldenImagePrep.ps1'

    # Copy the guest script in once. The Updates and Sysprep phases both
    # execute it by path.
    Send-GuestScript -VMName $Plan.TempVMName -Credential $cred -LocalPath $prepScript

    $maxRounds = 5
    for ($round = 1; $round -le $maxRounds; $round++) {
        Write-LabLog "Update round $round / $maxRounds" -Level Info

        $netOk = Confirm-GoldenImageInternet -VMName     $Plan.TempVMName `
                                             -Credential $cred `
                                             -IP         $Plan.TempVMIP `
                                             -Gateway    $Plan.TempGateway
        if (-not $netOk) {
            Write-LabLog "No internet before round $round - ending patch loop." -Level Warn
            return 'Partial'
        }

        Invoke-GuestScript -VMName $Plan.TempVMName -Credential $cred `
            -ScriptPath 'C:\LabScripts\Invoke-GoldenImagePrep.ps1' `
            -Arguments @{
                InstallUpdates   = $true
                UpdateTimeoutMin = $Plan.UpdateTimeoutMin
                Phase            = 'Updates'
            } -WaitForReboot

        try {
            $done = Invoke-Command -VMName $Plan.TempVMName -Credential $cred -ErrorAction Stop -ScriptBlock {
                Test-Path 'C:\LabScripts\.updates-done'
            }
            if ($done) {
                Write-LabLog 'All updates installed' -Level OK
                return 'Installed'
            }
        } catch {
            Start-Sleep -Seconds 15
            Wait-LabVMReady -VMName $Plan.TempVMName -Credential $cred
        }
    }

    # Exhausted rounds without the marker.
    Write-LabLog "Reached $maxRounds update rounds without completion marker." -Level Warn
    return 'Incomplete'
}
