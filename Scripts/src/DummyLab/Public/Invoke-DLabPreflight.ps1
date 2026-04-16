# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Invoke-DLabPreflight {
    <#
    .SYNOPSIS
        Runs a full preflight check before a lab or image operation.
    .DESCRIPTION
        Host-level checks (Test-DLabHost) plus operation-specific probes:
        disk space, required folders, VM namespace collisions, and shared
        infrastructure readiness (DLab-Internal switch + DLab-NAT).
        Returns a DLab.HealthStatus.
    .PARAMETER LabName
        If provided, also checks for collisions in that lab's VM namespace.
        Unlike New-DLab / Add-DLabVM, this parameter does NOT fall back to
        the configured default LabName: passing no LabName is the explicit
        "host-only preflight" mode.
    .EXAMPLE
        Invoke-DLabPreflight                  # host only
    .EXAMPLE
        Invoke-DLabPreflight -LabName NewProd # host + lab namespace
    #>
    [CmdletBinding()]
    [OutputType('DLab.HealthStatus')]
    param(
        [string]$LabName
    )

    $hostResult = Test-DLabHost
    $checks = @($hostResult.Checks)

    # --- Shared infrastructure checks ---
    $sharedSwitch = Get-VMSwitch -Name 'DLab-Internal' -ErrorAction SilentlyContinue
    $checks += [PSCustomObject]@{
        PSTypeName = 'DLab.HealthCheck'
        Name       = 'Shared switch (DLab-Internal)'
        Status     = if ($sharedSwitch) { 'Healthy' } else { 'Info' }
        Message    = if ($sharedSwitch) { 'Present' } else { 'Not yet created - will be initialised by New-DLab or New-DLabGoldenImage' }
    }

    $sharedNat = Get-NetNat -Name 'DLab-NAT' -ErrorAction SilentlyContinue
    $checks += [PSCustomObject]@{
        PSTypeName = 'DLab.HealthCheck'
        Name       = 'Shared NAT (DLab-NAT)'
        Status     = if ($sharedNat) { 'Healthy' } else { 'Info' }
        Message    = if ($sharedNat) { "Present ($($sharedNat.InternalIPInterfaceAddressPrefix))" } else { 'Not yet created - will be initialised by New-DLab or New-DLabGoldenImage' }
    }

    # --- Lab-specific namespace checks ---
    if ($LabName) {
        $existingVMs = @(Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^$LabName-(DC|SRV)" })
        $checks += [PSCustomObject]@{
            PSTypeName = 'DLab.HealthCheck'
            Name       = "VM namespace ($LabName-*)"
            Status     = if ($existingVMs.Count -eq 0) { 'Healthy' } else { 'Degraded' }
            Message    = if ($existingVMs.Count -gt 0) { "$($existingVMs.Count) existing VM(s) with $LabName- prefix" } else { 'Free' }
        }

        # Check that a /27 segment is available for a new lab
        $labsRoot = Get-DLabStorePath -Kind Labs
        $freeSeg  = Get-Free27Segment -LabsRoot $labsRoot
        $checks += [PSCustomObject]@{
            PSTypeName = 'DLab.HealthCheck'
            Name       = 'Network segment availability'
            Status     = if ($null -ne $freeSeg) { 'Healthy' } else { 'Unhealthy' }
            Message    = if ($null -ne $freeSeg) { "Segment $freeSeg available ($($(Get-27SegmentConfig -Segment $freeSeg).NetworkCIDR))" } else { 'All 15 lab segments (1-15) are in use' }
        }
    }

    $overall = 'Healthy'
    if ($checks.Status -contains 'Unhealthy')    { $overall = 'Unhealthy' }
    elseif ($checks.Status -contains 'Degraded') { $overall = 'Degraded' }

    [PSCustomObject]@{
        PSTypeName    = 'DLab.HealthStatus'
        Target        = if ($LabName) { "Host + Lab '$LabName'" } else { $env:COMPUTERNAME }
        Timestamp     = Get-Date
        OverallStatus = $overall
        Checks        = $checks
    }
}
