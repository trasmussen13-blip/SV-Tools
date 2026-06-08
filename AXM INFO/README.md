# AXM Info Tool

This README covers the AXM info inspection tool located in this folder.

## What it does

`AXM_info.ps1` scans a Windows host for AXM-related configuration and environment details, including:

- AXM/SimonsVoss Windows services
- installed AXM-related software
- SQL Server and LocalDB instances
- LockSysMgr `main_*` configuration entries
- SimonsVoss repository folders and MDF/LOG presence

## Usage

From an elevated PowerShell prompt, run:

```powershell
PowerShell -ExecutionPolicy Bypass -File .\AXM_info.ps1
```

If run without arguments, the script prompts for which checks to perform and whether to save a report.

## Arguments

- `-Services` — scan for AXM-related Windows services
- `-Software` — scan installed applications for AXM/SimonsVoss entries
- `-SQL` — scan for SQL Server and LocalDB instances
- `-MainDB` — inspect LockSysMgr `main_*` configuration entries
- `-Repository` — scan SimonsVoss repository folders and MDF/LOG presence
- `-All` — run all checks
- `-Dump` — prompt to save the report to a file
- `-OutFile <path>` — specify the report filename (default: `Hostname - AXM-info.txt`)

The script also supports `RunAXMinfo.bat` from the repository root, which normalizes argument formats and requests elevation.

## Example

```powershell
PowerShell -ExecutionPolicy Bypass -File .\AXM_info.ps1 -Services -SQL -Dump -OutFile "Hostname - AXM-info.txt"
```

## Notes

- Use an elevated prompt if you want the script to scan service and registry details.
- The report file includes a timestamp header when saved.

Author
- Created by Thomas Rasmussen
