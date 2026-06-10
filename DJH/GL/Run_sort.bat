@echo off
title CSV Filter Tool
echo ----------------------------------------
echo        Korer CSV Filter Script
echo ----------------------------------------
echo.

:: Sæt stien til PowerShell scriptet
set SCRIPT="%~dp0TheSortingHat.ps1"

:: Kør PowerShell scriptet
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %SCRIPT%

echo.
echo ----------------------------------------
echo Faerdig! Tryk en tast for at lukke...
pause >nul