# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Send-GuestScript {
    <#
    .SYNOPSIS
        Copies a script file into a VM via PowerShell Direct.
    .PARAMETER VMName
        Target VM.
    .PARAMETER Credential
        VM local admin credentials.
    .PARAMETER LocalPath
        Path to the script on the HOST.
    .PARAMETER GuestDestination
        Target folder inside the VM. Default: C:\LabScripts
    #>
    param(
        [string]$VMName,
        [PSCredential]$Credential,
        [string]$LocalPath,
        [string]$GuestDestination = 'C:\LabScripts'
    )

    $session = New-PSSession -VMName $VMName -Credential $Credential -ErrorAction Stop
    try {
        Invoke-Command -Session $session -ScriptBlock {
            param($dest)
            if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
        } -ArgumentList $GuestDestination

        $fileName = Split-Path $LocalPath -Leaf
        Write-Host "  [>] Copying '$fileName' to '${VMName}:${GuestDestination}'..." -ForegroundColor Cyan
        Copy-Item -Path $LocalPath -Destination $GuestDestination -ToSession $session -Force -ErrorAction Stop
        Write-Host "      Done." -ForegroundColor Green
    } finally {
        Remove-PSSession $session -ErrorAction SilentlyContinue
    }
}
