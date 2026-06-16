@echo off
echo.

set SCRIPT="%~dp0Launcher.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File %SCRIPT%

echo.
echo ----------------------------------------
pause
