# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

#
# Serialises a DLab.Operation to disk with DateTime fields written as ISO 8601
# round-trip format strings. This keeps operation documents locale-neutral and
# avoids PowerShell 5.1's "/Date(xxx)/" serialisation, which does not round-
# trip cleanly through ConvertFrom-Json + [datetime] cast in non-invariant
# cultures (e.g. Danish, German).

function Save-DLabOperationDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Operation
    )

    # Project to a hashtable so we can stringify DateTime fields without
    # mutating the in-memory operation object (callers may still use it).
    $doc = [ordered]@{}
    foreach ($prop in $Operation.PSObject.Properties) {
        $v = $prop.Value
        if ($v -is [datetime]) {
            $v = $v.ToString('o')   # ISO 8601 round-trip
        } elseif ($v -is [guid]) {
            $v = $v.ToString()
        } elseif ($prop.Name -eq 'Steps' -and $v) {
            # Each step carries a _Operation back-reference so Complete-DLabOperationStep
            # can persist without the caller passing the parent again. Strip it here to
            # break the circular chain (step._Operation.Steps[n]._Operation...) that
            # makes ConvertTo-Json exceed its depth limit and truncate the document.
            $v = @($v | ForEach-Object {
                $stepDoc = [ordered]@{}
                foreach ($sp in $_.PSObject.Properties) {
                    if ($sp.Name -eq '_Operation') { continue }
                    $sv = $sp.Value
                    if ($sv -is [datetime]) { $sv = $sv.ToString('o') }
                    elseif ($sv -is [guid])     { $sv = $sv.ToString() }
                    $stepDoc[$sp.Name] = $sv
                }
                $stepDoc
            })
        }
        $doc[$prop.Name] = $v
    }

    $doc | ConvertTo-Json -Depth 10 | Set-Content -Path $Operation.LogPath -Encoding UTF8
}
