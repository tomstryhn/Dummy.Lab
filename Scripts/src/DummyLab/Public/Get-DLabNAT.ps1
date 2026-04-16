# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Get-DLabNAT {
    <#
    .SYNOPSIS
        Returns the host NAT configuration for a lab (or all DLab-managed NATs).

    .DESCRIPTION
        Reads the NetNat objects currently present on the host and projects each
        into a typed DLab.NAT object that callers can compare to what
        Set-DLabNAT would produce. Useful for operators who need to answer
        "is NAT configured for this lab, and what subnet is it translating?"
        without hand-parsing Get-NetNat output.

        Without parameters, returns every NetNat on the host. With -LabName,
        filters by the lab's NAT naming convention (<LabName>-NAT). With -Name,
        returns only the named NAT.

        This cmdlet is read-only; it never mutates host state.

    .PARAMETER LabName
        Lab name. The NAT is looked up by the convention "<LabName>-NAT".

    .PARAMETER Name
        Exact NAT name. Mutually exclusive with -LabName.

    .EXAMPLE
        Get-DLabNAT

        Lists every NetNat on the host as DLab.NAT objects.

    .EXAMPLE
        Get-DLabNAT -LabName Demo

        Returns the NAT for lab "Demo", or nothing if no NAT is configured.

    .EXAMPLE
        Get-DLabNAT -Name Pipeline-NAT

        Returns the specific named NAT.

    .NOTES
        Author : Tom Stryhn
        Version : 1.0.0
    #>
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [OutputType('DLab.NAT')]
    param(
        [Parameter(ParameterSetName = 'ByLab', Mandatory, Position = 0)]
        [string]$LabName,

        [Parameter(ParameterSetName = 'ByName', Mandatory, Position = 0)]
        [string]$Name
    )

    process {
        $filter = switch ($PSCmdlet.ParameterSetName) {
            'ByLab'  { "$LabName-NAT" }
            'ByName' { $Name }
            default  { $null }
        }

        $nats = if ($filter) {
            Get-NetNat -Name $filter -ErrorAction SilentlyContinue
        } else {
            Get-NetNat -ErrorAction SilentlyContinue
        }

        if (-not $nats) {
            return
        }

        foreach ($nat in $nats) {
            [pscustomobject]@{
                PSTypeName                       = 'DLab.NAT'
                Name                             = $nat.Name
                InternalIPInterfaceAddressPrefix = $nat.InternalIPInterfaceAddressPrefix
                ExternalIPInterfaceAddressPrefix = $nat.ExternalIPInterfaceAddressPrefix
                Active                           = $nat.Active
                LabName                          = if ($nat.Name -match '^(?<lab>.+)-NAT$') { $matches['lab'] } else { $null }
            }
        }
    }
}
