@echo off
setlocal

:: Get the folder where this batch file is located
set "ScriptFolder=%~dp0"
set "PS1Path=%ScriptFolder%AXMserviceuser.ps1"

:: Remove trailing backslash from path if present (optional)
if "%PS1Path:~-1%"=="\" set "PS1Path=%PS1Path:~0,-1%"

:: Check if running elevated
powershell -NoProfile -Command ^
  "If (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }"
if %ERRORLEVEL% EQU 1 (
    echo Elevation required. Requesting UAC...
    powershell -NoProfile -Command "Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%PS1Path%\"' -Verb RunAs"
    exit /b
)

:: Already elevated - run the script directly
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1Path%"

endlocal
