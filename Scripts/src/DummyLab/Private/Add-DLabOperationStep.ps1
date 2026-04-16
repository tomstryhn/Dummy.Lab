# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

#
# Appends a DLab.OperationStep to a running DLab.Operation, persists the
# operation document, and emits a DLab.Event for the step. Used by multi-
# stage cmdlets (New-DLab, Add-DLabVM, New-DLabGoldenImage) so callers can
# reconstruct the exact timeline of what each run did, including partial
# progress on failures.
#
# Usage pattern:
#   $op = New-DLabOperation -Kind New-DLab -Target MyLab -LabName MyLab
#   $step = Add-DLabOperationStep -Operation $op -Name 'Create switch'
#   try {
#       New-VMSwitch -Name ... | Out-Null
#       $step | Complete-DLabOperationStep -Status Succeeded
#   } catch {
#       $step | Complete-DLabOperationStep -Status Failed -Message $_.Exception.Message
#       throw
#   }

function Add-DLabOperationStep {
    [CmdletBinding()]
    [OutputType('DLab.OperationStep')]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Operation,
        [Parameter(Mandatory)][string]$Name,
        [string]$Message = ''
    )

    $step = [PSCustomObject]@{
        PSTypeName  = 'DLab.OperationStep'
        Name        = $Name
        StartedAt   = Get-Date
        CompletedAt = $null
        DurationSec = $null
        Status      = 'Running'
        Message     = $Message
    }

    # Keep a reference back to the parent operation so Complete-DLabOperationStep
    # can persist without callers passing it again.
    $step | Add-Member -NotePropertyName _Operation -NotePropertyValue $Operation -Force

    $Operation.Steps = @($Operation.Steps) + @($step)
    Save-DLabOperationDocument -Operation $Operation

    Write-DLabEvent -Level Step -Source $Operation.Kind `
        -Message $Name `
        -OperationId $Operation.OperationId `
        -Data @{ StepName = $Name; Target = $Operation.Target }

    return $step
}

function Complete-DLabOperationStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][PSCustomObject]$Step,
        [ValidateSet('Succeeded', 'Failed', 'Skipped')][string]$Status = 'Succeeded',
        [string]$Message = ''
    )
    process {
        $Step.CompletedAt = Get-Date
        $Step.DurationSec = [math]::Round(($Step.CompletedAt - $Step.StartedAt).TotalSeconds, 2)
        $Step.Status      = $Status
        if ($Message) { $Step.Message = $Message }

        $op = $Step._Operation
        if ($op) {
            Save-DLabOperationDocument -Operation $op

            $level = switch ($Status) {
                'Succeeded' { 'Ok' }
                'Failed'    { 'Error' }
                'Skipped'   { 'Info' }
            }
            Write-DLabEvent -Level $level -Source $op.Kind `
                -Message "$($Step.Name) ($Status, $($Step.DurationSec)s)" `
                -OperationId $op.OperationId `
                -Data @{ StepName = $Step.Name; DurationSec = $Step.DurationSec; Status = $Status }
        }
    }
}
