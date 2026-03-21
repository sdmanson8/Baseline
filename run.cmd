@echo off
setlocal

:: Launcher for users starting Win10_11Util from File Explorer or Command Prompt.
:: It hands off directly to an elevated, hidden PowerShell process so no cmd window
:: needs to stay visible while the WPF splash and GUI load.

cd /d "%~dp0"

set "LOGFILE=%TEMP%\install_log.txt"
echo Installation started at %DATE% %TIME% > "%LOGFILE%"

if exist "%temp%\WinUtil Script for Windows 10.txt" (
    del /f /q "%temp%\WinUtil Script for Windows 10.txt" >nul 2>&1
)
if exist "%temp%\WinUtil Script for Windows 11.txt" (
    del /f /q "%temp%\WinUtil Script for Windows 11.txt" >nul 2>&1
)

set "LAUNCHER_VBS=%temp%\winutil-launch.vbs"
> "%LAUNCHER_VBS%" echo Set shell = CreateObject^("Shell.Application"^)
>>"%LAUNCHER_VBS%" echo shell.ShellExecute "powershell.exe", "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File """"%~dp0Win10_11Util.ps1""""", "", "runas", 0

wscript.exe //nologo "%LAUNCHER_VBS%"
set "LAUNCH_EXIT=%ERRORLEVEL%"
del /f /q "%LAUNCHER_VBS%" >nul 2>&1

if not "%LAUNCH_EXIT%"=="0" (
    echo %DATE% %TIME% - Launcher failed with exit code %LAUNCH_EXIT%. >> "%LOGFILE%"
) else (
    echo %DATE% %TIME% - Launcher handed off to elevated PowerShell. >> "%LOGFILE%"
)

exit /b %LAUNCH_EXIT%
