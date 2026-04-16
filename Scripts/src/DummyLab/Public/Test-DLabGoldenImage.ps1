# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Test-DLabGoldenImage {
    <#
    .SYNOPSIS
        Validates a golden image VHDX.
    .DESCRIPTION
        Runs a battery of cheap checks against a golden image:
          - File exists and is readable
          - Parses as a valid VHDX (Get-VHD)
          - Has no broken parent chain (differencing disks are not valid
            golden images; they must be standalone)
          - Protection status (read-only + deny-delete ACE)

        Emits a DLab.HealthStatus per image for consistency with future
        Test-DLab output. Does not modify state.

        Live-off-the-land: wraps Get-VHD and Get-Acl rather than
        re-implementing VHDX parsing.
    .PARAMETER Path
        Full path to the golden image VHDX. Accepts pipeline input.
    .EXAMPLE
        Test-DLabGoldenImage -Path C:\Dummy.Lab\GoldenImages\WS2025-DC-2026.04.14-unpatched.vhdx
    .EXAMPLE
        Get-DLabGoldenImage | Test-DLabGoldenImage | Where-Object OverallStatus -ne 'Healthy'
    #>
    [CmdletBinding()]
    [OutputType('DLab.HealthStatus')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('ImagePath', 'FullName')]
        [string]$Path
    )

    process {
        $imageName = Split-Path $Path -Leaf
        $checks = @()

        # Check 1: file exists
        $exists = Test-Path $Path
        $checks += [PSCustomObject]@{
            PSTypeName = 'DLab.HealthCheck'
            Name       = 'File exists'
            Status     = if ($exists) { 'Healthy' } else { 'Unhealthy' }
            Message    = if ($exists) { $Path } else { "Not found: $Path" }
        }
        if (-not $exists) {
            [PSCustomObject]@{
                PSTypeName    = 'DLab.HealthStatus'
                Target        = $imageName
                Timestamp     = Get-Date
                OverallStatus = 'Unhealthy'
                Checks        = $checks
            }
            return
        }

        # Check 2: parses as VHDX
        $vhdOk    = $false
        $vhdError = ''
        $vhdInfo  = $null
        try {
            $vhdInfo = Get-VHD -Path $Path -ErrorAction Stop
            $vhdOk = $true
        } catch {
            $vhdError = $_.Exception.Message
        }
        $checks += [PSCustomObject]@{
            PSTypeName = 'DLab.HealthCheck'
            Name       = 'VHDX parses'
            Status     = if ($vhdOk) { 'Healthy' } else { 'Unhealthy' }
            Message    = if ($vhdOk) { "Format: $($vhdInfo.VhdFormat), type: $($vhdInfo.VhdType)" } else { $vhdError }
        }

        # Check 3: standalone (not a differencing disk)
        if ($vhdOk) {
            $isStandalone = (-not $vhdInfo.ParentPath)
            $checks += [PSCustomObject]@{
                PSTypeName = 'DLab.HealthCheck'
                Name       = 'Standalone (no parent)'
                Status     = if ($isStandalone) { 'Healthy' } else { 'Unhealthy' }
                Message    = if ($isStandalone) { 'No parent VHDX' } else { "Has parent: $($vhdInfo.ParentPath)" }
            }
        }

        # Check 4: protection
        $file = Get-Item $Path
        $readOnly = $file.IsReadOnly
        $denyAce  = $false
        try {
            $acl = Get-Acl $Path
            $denyAce = [bool]($acl.Access | Where-Object {
                $_.AccessControlType -eq 'Deny' -and
                ($_.FileSystemRights.ToString() -match 'Delete')
            })
        } catch { }
        $protected = $readOnly -and $denyAce
        $checks += [PSCustomObject]@{
            PSTypeName = 'DLab.HealthCheck'
            Name       = 'Protected (read-only + deny-delete)'
            Status     = if ($protected) { 'Healthy' } else { 'Degraded' }
            Message    = "ReadOnly=$readOnly DenyDeleteACE=$denyAce"
        }

        # Overall roll-up
        $overall = 'Healthy'
        if ($checks.Status -contains 'Unhealthy')     { $overall = 'Unhealthy' }
        elseif ($checks.Status -contains 'Degraded')  { $overall = 'Degraded' }

        [PSCustomObject]@{
            PSTypeName    = 'DLab.HealthStatus'
            Target        = $imageName
            Timestamp     = Get-Date
            OverallStatus = $overall
            Checks        = $checks
        }
    }
}
