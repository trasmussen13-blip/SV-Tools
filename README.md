# SV-Tools

A small Windows utility repository for AXM support and diagnostics.

This repository contains tools for:

- inspecting AXM-related services, installed software, SQL instances, and repository configuration (`AXM INFO/`)
- creating and cleaning up an AXM service account for automated tasks (`AXM_ServiceAdminUsr/`)

## Repository structure

- `AXM INFO/` — host inspection tooling and documentation for AXM environment discovery.
- `AXM_ServiceAdminUsr/` — scripts for configuring and cleaning an AXM service admin user.

## Getting started

### AXM inspection

Open a PowerShell prompt and run:

```powershell
PowerShell -ExecutionPolicy Bypass -File .\AXM INFO\AXM_info.ps1
```

Or use the helper launcher from the repository root:

```powershell
RunAXMinfo.bat
```

The inspection script supports the following flags:

- `-Services`
- `-Software`
- `-SQL`
- `-MainDB`
- `-Repository`
- `-All`
- `-Dump`
- `-OutFile <path>`

### AXM service user setup

Open an elevated PowerShell prompt and run:

```powershell
.\AXM_ServiceAdminUsr\RunAXMserviceuser.bat
```

To remove the account and cleanup:

```powershell
PowerShell -ExecutionPolicy Bypass -File .\AXM_ServiceAdminUsr\AXMserviceuserCleanup.ps1
```

## Notes

- Review the scripts before running them, especially those that require admin privileges.
- `AXM INFO\README.md` contains more details for the inspection tool.

Author
- Created by Thomas Rasmussen
