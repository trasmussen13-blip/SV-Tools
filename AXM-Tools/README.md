# Script Launcher System - README

## Overview

This project is a PowerShell based utility launcher designed to collect,
organize, document, and execute internal tools from a single interface.

The launcher automatically scans the `./scripts` folder, detects
available tools, reads their metadata headers, groups them by category,
and provides an interactive console menu.

The system is designed for internal administration, diagnostics, and
support tooling where multiple scripts need to be maintained and
executed consistently.

------------------------------------------------------------------------

# Folder Structure

Recommended layout:

    Launcher/
    │
    ├── Launcher.ps1
    ├── banner.txt
    ├── README.md
    │
    └── scripts/
        │
        ├── Tool01/
        │   ├── Tool01.ps1
        │   └── readme.md
        │
        ├── Tool02/
        │   ├── Tool02.bat
        │   └── readme.md
        │
        └── Tool03/
            └── Tool03.cmd

Each subfolder inside `scripts` represents one tool.

The launcher expects one primary executable script per folder.

Supported formats:

-   `.ps1`
-   `.bat`
-   `.cmd`

If multiple supported files exist:

1.  `.ps1` is preferred
2.  `.bat` / `.cmd` are fallback options

------------------------------------------------------------------------

# Launcher Features

## Automatic Discovery

The launcher scans:

    ./scripts/*

and automatically detects tools.

No manual registration is required.

------------------------------------------------------------------------

## Metadata Detection

The launcher reads metadata from the script header.

Supported fields:

-   Name
-   Version
-   Category
-   Synopsis
-   Description
-   Admin requirement

The metadata is displayed in the menu and tool information screen.

------------------------------------------------------------------------

## PowerShell Script Header Format

Example:

``` powershell
<#
.NAME
    AXM_info

.VERSION
    1.2.0

.CATEGORY
    AXM Diagnostics

.SYNOPSIS
    Checks the local machine for AXM related software.

.DESCRIPTION
    Scans services, software,
    SQL instances and configuration files.

    Creates a diagnostic overview.

.ADMIN
    YES
#>
```

Rules:

-   Header must be inside `<# ... #>`
-   Tags start with `.`
-   Multi-line descriptions are supported
-   `.ADMIN YES` enables automatic elevation

------------------------------------------------------------------------

# Batch Script Header Format

Example:

``` bat
REM .NAME
REM AXM Cleanup

REM .VERSION
REM 1.0.0

REM .CATEGORY
REM Maintenance

REM .SYNOPSIS
REM Cleans temporary files.

REM .DESCRIPTION
REM Removes temporary data.
REM Performs cleanup checks.

REM .ADMIN YES
```

Supported comment styles:

``` bat
REM
```

or

``` bat
::
```

------------------------------------------------------------------------

# Administrator Execution

Scripts can request administrator privileges.

Enable:

``` powershell
.ADMIN
    YES
```

When selected:

-   If already running as administrator:
    -   Script runs normally
-   If not:
    -   Launcher starts the script elevated using UAC

Supported:

-   PowerShell elevation
-   Batch elevation

------------------------------------------------------------------------

# Readme Support

Each tool folder may contain:

    readme.md

Example:

    scripts/
    └── AXM_info/
        ├── AXM_info.ps1
        └── readme.md

The launcher detects this automatically.

The tool menu will show:

    [README]

and the detail view provides a help option.

------------------------------------------------------------------------

# Adding a New Script

## Step 1

Create a new folder:

Example:

    scripts/MyTool/

------------------------------------------------------------------------

## Step 2

Add your script:

Example:

    scripts/MyTool/MyTool.ps1

------------------------------------------------------------------------

## Step 3

Add the metadata header:

Example:

``` powershell
<#
.NAME
    MyTool

.VERSION
    1.0.0

.CATEGORY
    Utilities

.SYNOPSIS
    Performs a useful task.

.DESCRIPTION
    Detailed explanation of what the tool does.

.ADMIN
    NO
#>
```

------------------------------------------------------------------------

## Step 4

(Optional)

Add documentation:

    scripts/MyTool/readme.md

------------------------------------------------------------------------

## Step 5

Start the launcher.

The new tool will automatically appear.

------------------------------------------------------------------------

# Recommended Development Practices

## Naming

Use clear names:

Good:

    AXM_Info
    SQL_Check
    Log_Analyzer

Avoid:

    test1
    script_new
    final2

------------------------------------------------------------------------

## Categories

Use categories consistently.

Examples:

    Diagnostics
    Maintenance
    Deployment
    Utilities
    Reporting

------------------------------------------------------------------------

## Descriptions

Write descriptions for technicians, not developers.

Explain:

-   What it checks
-   What it changes
-   Expected output
-   Risks

------------------------------------------------------------------------

# Design Philosophy

The launcher separates:

## Framework

The launcher handles:

-   Discovery
-   UI
-   Metadata
-   Elevation
-   Documentation links

## Tools

Individual scripts handle:

-   Their own logic
-   Parameters
-   Output
-   Processing

This allows tools to be added without modifying the launcher.

------------------------------------------------------------------------

# Maintenance

To update a tool:

Replace only the script inside its folder.

The launcher does not require rebuilding.

------------------------------------------------------------------------

# Summary

The system provides a lightweight internal tool platform:

-   Automatic script discovery
-   Central execution point
-   Standard documentation format
-   Metadata driven UI
-   Administrator handling
-   Support for PowerShell and batch tools

New tools can be added by simply creating a folder, adding a script, and
including a valid header.
