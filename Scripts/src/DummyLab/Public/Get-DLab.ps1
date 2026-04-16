# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Get-DLab {
    <#
    .SYNOPSIS
        Lists Dummy.Lab labs.
    .DESCRIPTION
        Reads lab.state.json files under <LabStorageRoot>/Labs and returns a
        DLab.Lab object per lab, with its Network and VMs populated by cross-
        referencing live Hyper-V state.

        Live-off-the-land: Get-VM and Get-VMSwitch/Get-NetNat are the source of
        truth for runtime state. The state file is the source of truth for lab
        membership and intent.
    .PARAMETER Name
        Filter to a specific lab name (supports wildcards).
    .EXAMPLE
        Get-DLab
    .EXAMPLE
        Get-DLab -Name PipeTest
    .EXAMPLE
        Get-DLab | Where-Object Status -ne 'Healthy'
    #>
    [CmdletBinding()]
    [OutputType('DLab.Lab')]
    param(
        [Parameter(Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('LabName')]
        [string]$Name = '*'
    )

    process {
        $labsRoot = Get-DLabStorePath -Kind Labs
        if (-not (Test-Path $labsRoot)) {
            Write-Verbose "Labs root not present: $labsRoot"
            return
        }

        $stateFiles = Get-ChildItem -Path $labsRoot -Filter 'lab.state.json' -Recurse -ErrorAction SilentlyContinue
        foreach ($sf in $stateFiles) {
            $labName = $sf.Directory.Name
            if ($Name -and $labName -notlike $Name) { continue }

            try {
                $state = Get-Content $sf.FullName -Raw | ConvertFrom-Json
            } catch {
                # Durable log of state corruption so post-mortem (Get-DLabEventLog)
                # can find it. Write-Warning alone does not reach the JSONL log.
                Write-DLabEvent -Level Warn -Source 'Get-DLab' `
                    -Message "Corrupt state file skipped: $($sf.FullName)" `
                    -Data @{ StatePath = $sf.FullName; LabName = $labName; Error = $_.Exception.Message }
                Write-Warning "Corrupt state file skipped: $($sf.FullName) - $($_.Exception.Message)"
                continue
            }

            # Cross-reference live VMs
            $vmObjects = @()
            if ($state.PSObject.Properties['VMs'] -and $state.VMs) {
                foreach ($entry in $state.VMs) {
                    $live = Get-VM -Name $entry.Name -ErrorAction SilentlyContinue
                    $vmObjects += New-DLabVMObject -StateEntry $entry -LabName $labName -LiveVM $live
                }
            }

            # Cross-reference live switch/NAT
            $liveSwitch = $null
            $liveNat    = $null
            if ($state.PSObject.Properties['Network'] -and $state.Network.PSObject.Properties['SwitchName']) {
                $liveSwitch = Get-VMSwitch -Name $state.Network.SwitchName -ErrorAction SilentlyContinue
            }
            if ($state.PSObject.Properties['Infrastructure'] -and $state.Infrastructure.PSObject.Properties['NATName'] -and $state.Infrastructure.NATName) {
                $liveNat = Get-NetNat -Name $state.Infrastructure.NATName -ErrorAction SilentlyContinue
            }
            $network = New-DLabNetworkObject -LabName $labName -State $state -LiveSwitch $liveSwitch -LiveNat $liveNat

            # Overall status: quick heuristic. Use Test-DLab for a deep health check.
            $status = 'Healthy'
            if (-not $liveSwitch)                                          { $status = 'Degraded' }
            if ($vmObjects | Where-Object { $_.State -eq 'Missing' })      { $status = 'Degraded' }
            if ($vmObjects | Where-Object { $_.Status -eq 'Failed' })      { $status = 'Degraded' }

            New-DLabLabObject -LabName $labName -State $state -StatePath $sf.FullName `
                              -VMs $vmObjects -Network $network -Status $status
        }
    }
}
