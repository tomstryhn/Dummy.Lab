# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Update-LabStateLocked {
    <#
    .SYNOPSIS
        Atomically reads, updates, and writes the lab state with a file lock.
        Prevents race conditions when running parallel -Add deployments.
    .PARAMETER Path
        Path to lab.state.json.
    .PARAMETER UpdateScript
        ScriptBlock that receives the state object and returns the modified state.
    .OUTPUTS
        The updated state object.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][scriptblock]$UpdateScript
    )

    $lockFile = "$Path.lock"
    $lockAcquired = $false
    $maxWait = 30  # seconds

    try {
        # Acquire lock (spin-wait)
        $deadline = (Get-Date).AddSeconds($maxWait)
        while ((Get-Date) -lt $deadline) {
            try {
                $lock = [System.IO.File]::Open($lockFile, [System.IO.FileMode]::CreateNew,
                            [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                $lockAcquired = $true
                break
            } catch {
                Start-Sleep -Milliseconds 200
            }
        }
        if (-not $lockAcquired) {
            throw "Could not acquire state lock after ${maxWait}s. Another deployment may be running, or a stale lock file exists at: $lockFile`nTo recover from a stale lock, delete the .lock file and retry."
        }

        # Read, update, write
        $state = Read-LabState -Path $Path
        $state = & $UpdateScript $state
        Write-LabState -State $state -Path $Path
        return $state

    } finally {
        if ($lock) { $lock.Close() }
        Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
    }
}
