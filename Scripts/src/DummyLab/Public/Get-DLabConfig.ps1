# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Get-DLabConfig {
    <#
    .SYNOPSIS
        Returns the merged Dummy.Lab configuration.
    .DESCRIPTION
        Merges bundled defaults with user overrides (%APPDATA%\DummyLab\config.psd1)
        and environment overrides ($env:DUMMYLAB_CONFIG). Cached after first call.
    .PARAMETER Refresh
        Force a reload from disk, bypassing the cache.
    .EXAMPLE
        Get-DLabConfig
    .EXAMPLE
        (Get-DLabConfig).DomainSuffix
    #>
    [CmdletBinding()]
    param(
        [switch]$Refresh
    )
    $cfg = Get-DLabConfigInternal -Refresh:$Refresh
    # Return a shallow copy as PSCustomObject so the cache cannot be mutated
    # by callers, and so format views can target a proper type name.
    $obj = [PSCustomObject]@{ PSTypeName = 'DLab.Config' }
    foreach ($k in $cfg.Keys) { $obj | Add-Member -NotePropertyName $k -NotePropertyValue $cfg[$k] }
    return $obj
}
