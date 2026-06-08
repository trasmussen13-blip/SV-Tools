@echo off
rem Drop an AXM log file onto this batch file to analyze it.
rem The script writes console output and can optionally generate JSON when a second argument is provided.

set "SCRIPT_DIR=%~dp0"
set "LOG_PATH=%~1"

if "%LOG_PATH%"=="" (
    echo Usage: Drag and drop an AXM log file onto this batch file.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%AXM_log_analyzer.ps1" -Path "%LOG_PATH%"
exit /b %ERRORLEVEL%
