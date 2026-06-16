@echo off
title CSV Filter & Delta Tool
echo ----------------------------------------
echo     CSV Filter og Delta Compare Tool
echo       Leveret AS IS af SimonsVoss
echo ----------------------------------------
echo.

set SCRIPT="%~dp0master_filter.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File %SCRIPT%

echo.
echo ----------------------------------------
