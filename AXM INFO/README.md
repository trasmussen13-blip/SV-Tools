# SV-Tools — AXM Service Admin User Utility

Small Windows tooling for creating and cleaning up an AXM service account used for automated tasks.

Contents
- `AXM INFO/` — informational files related to AXM.
- `AXM_ServiceAdminUsr/` — the main tooling and scripts:
  - `AXMserviceuser.ps1` — PowerShell script to create/configure the AXM service user.
  - `AXMserviceuserCleanup.ps1` — PowerShell script to remove the service user and cleanup.
  - `RunAXMserviceuser.bat` — convenience batch wrapper to run the PowerShell script.

Prerequisites
- Windows 10/11 or Windows Server
- PowerShell 5.1+ (or PowerShell Core if adapted)
- Administrator privileges to create users and modify local/group policies

Quick start
1. Open an elevated PowerShell prompt (Run as Administrator).
2. To create the AXM service user, either run the batch wrapper or call the script directly:

```powershell
.
# from repo root
.\AXM_ServiceAdminUsr\RunAXMserviceuser.bat

# or directly
PowerShell -ExecutionPolicy Bypass -File .\AXM_ServiceAdminUsr\AXMserviceuser.ps1
```

3. To remove the created account and perform cleanup:

```powershell
PowerShell -ExecutionPolicy Bypass -File .\AXM_ServiceAdminUsr\AXMserviceuserCleanup.ps1
```

Notes
- Review the scripts before running; they require administrative access and will create/modify accounts and policies.
- Customize the scripts to match your environment (naming conventions, OU paths, password handling).

Contributing
- Improvements, bug fixes, and documentation updates are welcome. Please open an issue or submit a pull request.

License
- Add your preferred license file (e.g., `LICENSE`) at the repository root. This repository currently has no license included — add one if you plan to make it public.

Author
- Created by repository owner.
