# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Start-LabVM {
    <#
    .SYNOPSIS
        Starts a lab VM if it is not already running.
    #>
    param([string]$VMName)

    $vm = Get-VM -Name $VMName -ErrorAction Stop
    if ($vm.State -eq 'Running') {
        Write-Host "  [~] '$VMName' already running." -ForegroundColor DarkGray
        return
    }
    Write-Host "  [>] Starting '$VMName'..." -ForegroundColor Cyan
    Start-VM -Name $VMName -ErrorAction Stop
    Write-Host "      Started." -ForegroundColor Green
}
