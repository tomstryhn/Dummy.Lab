# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

#
# Pure forwarder. Every narrative line from orchestration code (phase helpers,
# Deploy-LabDC, Deploy-LabMember, etc.) routes through Write-DLabEvent so it
# lands in the single structured event ledger at <root>\Events\*.jsonl.
#
# No plaintext log file is written. The -Level values 'OK', 'Detail', 'Auto',
# and 'WhatIf' are preserved for backwards-compatibility with the pre-merge
# Lab* modules' call signatures; they map to the closest Write-DLabEvent level.
# DLab.ps1 flips $script:DLabRenderToHost so interactive operators still see
# the narrative on the console during a build; automation callers see only
# the structured events.

# Initialised here so New-DLabGoldenImage can safely read and restore it
# under Set-StrictMode -Version Latest, even on first run before DLab.ps1
# has had a chance to set it.
$script:DLabRenderToHost = $false

function Write-LabLog {
    param(
        [Parameter(Mandatory, Position = 0)][string]$Message,
        [ValidateSet('Info', 'OK', 'Warn', 'Error', 'Step', 'Detail', 'Auto', 'WhatIf')]
        [string]$Level = 'Info'
    )

    $dlabLevel = switch ($Level) {
        'OK'     { 'Ok' }
        'Warn'   { 'Warn' }
        'Error'  { 'Error' }
        'Step'   { 'Step' }
        'Detail' { 'Info' }
        'Auto'   { 'Info' }
        'WhatIf' { 'Info' }
        default  { 'Info' }
    }

    # Use the calling cmdlet as the event source so Get-DLabEventLog -Source
    # filters pick up the right owner. Falls back to 'legacy' if the stack
    # is unavailable (e.g. called from an unusual context).
    $source = 'legacy'
    try {
        $callStack = Get-PSCallStack
        if ($callStack.Count -ge 2) {
            $c = $callStack[1].Command
            if ($c) { $source = $c }
        }
    } catch { }

    Write-DLabEvent -Level $dlabLevel -Source $source -Message $Message
}
