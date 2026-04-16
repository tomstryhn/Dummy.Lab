# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Send-DLabGuestFile {
    <#
    .SYNOPSIS
        Copies a file from the host into a Dummy.Lab VM via PowerShell Direct.
    .DESCRIPTION
        Wraps the legacy Send-GuestScript function. Despite the legacy name
        ending in '-Script', the underlying implementation is a generic file
        copy over a PowerShell Direct session, so this cmdlet exposes it under
        the more accurate '-GuestFile' noun. Any file type works.
    .PARAMETER Name
        Full Hyper-V VM name. Accepts pipeline input.
    .PARAMETER Credential
        Credential to open the PowerShell Direct session.
    .PARAMETER LocalPath
        Host-side path to the file to send.
    .PARAMETER GuestDestination
        Target directory inside the VM. Default: 'C:\LabScripts'.
    .EXAMPLE
        Send-DLabGuestFile -Name PipeTest-SRV01 -Credential $cred `
            -LocalPath 'C:\Dummy.Lab\Scripts\GuestScripts\Install-MemberServer.ps1'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [Alias('VMName')]
        [string]$Name,

        [Parameter(Mandatory)]
        [PSCredential]$Credential,

        [Parameter(Mandatory)]
        [string]$LocalPath,

        [string]$GuestDestination = 'C:\LabScripts'
    )

    process {
        if (-not (Test-Path $LocalPath)) {
            Write-Error "Local file not found: $LocalPath"
            return
        }

        $fileName = Split-Path $LocalPath -Leaf
        Write-DLabEvent -Level Step -Source 'Send-DLabGuestFile' `
            -Message "Copying '$fileName' to ${Name}:${GuestDestination}" `
            -Data @{ VMName = $Name; LocalPath = $LocalPath; GuestDestination = $GuestDestination }

        try {
            Send-GuestScript -VMName $Name `
                             -Credential $Credential `
                             -LocalPath $LocalPath `
                             -GuestDestination $GuestDestination
            Write-DLabEvent -Level Ok -Source 'Send-DLabGuestFile' `
                -Message "Copied '$fileName' to $Name" `
                -Data @{ VMName = $Name; FileName = $fileName }
        } catch {
            Write-DLabEvent -Level Error -Source 'Send-DLabGuestFile' `
                -Message "Copy failed to ${Name}: $($_.Exception.Message)" `
                -Data @{ VMName = $Name; LocalPath = $LocalPath; Error = $_.Exception.Message }
            throw
        }
    }
}
