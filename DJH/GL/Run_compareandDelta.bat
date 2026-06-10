@echo off
title Delta Compare Tool
echo ----------------------------------------
echo        Korer Delta Compare Script
echo ----------------------------------------
echo.

set SCRIPT="%~dp0delta_compare.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File %SCRIPT%

echo.
echo ----------------------------------------
echo Faerdig! Tryk en tast for at lukke...
pause >nul