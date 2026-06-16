@echo off
rem Finds and analyzes the newest AXMLog file in the LockSysMgr log directory.

setlocal enabledelayedexpansion
set "SCRIPT_DIR=%~dp0"
set "LOG_SOURCE_DIR=%USERPROFILE%\AppData\Local\SimonsVoss\LockSysMgr\log"

rem Check if the log directory exists
if not exist "%LOG_SOURCE_DIR%" (
    echo Error: Log directory not found: %LOG_SOURCE_DIR%
    pause
    exit /b 1
)

rem Find the newest AXMLog file
for /f "tokens=*" %%F in ('dir /b /o-d "%LOG_SOURCE_DIR%\AXMLog*.log" 2^>nul') do (
    set "LOG_PATH=%LOG_SOURCE_DIR%\%%F"
    goto found
)

echo Error: No AXMLog files found in %LOG_SOURCE_DIR%
pause
exit /b 1

:found
echo Analyzing: %LOG_PATH%
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%AXM_log_condenser.ps1" -Path "%LOG_PATH%"
exit /b %ERRORLEVEL%
