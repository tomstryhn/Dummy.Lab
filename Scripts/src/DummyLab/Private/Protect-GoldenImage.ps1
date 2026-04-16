# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

function Protect-GoldenImage {
    <#
    .SYNOPSIS
        Protects a golden image VHDX from accidental deletion or modification.
    .DESCRIPTION
        Sets the file to read-only and removes delete permissions.
        Hyper-V can still use read-only VHDXs as differencing disk parents.
    .PARAMETER Path
        Full path to the golden image VHDX.
    #>
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path $Path)) {
        Write-Warning "Golden image not found: $Path"
        return
    }

    # Set read-only attribute
    $file = Get-Item $Path
    $file.IsReadOnly = $true

    # Remove delete permission for Everyone (keep read)
    $acl = Get-Acl $Path
    $protectRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        'Everyone', 'Delete,DeleteSubdirectoriesAndFiles', 'Deny'
    )
    $acl.AddAccessRule($protectRule)
    Set-Acl -Path $Path -AclObject $acl

    Write-Host "  [+] Protected: $Path (read-only + delete-denied)" -ForegroundColor Green
}
