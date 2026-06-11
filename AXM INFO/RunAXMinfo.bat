@echo off
setlocal

set "ScriptFolder=%~dp0"
set "PS1Path=%ScriptFolder%AXM_info.ps1"

if not exist "%PS1Path%" (
    echo [ERROR] PowerShell script not found:
    echo         "%PS1Path%"
    echo.
    pause
    exit /b 2
)

:: Check admin
powershell -NoProfile -Command ^
    "if (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }"

if errorlevel 1 (
    echo Elevation required. Requesting UAC...
    powershell -NoProfile -Command ^
        "try { $p = Start-Process powershell.exe -Verb RunAs -PassThru -Wait -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','%PS1Path%'); exit $p.ExitCode } catch { exit 1223 }"

    set "RC=%ERRORLEVEL%"

    if "%RC%"=="1223" (
        echo.
        echo [ERROR] UAC elevation was cancelled or denied.
        echo.
        pause
        exit /b 1223
    )

    if not "%RC%"=="0" (
        echo.
        echo [ERROR] Elevated PowerShell script failed.
        echo [ERROR] Exit code: %RC%
        echo [ERROR] Script: "%PS1Path%"
        echo.
        pause
        exit /b %RC%
    )

    echo.
    echo Script completed successfully.
    echo.
    pause
    endlocal
    exit /b 0
)

:: Already elevated
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1Path%" %*
set "RC=%ERRORLEVEL%"

if not "%RC%"=="0" (
    echo.
    echo [ERROR] PowerShell script failed.
    echo [ERROR] Exit code: %RC%
    echo [ERROR] Script: "%PS1Path%"
    echo.
    pause
    exit /b %RC%
)

echo.
echo Script completed successfully.
echo.
pause

endlocal
exit /b 0