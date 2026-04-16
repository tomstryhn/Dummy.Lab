# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Test-HyperVAvailable {
    <#
    .SYNOPSIS
        Checks that the Hyper-V PowerShell module is present and the service responds.
    #>
    $hvModule = Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue
    if (-not $hvModule) {
        return New-ValidationResult -Check 'HyperVAvailable' -Passed $false `
            -Message 'Hyper-V PowerShell module not found.' `
            -Detail 'Enable Hyper-V: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All'
    }

    try {
        $null = Get-VMSwitch -ErrorAction Stop
        return New-ValidationResult -Check 'HyperVAvailable' -Passed $true `
            -Message 'Hyper-V module available and service responding.'
    } catch {
        return New-ValidationResult -Check 'HyperVAvailable' -Passed $false `
            -Message 'Hyper-V module found but service not responding.' `
            -Detail $_.Exception.Message
    }
}
