# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Wait-LabVMReady {
    <#
    .SYNOPSIS
        Polls until a VM is ready for PowerShell Direct connections.
    .DESCRIPTION
        Attempts to establish a PowerShell Direct session to the VM using the
        primary credential, then the alternate credential if provided. Returns
        $true when the VM is reachable, $false on timeout.

        Credentials are tested but never returned  - they stay within the function
        scope. Callers use their own credential references for subsequent operations.
    .PARAMETER VMName
        Target VM name.
    .PARAMETER Credential
        Primary PSCredential (tried first).
    .PARAMETER AlternateCredential
        Secondary PSCredential (tried if primary fails, e.g. domain cred after join).
    .PARAMETER TimeoutMinutes
        How long to wait before giving up. Default: 15 minutes.
    .PARAMETER PollIntervalSeconds
        Seconds between attempts. Default: 10.
    .OUTPUTS
        [bool] $true if VM became ready, $false on timeout.
    #>
    param(
        [string]$VMName,
        [PSCredential]$Credential,
        [PSCredential]$AlternateCredential = $null,
        [int]$TimeoutMinutes      = 15,
        [int]$PollIntervalSeconds = 10
    )

    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $attempt  = 0

    Write-Host "  [~] Waiting for '$VMName'..." -ForegroundColor Cyan

    while ((Get-Date) -lt $deadline) {
        $attempt++

        # Try primary credential
        try {
            $session = New-PSSession -VMName $VMName -Credential $Credential -ErrorAction Stop
            Remove-PSSession $session
            Write-Host "  [+] '$VMName' ready. (attempt $attempt)" -ForegroundColor Green
            return $true
        } catch { }

        # Try alternate credential (domain cred after join)
        if ($AlternateCredential) {
            try {
                $session = New-PSSession -VMName $VMName -Credential $AlternateCredential -ErrorAction Stop
                Remove-PSSession $session
                Write-Host "  [+] '$VMName' ready with alternate credential. (attempt $attempt)" -ForegroundColor Green
                return $true
            } catch { }
        }

        Start-Sleep -Seconds $PollIntervalSeconds
    }

    Write-Host "  [X] Timeout waiting for '$VMName' after $TimeoutMinutes minutes." -ForegroundColor Red
    return $false
}
