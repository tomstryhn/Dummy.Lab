# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Test-VMNameConflict {
    <#
    .SYNOPSIS
        Checks whether any planned VM names already exist in Hyper-V.
    .PARAMETER VMNames
        Array of VM names to check.
    #>
    param([string[]]$VMNames)

    $conflicts = @()
    foreach ($name in $VMNames) {
        if (Get-VM -Name $name -ErrorAction SilentlyContinue) {
            $conflicts += $name
        }
    }

    if ($conflicts.Count -gt 0) {
        return New-ValidationResult -Check 'VMNameConflict' -Passed $false `
            -Message "VM name conflict(s): $($conflicts -join ', ')" `
            -Detail 'Remove or rename existing VMs, or use a different -LabName.'
    }

    New-ValidationResult -Check 'VMNameConflict' -Passed $true `
        -Message "VM names available: $($VMNames -join ', ')"
}
