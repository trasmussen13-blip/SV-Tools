@echo off
setlocal EnableDelayedExpansion

:: Locate script
set "ScriptFolder=%~dp0"
set "PS1Path=%ScriptFolder%AXM INFO\AXM_info.ps1"
if "%PS1Path:~-1%"=="\" set "PS1Path=%PS1Path:~0,-1%"

:: Normalize and build PowerShell argument list from %*
set "ARGS="
:arg_loop
if "%~1"=="" goto arg_done
set "a=%~1"
:: convert leading -- or / to -
if "!a:~0,2!"=="--" set "a=-!a:~2!"
if "!a:~0,1!"=="/" set "a=-!a:~1!"

:: If arg contains = or :, split into key and value
set "hasSep=0"
for /f "tokens=1* delims==:" %%I in ("!a!") do (
  set "k=%%I"
  set "v=%%J"
  if defined v set "hasSep=1"
)

if "!hasSep!"=="1" (
  set "ARGS=!ARGS! -!k! "!v!""
) else (
  set "ARGS=!ARGS! !a!"
)

shift
goto arg_loop
:arg_done

:: Check elevation
powershell -NoProfile -Command "If (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }"
if %ERRORLEVEL% EQU 1 (
    echo Elevation required. Requesting UAC...
    powershell -NoProfile -Command "Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%PS1Path%\" %ARGS%' -Verb RunAs"
    exit /b
)

:: Already elevated - run the script directly
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1Path%" %ARGS%

endlocal
