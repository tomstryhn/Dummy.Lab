# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Test-DLabHost {
    <#
    .SYNOPSIS
        Checks whether the current host meets Dummy.Lab prerequisites.
    .DESCRIPTION
        Runs a battery of host-level checks: administrator elevation, Hyper-V
        availability, minimum RAM. Each check contributes a DLab.HealthCheck
        to a DLab.HealthStatus roll-up. Use before running New-DLab or
        New-DLabGoldenImage on a fresh host.
    .EXAMPLE
        Test-DLabHost | Format-Table Target, OverallStatus
    .EXAMPLE
        (Test-DLabHost).Checks | Format-Table Name, Status, Message -AutoSize
    #>
    [CmdletBinding()]
    [OutputType('DLab.HealthStatus')]
    param()

    $checks = @()

    $adminOk = Test-AdminElevation
    $checks += [PSCustomObject]@{
        PSTypeName = 'DLab.HealthCheck'
        Name       = 'Administrator elevation'
        Status     = if ($adminOk) { 'Healthy' } else { 'Unhealthy' }
        Message    = if ($adminOk) { 'Running elevated' } else { 'Not elevated - required for Hyper-V operations' }
    }

    $hvOk = Test-HyperVAvailable
    $checks += [PSCustomObject]@{
        PSTypeName = 'DLab.HealthCheck'
        Name       = 'Hyper-V available'
        Status     = if ($hvOk) { 'Healthy' } else { 'Unhealthy' }
        Message    = if ($hvOk) { 'Hyper-V module and service OK' } else { 'Hyper-V PowerShell module not found or service not running' }
    }

    $ram = [math]::Round((Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).TotalPhysicalMemory / 1GB, 1)
    $ramStatus = if ($ram -ge 8) { 'Healthy' } elseif ($ram -ge 4) { 'Degraded' } else { 'Unhealthy' }
    $checks += [PSCustomObject]@{
        PSTypeName = 'DLab.HealthCheck'
        Name       = 'Host RAM'
        Status     = $ramStatus
        Message    = "$ram GB (recommended: 8+ GB, minimum: 4 GB)"
    }

    $overall = 'Healthy'
    if ($checks.Status -contains 'Unhealthy')    { $overall = 'Unhealthy' }
    elseif ($checks.Status -contains 'Degraded') { $overall = 'Degraded' }

    [PSCustomObject]@{
        PSTypeName    = 'DLab.HealthStatus'
        Target        = $env:COMPUTERNAME
        Timestamp     = Get-Date
        OverallStatus = $overall
        Checks        = $checks
    }
}
