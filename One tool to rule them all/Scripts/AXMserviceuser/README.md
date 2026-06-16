# AXM Service Admin Setup

This folder contains PowerShell scripts used to create and manage a local AXM service account and assign it to all AXM-related services.

## Files

- `AXMserviceuser.ps1`  
  Creates or updates the local service account `svcaxm_usr`, grants service logon rights, assigns it to AXM services, configures service logons, restarts services, and validates final state.

- `AXMserviceuserCleanup.ps1`  
  Removes the local service account and optionally cleans up related configuration.

- `RunAXMserviceuser.bat`  
  Helper batch file that elevates privileges if required and runs `AXMserviceuser.ps1`.

## Purpose

The script automates:

- Create or reset local service user (`svcaxm_usr`)
- Generate random runtime password (not saved to disk)
- Set password to never expire
- Grant "Log On As A Service"
- Assign to services:
  - axm*

- Configure services using CIM/WMI with fallback to `sc.exe`
- Restart services in dependency-aware order
- Validate final state

## Requirements

- Windows Server / Windows 10/11
- Administrator rights
- PowerShell with:
  - Get-LocalUser
  - New-LocalUser
  - Set-LocalUser
  - Get-Service
  - Get-CimInstance
  - Invoke-CimMethod
  - sc.exe

## Usage

1. Open PowerShell as Administrator  
2. Navigate to folder  
3. Run:

    .\AXMserviceuser.ps1

or run:

    RunAXMserviceuser.bat

## Notes

- Password is generated per run and NOT stored
- Script is idempotent in service configuration
- Designed for controlled admin environments only
