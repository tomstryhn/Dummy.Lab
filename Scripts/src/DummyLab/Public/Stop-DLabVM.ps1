# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Stop-DLabVM {
    <#
    .SYNOPSIS
        Stops a Dummy.Lab VM.
    .DESCRIPTION
        Wrapper around Stop-VM with event instrumentation. Attempts a graceful
        shutdown unless -TurnOff is specified, in which case the VM is hard-
        powered-off. Idempotent when the VM is already off.

        Live-off-the-land: Stop-VM does the work; this cmdlet adds narration.
    .PARAMETER Name
        Full Hyper-V VM name. Accepts pipeline input.
    .PARAMETER TurnOff
        Hard power-off. Use when the guest OS is unresponsive or for fast
        shutdowns where clean OS state is not needed.
    .PARAMETER Force
        Bypass confirmation prompts for non-graceful shutdowns.
    .PARAMETER PassThru
        Emit the DLab.VM object after stopping.
    .EXAMPLE
        Stop-DLabVM -Name PipeTest-SRV01
    .EXAMPLE
        Get-DLabVM -LabName PipeTest | Stop-DLabVM -TurnOff -Force
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('DLab.VM')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('VMName')]
        [string]$Name,

        [switch]$TurnOff,
        [switch]$Force,
        [switch]$PassThru
    )

    process {
        $vm = Get-VM -Name $Name -ErrorAction SilentlyContinue
        if (-not $vm) {
            Write-Error "VM not found: $Name"
            return
        }

        if ($vm.State -eq 'Off') {
            Write-DLabEvent -Level Info -Source 'Stop-DLabVM' `
                -Message "$Name is already off" `
                -Data @{ VMName = $Name; State = 'Off' }
            if ($PassThru) { Get-DLabVM -VMName $Name }
            return
        }

        $action = if ($TurnOff) { 'Turn off (hard power-off)' } else { 'Shut down (graceful)' }
        if (-not $PSCmdlet.ShouldProcess($Name, $action)) { return }

        Write-DLabEvent -Level Step -Source 'Stop-DLabVM' `
            -Message "$action`: $Name" `
            -Data @{ VMName = $Name; TurnOff = [bool]$TurnOff }

        try {
            if ($TurnOff) {
                Stop-VM -Name $Name -TurnOff -Force:$Force -ErrorAction Stop | Out-Null
            } else {
                Stop-VM -Name $Name -Force:$Force -ErrorAction Stop | Out-Null
            }
            Write-DLabEvent -Level Ok -Source 'Stop-DLabVM' `
                -Message "$Name stopped" `
                -Data @{ VMName = $Name }
        } catch {
            Write-DLabEvent -Level Error -Source 'Stop-DLabVM' `
                -Message "Failed to stop ${Name}: $($_.Exception.Message)" `
                -Data @{ VMName = $Name; Error = $_.Exception.Message }
            throw
        }

        if ($PassThru) { Get-DLabVM -VMName $Name }
    }
}
