@echo off
REM .NAME    CreateBackupFromRepository
REM .VERSION 1.0.0
REM .CATEGORY Backup
REM .SYNOPSIS Creates a Backup From Repository.
REM .DESCRIPTION
REM AXM-services needs to be killed before running this tool. 
REM This tool will create a backup of the repository and store it in the same location as the executable.  
REM .ADMIN   NO

if not exist "%~dp0CreateBackupFromRepository.exe" (
    echo ERROR: CreateBackupFromRepository.exe not found in "%~dp0"
    pause
    exit /b 1
)

start /wait "" "%~dp0CreateBackupFromRepository.exe"