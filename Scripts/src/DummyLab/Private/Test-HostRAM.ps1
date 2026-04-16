# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Test-HostRAM {
    <#
    .SYNOPSIS
        Warns if host RAM is below the recommended minimum. Never hard-fails.
    .PARAMETER RequiredGB
        Minimum RAM in GB. Default: 16.
    #>
    param([int]$RequiredGB = 16)

    $totalGB = [math]::Round(
        (Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum / 1GB, 1
    )
    $msg = if ($totalGB -ge $RequiredGB) {
        "Host RAM: ${totalGB} GB - OK."
    } else {
        "Host RAM: ${totalGB} GB - below recommended ${RequiredGB} GB. VMs may swap heavily."
    }

    New-ValidationResult -Check 'HostRAM' -Passed $true -Message $msg -Detail "Detected: ${totalGB} GB"
}
