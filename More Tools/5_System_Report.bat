@echo off
title PC Optimizer - System Report v4.21
color 0B
for %%I in ("%~dp0..") do set "ROOTDIR=%%~fI"

:: Read-only. Shows what uses your CPU and RAM, what starts with Windows, disk space
:: and GPU driver age. It does not change any setting.
:: Administrator rights are NOT needed.

if not exist "%ROOTDIR%\tools\System_Report.ps1" goto NOTOOL

echo.
echo   PC Optimizer - System Report
echo   Starting PowerShell, please wait a few seconds.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOTDIR%\tools\System_Report.ps1" -Root "%ROOTDIR%\."
echo.
pause
exit /b

:NOTOOL
echo [ERROR] The "tools" folder was not found next to the "More Tools" folder.
echo Keep this file in the "More Tools" folder, inside the folder that has 1_Start_Here and the tools folder.
pause
exit /b
