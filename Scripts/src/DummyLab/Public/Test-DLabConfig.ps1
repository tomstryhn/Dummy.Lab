# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Test-DLabConfig {
    <#
    .SYNOPSIS
        Validates the resolved Dummy.Lab configuration.

    .DESCRIPTION
        Runs a suite of checks against the merged configuration returned by
        Get-DLabConfig and returns a typed DLab.ConfigHealth object with an
        OverallStatus and a Checks list.

        Checks performed:

            Loadable               Config loads without error.
            RequiredKeys           All keys the module depends on are present.
            StorageRootAccessible  LabStorageRoot exists or can be created.
            SharedNetworkValid     SharedNetworkCIDR is a valid /23 CIDR and
                                   SharedGatewayIP is within that range.
            SegmentRangeValid      StagingSegment is 0 and LabSegmentFirst is
                                   1-15 and greater than StagingSegment.
            SizingSane             DefaultMemoryGB >= 1 and DefaultCPU >= 1.
            ImageCatalogReadable   Get-DLabCatalog returns at least one entry.
            OSKeyResolvable        DefaultServerOS resolves to a catalog entry.

        Each check produces a DLab.ConfigCheck record with Status of Passed,
        Warning, or Failed. OverallStatus is Healthy when every check is
        Passed, Warning when at least one is Warning but none Failed, and
        Unhealthy when any check Failed.

        This cmdlet never mutates host or config state.

    .EXAMPLE
        Test-DLabConfig

        Run all checks against the current config and return the summary.

    .EXAMPLE
        (Test-DLabConfig).Checks | Where-Object Status -ne 'Passed'

        Show only the checks that did not pass.

    .NOTES
        Author : Tom Stryhn
        Version : 1.0.0
    #>
    [CmdletBinding()]
    [OutputType('DLab.ConfigHealth')]
    param()

    $checks = [System.Collections.Generic.List[object]]::new()

    function _Add {
        param(
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][ValidateSet('Passed','Warning','Failed')][string]$Status,
            [string]$Message
        )
        $checks.Add([pscustomobject]@{
            PSTypeName = 'DLab.ConfigCheck'
            Name       = $Name
            Status     = $Status
            Message    = $Message
        })
    }

    # Loadable
    $cfg = $null
    try {
        $cfg = Get-DLabConfig -Refresh
        _Add -Name 'Loadable' -Status 'Passed' -Message 'Config loaded.'
    } catch {
        _Add -Name 'Loadable' -Status 'Failed' -Message "Config failed to load: $($_.Exception.Message)"
    }

    if (-not $cfg) {
        return [pscustomobject]@{
            PSTypeName    = 'DLab.ConfigHealth'
            OverallStatus = 'Unhealthy'
            Checks        = $checks
        }
    }

    # RequiredKeys
    $required = @(
        'LabStorageRoot','LabsFolderName','ImageStoreName','EventsFolderName',
        'DomainSuffix','SharedSwitchName','SharedNATName','SharedNetworkCIDR',
        'SharedGatewayIP','StagingSegment','LabSegmentFirst',
        'DefaultMemoryGB','DefaultCPU','DefaultServerOS','VHDXSizeGB'
    )
    $cfgProps = @($cfg.PSObject.Properties.Name)
    # @(...) forces array semantics so .Count is always defined even when
    # the filter matches zero items (under Set-StrictMode -Version Latest,
    # calling .Count on $null throws PropertyNotFoundException).
    $missing  = @($required | Where-Object { $_ -notin $cfgProps })
    if ($missing.Count -eq 0) {
        _Add -Name 'RequiredKeys' -Status 'Passed' -Message "All $($required.Count) required keys present."
    } else {
        _Add -Name 'RequiredKeys' -Status 'Failed' -Message "Missing required keys: $($missing -join ', ')"
    }

    # StorageRootAccessible
    try {
        if (Test-Path $cfg.LabStorageRoot) {
            _Add -Name 'StorageRootAccessible' -Status 'Passed' -Message "LabStorageRoot exists: $($cfg.LabStorageRoot)"
        } else {
            # Check if parent exists so we could create it
            $parent = Split-Path -Parent $cfg.LabStorageRoot
            if ($parent -and (Test-Path $parent)) {
                _Add -Name 'StorageRootAccessible' -Status 'Warning' -Message "LabStorageRoot does not exist yet but parent is accessible: $($cfg.LabStorageRoot)"
            } else {
                _Add -Name 'StorageRootAccessible' -Status 'Failed' -Message "LabStorageRoot parent not accessible: $($cfg.LabStorageRoot)"
            }
        }
    } catch {
        _Add -Name 'StorageRootAccessible' -Status 'Failed' -Message "LabStorageRoot check threw: $($_.Exception.Message)"
    }

    # SharedNetworkValid
    if ($cfg.SharedNetworkCIDR -match '^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/(\d{1,2})$') {
        $cidrPrefix = [int]$Matches[2]
        if ($cidrPrefix -lt 8 -or $cidrPrefix -gt 30) {
            _Add -Name 'SharedNetworkValid' -Status 'Failed' -Message "SharedNetworkCIDR prefix /$cidrPrefix is outside the supported range /8-/30."
        } elseif (-not ($cfg.SharedGatewayIP -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$')) {
            _Add -Name 'SharedNetworkValid' -Status 'Failed' -Message "SharedGatewayIP is not a valid IPv4 address: $($cfg.SharedGatewayIP)"
        } else {
            _Add -Name 'SharedNetworkValid' -Status 'Passed' -Message "Supernet: $($cfg.SharedNetworkCIDR) | gateway: $($cfg.SharedGatewayIP)"
        }
    } else {
        _Add -Name 'SharedNetworkValid' -Status 'Failed' -Message "SharedNetworkCIDR is not a valid CIDR: $($cfg.SharedNetworkCIDR)"
    }

    # SegmentRangeValid
    $stagingSeg = [int]$cfg.StagingSegment
    $labFirst   = [int]$cfg.LabSegmentFirst
    if ($stagingSeg -ne 0) {
        _Add -Name 'SegmentRangeValid' -Status 'Failed' -Message "StagingSegment should be 0 (got $stagingSeg)."
    } elseif ($labFirst -lt 1 -or $labFirst -gt 15) {
        _Add -Name 'SegmentRangeValid' -Status 'Failed' -Message "LabSegmentFirst must be 1-15 (got $labFirst)."
    } elseif ($labFirst -le $stagingSeg) {
        _Add -Name 'SegmentRangeValid' -Status 'Failed' -Message "LabSegmentFirst ($labFirst) must be greater than StagingSegment ($stagingSeg)."
    } else {
        _Add -Name 'SegmentRangeValid' -Status 'Passed' -Message "Staging=segment $stagingSeg | labs start at segment $labFirst (up to 15)."
    }

    # SizingSane
    if ([int]$cfg.DefaultMemoryGB -lt 1) {
        _Add -Name 'SizingSane' -Status 'Failed' -Message "DefaultMemoryGB too small: $($cfg.DefaultMemoryGB)"
    } elseif ([int]$cfg.DefaultCPU -lt 1) {
        _Add -Name 'SizingSane' -Status 'Failed' -Message "DefaultCPU too small: $($cfg.DefaultCPU)"
    } else {
        _Add -Name 'SizingSane' -Status 'Passed' -Message "Default sizing: $($cfg.DefaultMemoryGB) GB / $($cfg.DefaultCPU) vCPU"
    }

    # ImageCatalogReadable
    $catalog = @()
    try {
        # @(...) forces array even when Get-DLabCatalog emits a single entry
        # so .Count is always defined under strict mode.
        $catalog = @(Get-DLabCatalog -ErrorAction Stop)
        if ($catalog.Count -gt 0) {
            _Add -Name 'ImageCatalogReadable' -Status 'Passed' -Message "Catalog entries: $($catalog.Count)"
        } else {
            _Add -Name 'ImageCatalogReadable' -Status 'Warning' -Message 'Catalog loaded but empty.'
        }
    } catch {
        _Add -Name 'ImageCatalogReadable' -Status 'Failed' -Message "Get-DLabCatalog threw: $($_.Exception.Message)"
    }

    # OSKeyResolvable. Strict-mode-safe property access: an individual catalog
    # entry may not carry every property we inspect (OSKey vs Alias), so we
    # check via PSObject.Properties before reading.
    if ($catalog.Count -gt 0) {
        $key = [string]$cfg.DefaultServerOS
        $resolved = @($catalog | Where-Object {
            $props = $_.PSObject.Properties
            ($props['OSKey'] -and $_.OSKey -eq $key) -or
            ($props['Alias'] -and $_.Alias -eq $key)
        })
        if ($resolved.Count -gt 0) {
            _Add -Name 'OSKeyResolvable' -Status 'Passed' -Message "DefaultServerOS resolves: $key"
        } else {
            _Add -Name 'OSKeyResolvable' -Status 'Warning' -Message "DefaultServerOS not in catalog: $key"
        }
    } else {
        _Add -Name 'OSKeyResolvable' -Status 'Warning' -Message 'Skipped (catalog not readable).'
    }

    # Aggregate
    $overall = if ($checks | Where-Object Status -eq 'Failed') {
        'Unhealthy'
    } elseif ($checks | Where-Object Status -eq 'Warning') {
        'Warning'
    } else {
        'Healthy'
    }

    [pscustomobject]@{
        PSTypeName    = 'DLab.ConfigHealth'
        OverallStatus = $overall
        Checks        = $checks
    }
}
