@echo off
setlocal

:: Launcher for users starting Baseline from File Explorer or Command Prompt.
:: It hands off directly to an elevated, hidden PowerShell process so no cmd window
:: needs to stay visible while the WPF splash and GUI load.

cd /d "%~dp0"

set "LOGFILE=%TEMP%\install_log.txt"
echo Installation started at %DATE% %TIME% > "%LOGFILE%"

set "LAUNCHER_SCRIPT=%~dp0Bootstrap\Start-BaselineElevated.ps1"

if exist "%temp%\Baseline - Utility for Windows 10.txt" (
    del /f /q "%temp%\Baseline - Utility for Windows 10.txt" >nul 2>&1
)
if exist "%temp%\Baseline - Utility for Windows 11.txt" (
    del /f /q "%temp%\Baseline - Utility for Windows 11.txt" >nul 2>&1
)

if not exist "%LAUNCHER_SCRIPT%" (
    echo %DATE% %TIME% - Launcher helper missing: %LAUNCHER_SCRIPT% >> "%LOGFILE%"
    exit /b 1
)

:: -ExecutionPolicy Bypass is required here because run.cmd is the File Explorer launch path where users may not have configured their execution policy. The bypass is scoped to this single process.
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%LAUNCHER_SCRIPT%" %*
set "LAUNCH_EXIT=%ERRORLEVEL%"

if not "%LAUNCH_EXIT%"=="0" (
    echo %DATE% %TIME% - Launcher failed with exit code %LAUNCH_EXIT%. >> "%LOGFILE%"
) else (
    echo %DATE% %TIME% - Launcher handed off to elevated PowerShell. >> "%LOGFILE%"
)

exit /b %LAUNCH_EXIT%
