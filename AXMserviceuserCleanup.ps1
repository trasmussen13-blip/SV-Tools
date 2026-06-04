<#
.SYNOPSIS
    Removes the AXM service user account (svcaxm_usr)

.DESCRIPTION
    Deletes the local service account named svcaxm_usr and optionally removes the password file.

.AUTHOR
    Thomas Krogager Rasmusen
    SimonsVoss

.VERSION
    1.0.0

.NOTES
    Requires administrator privileges to execute.
#>

# Requires administrator privileges
#Requires -RunAsAdministrator

$accountName = "svcaxm_usr"

Write-Host "Starting AXM service user cleanup..." -ForegroundColor Cyan

# Check if user exists
try {
    $user = Get-LocalUser -Name $accountName -ErrorAction Stop
    Write-Host "Found service user: $accountName" -ForegroundColor Green
} catch {
    Write-Host "Service user '$accountName' not found." -ForegroundColor Yellow
    Read-Host -Prompt 'Press Enter to exit'
    exit 0
}

# Confirm deletion
$confirm = Read-Host "Are you sure you want to delete user '$accountName'? (yes/no)"
if ($confirm -ne 'yes') {
    Write-Host "Deletion cancelled." -ForegroundColor Yellow
    Read-Host -Prompt 'Press Enter to exit'
    exit 0
}

# Remove the user from Administrators group
try {
    $adminGroup = Get-LocalGroup | Where-Object { $_.SID.Value -eq 'S-1-5-32-544' }
    if ($adminGroup) {
        Remove-LocalGroupMember -Group $adminGroup.Name -Member $accountName -ErrorAction Stop
        Write-Host "Removed '$accountName' from Administrators group." -ForegroundColor Green
    }
} catch {
    Write-Host "Warning: Could not remove user from Administrators group: $_" -ForegroundColor Yellow
}

# Delete the user account
try {
    Remove-LocalUser -Name $accountName -ErrorAction Stop
    Write-Host "Service user '$accountName' deleted successfully." -ForegroundColor Green
} catch {
    Write-Host "Error deleting service user: $_" -ForegroundColor Red
    Read-Host -Prompt 'Press Enter to exit'
    exit 1
}

# Remove password file if it exists
$hostname = $env:COMPUTERNAME
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$passwordFile = Join-Path $scriptPath "${hostname}-password.txt"

if (Test-Path $passwordFile) {
    try {
        Remove-Item -Path $passwordFile -Force -ErrorAction Stop
        Write-Host "Password file removed: $passwordFile" -ForegroundColor Green
    } catch {
        Write-Host "Warning: Could not remove password file: $_" -ForegroundColor Yellow
    }
}

Write-Host "`nService user cleanup complete!" -ForegroundColor Green
Read-Host -Prompt 'Press Enter to exit'
