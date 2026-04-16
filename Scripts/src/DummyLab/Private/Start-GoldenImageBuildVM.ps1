# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

#
# Phase 3 of the golden-image build: Boot.
#
# Ensures the shared DLab infrastructure exists (DLab-Internal switch +
# DLab-NAT), registers the temp VM against the new VHDX, starts it, and
# waits for PowerShell Direct to become reachable. When -InstallUpdates is
# in effect, internet access is verified before this phase returns; if no
# internet can be established, the plan is mutated to the unpatched variant
# and the caller can skip the Patch phase.

function Start-GoldenImageBuildVM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Plan
    )

    Write-LabLog "Phase 3: Boot temp VM" -Level Step

    # Ensure shared switch + NAT are in place. Idempotent - fast if already exists.
    Ensure-DLabSharedInfrastructure

    # Register and start temp VM on the shared switch
    $null = New-LabVM -VMName         $Plan.TempVMName `
                      -VHDXPath       $Plan.VHDXPath `
                      -SwitchName     $Plan.TempSwitchName `
                      -MemoryGB       $Plan.OSEntry.DefaultMemoryGB `
                      -ProcessorCount 4

    Start-LabVM -VMName $Plan.TempVMName

    $cred = [pscredential]::new('Administrator',
                                (ConvertTo-SecureString $Plan.AdminPassword -AsPlainText -Force))

    Write-LabLog 'Waiting for VM to complete initial setup...' -Level Info
    $ready = Wait-LabVMReady -VMName $Plan.TempVMName -Credential $cred -TimeoutMinutes 15
    if (-not $ready) {
        throw "Temp VM '$($Plan.TempVMName)' did not become ready within 15 minutes."
    }
    Write-LabLog 'VM ready for PowerShell Direct' -Level OK

    # Attach credential onto the plan so later phases can use it.
    $Plan | Add-Member -NotePropertyName AdminCredential -NotePropertyValue $cred -Force

    # If patching was requested, verify internet before handing off to Patch.
    if ($Plan.InstallUpdates) {
        $ok = Confirm-GoldenImageInternet -VMName      $Plan.TempVMName `
                                          -Credential  $cred `
                                          -IP          $Plan.TempVMIP `
                                          -Gateway     $Plan.TempGateway `
                                          -PrefixLength $Plan.TempVMIPPrefix
        if (-not $ok) {
            Write-LabLog 'No internet access - falling back to unpatched build.' -Level Warn
            _Switch-PlanToUnpatched -Plan $Plan
        }
    }
}

# Private-to-file helper. Flips the plan to unpatched, renaming the in-progress
# VHDX on disk. If an unpatched image already exists for today, throws with a
# distinct message so the orchestrator can clean up the in-progress VM.
function _Switch-PlanToUnpatched {
    param([pscustomobject]$Plan)

    if ($Plan.PatchSuffix -eq '-unpatched') { return }

    $unpatchedName = "$($Plan.OSEntry.GoldenPrefix)-$((Get-Date).ToString('yyyy.MM.dd'))-unpatched"
    $unpatchedPath = Join-Path $Plan.ImageStorePath "${unpatchedName}.vhdx"

    if (Test-Path $unpatchedPath) {
        throw "Unpatched image already exists for today (${unpatchedName}.vhdx) and no internet is available. Nothing new to build."
    }

    $old = $Plan.VHDXPath
    $Plan.PatchSuffix    = '-unpatched'
    $Plan.ImageName      = $unpatchedName
    $Plan.VHDXPath       = $unpatchedPath
    $Plan.InstallUpdates = $false

    if ($old -ne $unpatchedPath) {
        Rename-Item -Path $old -NewName "${unpatchedName}.vhdx" -ErrorAction Stop
        Write-LabLog "Continuing as unpatched build: ${unpatchedName}.vhdx" -Level Warn
    }
}
