@echo off
REM .NAME    Set_SectorSize_To_4096
REM .VERSION 1.0.0
REM .CATEGORY Tools
REM .SYNOPSIS Adds or updates ForcedPhysicalSectorSizeInBytes REG_MULTI_SZ for stornvme driver
REM .DESCRIPTION
REM   Ensures the registry value ForcedPhysicalSectorSizeInBytes exists under:
REM   HKLM\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device
REM   and sets it to a multi-string containing "*" and "4095".
REM   A reboot may be required for the driver to pick up the change.
REM .ADMIN   YES

REG ADD "HKLM\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device" /v "ForcedPhysicalSectorSizeInBytes" /t REG_MULTI_SZ /d "* 4095" /f
pause