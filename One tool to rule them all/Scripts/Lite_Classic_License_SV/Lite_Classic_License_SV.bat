@echo off
REM .NAME Lite_Classic_License
REM .VERSION 1.0.0
REM .CATEGORY Tools
REM .SYNOPSIS Resets AXM_LIGHT/CLASSIC registration.
REM .DESCRIPTION This Tool resets AXM_LIGHT/CLASSIC registration.
REM  This is used to remedy registration error typically encountered when going from V1 to V2.    
REM .ADMIN   NO

set "file=%~dp0Lite_Classic_License_SV.html"

if exist "%file%" (
    start "" "%file%"
    exit /b 0
) else (
    echo File not found: "%file%"
    pause
    exit /b 1
)