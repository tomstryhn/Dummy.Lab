# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Invoke-DLabGuestScript {
    <#
    .SYNOPSIS
        Executes a script inside a Dummy.Lab VM via PowerShell Direct.
    .DESCRIPTION
        Wraps the internal Invoke-GuestScript helper with event instrumentation.
        Exit-code propagation and failure output surfacing are handled by the
        underlying helper.
    .PARAMETER Name
        Full Hyper-V VM name. Accepts pipeline input.
    .PARAMETER Credential
        Credential to open the PowerShell Direct session. Typically local admin
        for freshly-joined guests or domain admin for post-join operations.
    .PARAMETER ScriptPath
        Absolute path to the script inside the VM (after copying in with
        Send-DLabGuestFile).
    .PARAMETER Arguments
        Hashtable of parameter name to value pairs passed to the script.
    .PARAMETER WaitForReboot
        If the script triggers a reboot, wait for the VM to come back with the
        same credentials.
    .PARAMETER ShowOutput
        Stream the guest script's stdout to the host console (in addition to
        surfacing it on non-zero exit codes).
    .EXAMPLE
        Invoke-DLabGuestScript -Name PipeTest-SRV01 -Credential $cred `
            -ScriptPath 'C:\LabScripts\Install-MemberServer.ps1' `
            -Arguments @{ DomainName = 'pipetest.internal' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('VMName')]
        [string]$Name,

        [Parameter(Mandatory)]
        [PSCredential]$Credential,

        [Parameter(Mandatory)]
        [string]$ScriptPath,

        [hashtable]$Arguments = @{},
        [switch]$WaitForReboot,
        [switch]$ShowOutput
    )

    process {
        Write-DLabEvent -Level Step -Source 'Invoke-DLabGuestScript' `
            -Message "Running '$ScriptPath' on $Name" `
            -Data @{ VMName = $Name; ScriptPath = $ScriptPath; ParamCount = $Arguments.Count }

        try {
            Invoke-GuestScript -VMName $Name `
                               -Credential $Credential `
                               -ScriptPath $ScriptPath `
                               -Arguments $Arguments `
                               -WaitForReboot:$WaitForReboot `
                               -ShowOutput:$ShowOutput
            Write-DLabEvent -Level Ok -Source 'Invoke-DLabGuestScript' `
                -Message "Guest script finished on $Name" `
                -Data @{ VMName = $Name; ScriptPath = $ScriptPath }
        } catch {
            Write-DLabEvent -Level Error -Source 'Invoke-DLabGuestScript' `
                -Message "Guest script failed on ${Name}: $($_.Exception.Message)" `
                -Data @{ VMName = $Name; ScriptPath = $ScriptPath; Error = $_.Exception.Message }
            throw
        }
    }
}
