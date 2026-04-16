# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Start-DLabVM {
    <#
    .SYNOPSIS
        Starts a Dummy.Lab VM.
    .DESCRIPTION
        Thin wrapper around Start-VM that adds event instrumentation and
        optionally emits the DLab.VM object for pipeline chaining. Idempotent
        when the VM is already running.

        Live-off-the-land: the heavy lifting is done by Start-VM. This cmdlet
        adds narration and integrates the operation into the event log.
    .PARAMETER Name
        Full Hyper-V VM name (e.g. 'PipeTest-SRV01'). Accepts pipeline input
        from DLab.VM.Name.
    .PARAMETER PassThru
        Emit the resulting DLab.VM object. By default the cmdlet produces no
        output, matching Start-VM's convention.
    .EXAMPLE
        Start-DLabVM -Name PipeTest-SRV01
    .EXAMPLE
        Get-DLabVM -Role Server | Start-DLabVM -PassThru | Wait-DLabVM
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType('DLab.VM')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('VMName')]
        [string]$Name,

        [switch]$PassThru
    )

    process {
        $vm = Get-VM -Name $Name -ErrorAction SilentlyContinue
        if (-not $vm) {
            Write-Error "VM not found: $Name"
            return
        }

        if ($vm.State -eq 'Running') {
            Write-DLabEvent -Level Info -Source 'Start-DLabVM' `
                -Message "$Name is already running" `
                -Data @{ VMName = $Name; State = 'Running' }
            if ($PassThru) { Get-DLabVM -VMName $Name }
            return
        }

        if (-not $PSCmdlet.ShouldProcess($Name, 'Start VM')) { return }

        Write-DLabEvent -Level Step -Source 'Start-DLabVM' `
            -Message "Starting $Name" `
            -Data @{ VMName = $Name }

        try {
            Start-VM -Name $Name -ErrorAction Stop | Out-Null
            Write-DLabEvent -Level Ok -Source 'Start-DLabVM' `
                -Message "$Name started" `
                -Data @{ VMName = $Name }
        } catch {
            Write-DLabEvent -Level Error -Source 'Start-DLabVM' `
                -Message "Failed to start ${Name}: $($_.Exception.Message)" `
                -Data @{ VMName = $Name; Error = $_.Exception.Message }
            throw
        }

        if ($PassThru) { Get-DLabVM -VMName $Name }
    }
}
