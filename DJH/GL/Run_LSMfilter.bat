@echo off
title LSM Filter Tool
echo ----------------------------------------
echo        Korer LSM Filter Script
echo ----------------------------------------
echo.

:: Sæt stien til PowerShell scriptet
set SCRIPT="%~dp0LSMFilter.ps1"

:: Kør PowerShell scriptet med Bypass
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %SCRIPT%

echo.
echo ----------------------------------------
echo Faerdig! Tryk en tast for at lukke...
pause >nul