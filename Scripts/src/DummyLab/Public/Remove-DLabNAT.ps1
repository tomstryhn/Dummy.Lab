# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Remove-DLabNAT {
    <#
    .SYNOPSIS
        Removes a host NAT configuration.
    .DESCRIPTION
        Deletes a NetNat object by name. Idempotent: if the NAT does not exist,
        the cmdlet reports that and succeeds.

        Supports -WhatIf for a dry run. Emits Write-DLabEvent. Silent by default.
    .PARAMETER Name
        NAT name to remove (e.g., 'Pipeline-NAT'). Accepts pipeline input
        from Get-DLabNAT by value or by the 'Name' property.
    .EXAMPLE
        Remove-DLabNAT -Name 'Pipeline-NAT'
    .EXAMPLE
        Remove-DLabNAT -Name 'Pipeline-NAT' -WhatIf
    .EXAMPLE
        # Pipeline composition: remove every DLab NAT that matches a lab prefix
        Get-DLabNAT | Where-Object LabName -like 'Test-*' | Remove-DLabNAT -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name
    )

    process {
        $nat = Get-NetNat -Name $Name -ErrorAction SilentlyContinue

        if (-not $nat) {
            Write-DLabEvent -Level Info -Source 'Remove-DLabNAT' `
                -Message "NAT not found: $Name (nothing to remove)" `
                -Data @{ NATName = $Name }
            return
        }

        if (-not $PSCmdlet.ShouldProcess($Name, 'Remove NAT')) { return }

        try {
            Write-DLabEvent -Level Step -Source 'Remove-DLabNAT' `
                -Message "Removing NAT: $Name" `
                -Data @{ NATName = $Name }

            Remove-NetNat -Name $Name -Confirm:$false -ErrorAction Stop | Out-Null

            Write-DLabEvent -Level Ok -Source 'Remove-DLabNAT' `
                -Message "NAT removed: $Name" `
                -Data @{ NATName = $Name }
        } catch {
            Write-DLabEvent -Level Error -Source 'Remove-DLabNAT' `
                -Message "Failed to remove NAT: $($_.Exception.Message)" `
                -Data @{ NATName = $Name; Error = $_.Exception.Message }
            throw
        }
    }
}
