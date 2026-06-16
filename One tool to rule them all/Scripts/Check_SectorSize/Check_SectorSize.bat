@echo off
REM .NAME    Check_SectorSize
REM .VERSION 1.0.0
REM .CATEGORY Diagnostics
REM .SYNOPSIS Run fsutil to show sector info for C:
REM .DESCRIPTION
REM   Shows bytes per sector, physical sector size and alignment info for C:
REM .ADMIN   YES

fsutil fsinfo sectorinfo c:
pause