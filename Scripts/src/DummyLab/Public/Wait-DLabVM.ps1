# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Wait-DLabVM {
    <#
    .SYNOPSIS
        Waits for a Dummy.Lab VM to be ready for PowerShell Direct connections.
    .DESCRIPTION
        Thin wrapper around the legacy Wait-LabVMReady function. Polls until a
        PowerShell Direct session can be opened with the given credentials,
        returns true when ready, false on timeout. Emits events on attempt
        start, success, and timeout.
    .PARAMETER Name
        Full Hyper-V VM name. Accepts pipeline input.
    .PARAMETER Credential
        Primary credential to test with. Typically local admin.
    .PARAMETER AlternateCredential
        Fallback credential. Useful after domain join when local admin may
        have stopped working.
    .PARAMETER TimeoutMinutes
        Maximum wait time. Default 15.
    .PARAMETER PollIntervalSeconds
        Seconds between attempts. Default 10.
    .PARAMETER PassThru
        Emit a DLab.VM object if the wait succeeded (nothing on timeout).
    .EXAMPLE
        $cred = Get-Credential Administrator
        Wait-DLabVM -Name PipeTest-SRV01 -Credential $cred
    .EXAMPLE
        Get-DLabVM | Start-DLabVM -PassThru | Wait-DLabVM -Credential $cred -PassThru
    .NOTES
        Follows the Wait-Process convention: silent on success, emits a
        non-terminating error on timeout. Use -PassThru to emit a DLab.VM
        object on success. Wrap in try/catch with -ErrorAction Stop if you
        need the timeout to terminate a pipeline.
    #>
    [CmdletBinding()]
    [OutputType('DLab.VM')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('VMName')]
        [string]$Name,

        [Parameter(Mandatory)]
        [PSCredential]$Credential,

        [PSCredential]$AlternateCredential,

        [int]$TimeoutMinutes      = 15,
        [int]$PollIntervalSeconds = 10,

        [switch]$PassThru
    )

    process {
        Write-DLabEvent -Level Step -Source 'Wait-DLabVM' `
            -Message "Waiting for $Name (timeout ${TimeoutMinutes}m)" `
            -Data @{ VMName = $Name; TimeoutMinutes = $TimeoutMinutes }

        $ready = Wait-LabVMReady -VMName $Name `
                                 -Credential $Credential `
                                 -AlternateCredential $AlternateCredential `
                                 -TimeoutMinutes $TimeoutMinutes `
                                 -PollIntervalSeconds $PollIntervalSeconds

        if ($ready) {
            Write-DLabEvent -Level Ok -Source 'Wait-DLabVM' `
                -Message "$Name is ready" `
                -Data @{ VMName = $Name }
            if ($PassThru) { Get-DLabVM -VMName $Name }
        } else {
            Write-DLabEvent -Level Warn -Source 'Wait-DLabVM' `
                -Message "$Name did not become ready within ${TimeoutMinutes}m" `
                -Data @{ VMName = $Name; TimeoutMinutes = $TimeoutMinutes }
            Write-Error "Timed out waiting for '$Name' after $TimeoutMinutes minute(s)."
        }
    }
}
