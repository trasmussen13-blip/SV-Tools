# AXM Log Condenser

## Version
3.0.0

## Category
AXM Diagnostics

## Purpose

AXM Log Condenser is a diagnostic helper tool for analysing AXM log files.

The tool reads AXM log files and creates a simplified overview of:

- Log file information
- Entry counts
- Fatal / Error / Warning events
- Detected AXM components
- Repeated error patterns
- Stack traces

The goal is to reduce the time needed to manually search through large AXM log files.

---

## Usage

Run without parameters:

```powershell
.\AXM_log_condenser.ps1