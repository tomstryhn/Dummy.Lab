# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Test-AdminElevation {
    <#
    .SYNOPSIS
        Verifies the current process is running as Administrator.
    #>
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    $isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    New-ValidationResult -Check 'AdminElevation' `
        -Passed $isAdmin `
        -Message $(if ($isAdmin) { 'Running as Administrator.' } else { 'NOT running as Administrator. Re-launch PowerShell as Administrator.' })
}
