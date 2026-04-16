# Copyright (c) 2026 Tom Stryhn. Licensed under CC BY-NC 4.0.

#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Optional post-deployment: creates OU structure and randomized test users/groups on a lab DC.

.DESCRIPTION
    Run after Install-DC.ps1 completes. Idempotent - safe to re-run.
    Creates:
      - Standard OU structure
      - LabAdmin account (Domain Admin)
      - N randomized standard users
      - Security groups with users assigned

.NOTES
    Author  : Tom Stryhn
    Target  : Domain Controller running dummy.local
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Lab-only credentials - intentional plaintext for automation')]
[CmdletBinding()]
param (
    [string]$DomainName     = 'dummy.lab',
    [int]$UserCount         = 10,
    [string]$AdminPassword  = 'Qwerty*12345',
    [string]$UserPassword   = 'Qwerty*12345'
)

function Write-Phase { param([string]$Message); Write-Host "`n>> $Message" -ForegroundColor Cyan }

Import-Module ActiveDirectory -ErrorAction Stop
$domainDN = (Get-ADDomain).DistinguishedName

#region OU Structure
Write-Phase "Creating OU structure"
$ouDefs = @(
    @{ Name = 'Lab Users';            Path = $domainDN }
    @{ Name = 'Lab Computers';        Path = $domainDN }
    @{ Name = 'Lab Servers';          Path = $domainDN }
    @{ Name = 'Lab Groups';           Path = $domainDN }
    @{ Name = 'Lab Service Accounts'; Path = $domainDN }
    @{ Name = 'Disabled Objects';     Path = $domainDN }
)

foreach ($ou in $ouDefs) {
    $dn = "OU=$($ou.Name),$($ou.Path)"
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'" -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $ou.Name -Path $ou.Path -ProtectedFromAccidentalDeletion $true
        Write-Host "   Created: $($ou.Name)" -ForegroundColor Green
    } else {
        Write-Host "   Exists:  $($ou.Name)" -ForegroundColor DarkGray
    }
}

#region LabAdmin
Write-Phase "Creating LabAdmin (Domain Admin)"
$adminPwd = ConvertTo-SecureString $AdminPassword -AsPlainText -Force
if (-not (Get-ADUser -Filter 'SamAccountName -eq "LabAdmin"' -ErrorAction SilentlyContinue)) {
    New-ADUser -Name 'LabAdmin' -SamAccountName 'LabAdmin' `
        -UserPrincipalName "LabAdmin@$DomainName" `
        -Path "OU=Lab Users,$domainDN" `
        -AccountPassword $adminPwd -Enabled $true `
        -PasswordNeverExpires $true -Description 'Lab admin account'
    Add-ADGroupMember -Identity 'Domain Admins' -Members 'LabAdmin'
    Write-Host "   LabAdmin created (Domain Admin)." -ForegroundColor Green
} else {
    Write-Host "   LabAdmin exists." -ForegroundColor DarkGray
}

#endregion LabAdmin

#region Randomized users
Write-Phase "Creating $UserCount randomized test users"

$firstNames = @('Alice','Bob','Charlie','Diana','Erik','Fiona','Gustav','Helle','Ivan','Jana',
                'Karl','Lena','Mads','Nina','Oscar','Petra','Rasmus','Sofia','Thomas','Ulla',
                'Viktor','Wendy','Xander','Yasmin','Zack')
$lastNames  = @('Test','Demo','Lab','Dev','Qa','Stg','User','Sample','Temp','Mock')

$userPwd     = ConvertTo-SecureString $UserPassword -AsPlainText -Force
$createdSAMs = @()

for ($i = 1; $i -le $UserCount; $i++) {
    $first  = $firstNames[($i - 1) % $firstNames.Count]
    $last   = $lastNames[($i - 1) % $lastNames.Count] + $i
    $sam    = "$($first.ToLower()).$($last.ToLower())"
    $name   = "$first $last"

    if (-not (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue)) {
        New-ADUser -Name $name -SamAccountName $sam `
            -UserPrincipalName "$sam@$DomainName" `
            -GivenName $first -Surname $last `
            -Path "OU=Lab Users,$domainDN" `
            -AccountPassword $userPwd -Enabled $true `
            -PasswordNeverExpires $true -Description "Lab test user #$i"
        Write-Host "   Created: $sam" -ForegroundColor Green
    } else {
        Write-Host "   Exists:  $sam" -ForegroundColor DarkGray
    }
    $createdSAMs += $sam
}

#endregion OU Structure

#region Security Groups
Write-Phase "Creating test security groups"

$groupDefs = @(
    @{ Name = 'Lab-AllUsers';    Members = $createdSAMs }
    @{ Name = 'Lab-HelpDesk';   Members = $createdSAMs | Select-Object -First ([math]::Ceiling($UserCount / 3)) }
    @{ Name = 'Lab-Developers'; Members = $createdSAMs | Select-Object -Last  ([math]::Ceiling($UserCount / 3)) }
)

foreach ($g in $groupDefs) {
    if (-not (Get-ADGroup -Filter "SamAccountName -eq '$($g.Name)'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $g.Name -SamAccountName $g.Name `
            -GroupScope Global -GroupCategory Security `
            -Path "OU=Lab Groups,$domainDN" `
            -Description "Lab test group: $($g.Name)"
        Write-Host "   Created: $($g.Name)" -ForegroundColor Green
    } else {
        Write-Host "   Exists:  $($g.Name)" -ForegroundColor DarkGray
    }
    if ($g.Members) {
        Add-ADGroupMember -Identity $g.Name -Members $g.Members -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "  ===============================================" -ForegroundColor Yellow
Write-Host "   Lab Test Data Deployed" -ForegroundColor Yellow
Write-Host "  ===============================================" -ForegroundColor Yellow
Write-Host "   OUs      : Lab Users, Computers, Servers, Groups, Service Accounts, Disabled"
Write-Host "   LabAdmin : Domain Admin - $AdminPassword" -ForegroundColor DarkYellow
Write-Host "   Users    : $UserCount users - $UserPassword" -ForegroundColor DarkYellow
Write-Host "   Groups   : Lab-AllUsers, Lab-HelpDesk, Lab-Developers"
Write-Host "  ===============================================" -ForegroundColor Yellow
#endregion Security Groups
#endregion Randomized users
