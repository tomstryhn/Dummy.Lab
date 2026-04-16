# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Get-Free27Segment {
    <#
    .SYNOPSIS
        Returns the next unallocated /27 segment index for a new lab.
    .DESCRIPTION
        Reads all lab.state.json files to find which segments are already
        claimed, then returns the lowest free index >= LabSegmentFirst (1).
        Segment 0 is always reserved for staging (golden-image builds).

        Three sources are consulted to detect claimed segments:
          1. Lab state files (state.Network.Segment field).
          2. Host NetIPAddress bindings on vEthernet (DLab-Internal) - catches
             orphan IPs left by a partially cleaned-up lab.
          3. The segments argument, for callers that want to reserve a segment
             before writing a state file (avoids race conditions).

        Returns $null if all 15 lab segments (1-15) are taken.
    .PARAMETER LabsRoot
        Path to the Labs folder (e.g. C:\Dummy.Lab\Labs).
    .PARAMETER ExcludeSegments
        Additional segment indices to treat as taken (e.g. being created now).
    .OUTPUTS
        int, or $null if no segment is available.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)][string]$LabsRoot,
        [int[]]$ExcludeSegments = @()
    )

    $taken = [System.Collections.Generic.HashSet[int]]::new()

    # Segment 0 always reserved for staging.
    [void]$taken.Add(0)

    foreach ($seg in $ExcludeSegments) {
        [void]$taken.Add($seg)
    }

    # Source 1: lab state files
    if (Test-Path $LabsRoot) {
        $stateFiles = Get-ChildItem -Path $LabsRoot -Filter 'lab.state.json' -Recurse -ErrorAction SilentlyContinue
        foreach ($sf in $stateFiles) {
            try {
                $s = Get-Content $sf.FullName -Raw | ConvertFrom-Json
                if ($s.PSObject.Properties['Network'] -and
                    $s.Network -and
                    $s.Network.PSObject.Properties['Segment']) {
                    $seg = [int]$s.Network.Segment
                    [void]$taken.Add($seg)
                }
            } catch { }
        }
    }

    # Source 2: host IP bindings on the shared vEthernet adapter (orphan detection)
    # The host adapter sits at 10.74.18.1/23 covering the whole supernet.
    # Guest IPs on the adapter would only appear for vEthernet sub-interfaces,
    # but we also check NetIPAddress for completeness (handles unusual residuals).
    $adapterName = 'vEthernet (DLab-Internal)'
    $guestIPs = Get-NetIPAddress -InterfaceAlias $adapterName -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.IPAddress -ne '10.74.18.1' -and $_.IPAddress -notmatch '^169\.' }
    foreach ($ip in $guestIPs) {
        # Determine which /27 segment this IP belongs to.
        # 10.74.18.0/23 base as int = (10<<24)|(74<<16)|(18<<8)|0
        $baseInt = (10 * 16777216) + (74 * 65536) + (18 * 256)
        $parts = $ip.IPAddress -split '\.'
        if ($parts.Count -eq 4) {
            $ipInt = ([int]$parts[0] * 16777216) + ([int]$parts[1] * 65536) + ([int]$parts[2] * 256) + [int]$parts[3]
            $offset = $ipInt - $baseInt
            if ($offset -ge 0 -and $offset -le 511) {
                [void]$taken.Add([math]::Floor($offset / 32))
            }
        }
    }

    # Return the first free segment in range 1-15
    for ($i = 1; $i -le 15; $i++) {
        if (-not $taken.Contains($i)) {
            return $i
        }
    }

    return $null
}
