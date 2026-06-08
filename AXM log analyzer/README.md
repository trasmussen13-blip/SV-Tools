# AXM Log Analyzer

Standalone PowerShell tool for analyzing SimonsVoss AXM log files.

## Purpose

- Parse AXM log files
- Extract environment information
- Detect programming and communication sessions
- Summarize issues and recurring patterns
- Produce technician-friendly console output
- Export structured JSON for future AI or automation integration

## Usage

```powershell
powershell -File .\AXM_log_analyzer.ps1 -Path .\AXMLog-PlatformPlus-20260602_003.log
```

Generate JSON output:

```powershell
powershell -File .\AXM_log_analyzer.ps1 -Path .\AXMLog-PlatformPlus-20260602_003.log -Json -Output .\AXMReport.json
```

## Components

- `Parse-AXMLogLine` — parses timestamps, log level, component, and message
- `Analyze-Environment` — extracts version, database type, gateway and service details
- `Analyze-Sessions` — groups programming sessions and counts related operations
- `Analyze-Issues` — categorizes log problems into critical, warning, and informational buckets
- `Analyze-Patterns` — detects recurring issue patterns
- `Generate-Timeline` — creates a chronological summary of significant events
- `Get-Recommendations` — generates practical support recommendations

## Notes

- The script is designed to be extended with additional analyzers or export formats.
- It does not modify systems or perform diagnostics beyond log interpretation.
