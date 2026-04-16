# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

#
# Locale-safe parser for DateTime values read from persisted operation and
# event documents. Handles three shapes:
#   1. Already a [datetime] object (PS 7 auto-parses ISO 8601 in JSON)
#   2. ISO 8601 round-trip string (what we now write with 'o' format)
#   3. Legacy "/Date(epoch-ms)/" strings from PS 5.1's older JSON serialisation
# Returns $null for empty or unparseable inputs. Never throws, so callers can
# treat missing/corrupt date fields as "not set" rather than as errors.

function ConvertFrom-DLabJsonDate {
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [Parameter(ValueFromPipeline)]
        $Value
    )
    process {
        if ($null -eq $Value)            { return $null }
        if ($Value -is [datetime])       { return $Value }

        $s = "$Value".Trim()
        if (-not $s)                     { return $null }

        # Legacy /Date(ms)/ form from older PS 5.1 ConvertTo-Json output
        if ($s -match '/Date\((-?\d+)\)/') {
            try {
                $epoch = [datetime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
                return $epoch.AddMilliseconds([long]$matches[1]).ToLocalTime()
            } catch { return $null }
        }

        # ISO 8601 and other parseable formats. Parse with InvariantCulture
        # and Roundtrip style so Danish/German/etc. locales don't break it.
        # Any UTC-kind result is converted to local so downstream filters and
        # format views don't have to worry about DateTime.Kind mismatches.
        try {
            $parsed = [datetime]::Parse(
                $s,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::RoundtripKind
            )
            if ($parsed.Kind -eq [System.DateTimeKind]::Utc) {
                $parsed = $parsed.ToLocalTime()
            }
            return $parsed
        } catch {
            try { return [datetime]$s } catch { return $null }
        }
    }
}
