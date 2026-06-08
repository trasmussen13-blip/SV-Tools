# AXM Service Admin Setup

This folder contains the PowerShell script used to create a local AXM service account and assign it to all AXM services.

## Files

- `AXMserviceuser.ps1` - Creates or updates the local service account `svcaxm_usr`, grants it service logon rights, and configures AXM services to run under that account.
- `AXMserviceuserCleanup.ps1` - Removes the local service account and optionally deletes the saved password file.
- `RunAXMserviceuser.bat` - Helper batch file that elevates if needed and runs `AXMserviceuser.ps1`.

## Purpose

The script automates:

- creating or resetting a local service user (`svcaxm_usr`)
- generating and saving a random password to a file named `<hostname>-password.txt`
- setting the account password to never expire
- granting the account "Log On As A Service"
- assigning the account to all services matching `axm*`
- granting file and registry permissions for the service binaries and registry keys
- restarting the relevant services

## Requirements

- Windows
- Administrative privileges
- PowerShell with `Get-LocalUser`, `New-LocalUser`, `Get-LocalGroup`, `Add-LocalGroupMember`, `Get-Service`, and CIM access

## Usage

1. Open PowerShell as Administrator.
2. Navigate to the folder containing `AXMserviceuser.ps1`.
3. Run either:

```powershell
.\AXMserviceuser.ps1
```

or use the provided batch launcher:

```batch
RunAXMserviceuser.bat
```

## Notes

- The script saves the generated password to a file named `<hostname>-password.txt` in the same folder.
- If the AXM service user already exists, the script resets the password and reconfigures the service account.
- The script now attempts to configure the service account with CIM/WMI first, and only falls back to `sc.exe` if needed.
- Run the script from an elevated PowerShell session to avoid permission errors.
