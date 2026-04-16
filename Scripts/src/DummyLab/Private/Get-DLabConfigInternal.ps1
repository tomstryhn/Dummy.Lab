# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

#
# Loads and caches the merged configuration. Precedence (highest wins):
#   1. $env:DUMMYLAB_CONFIG (full path to a .psd1)
#   2. %APPDATA%\DummyLab\config.psd1
#   3. Bundled DLab.Defaults.psd1 (module source)
#
# Cached in module scope after first call. Call with -Refresh to reload.

$script:DLabConfigCache = $null

function Get-DLabConfigInternal {
    [CmdletBinding()]
    param(
        [switch]$Refresh
    )

    if (-not $Refresh -and $script:DLabConfigCache) {
        return $script:DLabConfigCache
    }

    # Bundled defaults. Assembled module: psm1 + DLab.Defaults.psd1 share a folder,
    # so $PSScriptRoot inside any function resolves to that folder.
    # Source tree (dev loading): function file lives in Private\, defaults live
    # one level up in Config\, so $PSScriptRoot\..\Config\ catches it.
    $candidates = @(
        (Join-Path $PSScriptRoot 'DLab.Defaults.psd1'),
        (Join-Path $PSScriptRoot '..\Config\DLab.Defaults.psd1'),
        (Join-Path $PSScriptRoot '..\DLab.Defaults.psd1')
    )
    $defaultsPath = $null
    foreach ($c in $candidates) {
        if (Test-Path $c) { $defaultsPath = (Resolve-Path $c).Path; break }
    }
    if (-not $defaultsPath) {
        throw "DummyLab defaults file not found. Checked: $($candidates -join '; ')"
    }

    $config = Import-PowerShellDataFile -Path $defaultsPath

    # User override: %APPDATA%\DummyLab\config.psd1
    $userOverride = Join-Path $env:APPDATA 'DummyLab\config.psd1'
    if (Test-Path $userOverride) {
        $userConfig = Import-PowerShellDataFile -Path $userOverride
        foreach ($key in $userConfig.Keys) {
            $config[$key] = $userConfig[$key]
        }
    }

    # Environment override
    if ($env:DUMMYLAB_CONFIG -and (Test-Path $env:DUMMYLAB_CONFIG)) {
        $envConfig = Import-PowerShellDataFile -Path $env:DUMMYLAB_CONFIG
        foreach ($key in $envConfig.Keys) {
            $config[$key] = $envConfig[$key]
        }
    }

    $script:DLabConfigCache = $config
    return $config
}
