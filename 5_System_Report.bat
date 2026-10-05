@echo off
title PC Optimizer - System Report v4.8
color 0B

:: Read-only. Shows what uses your CPU and RAM, what starts with Windows, disk space
:: and GPU driver age. It does not change any setting.
:: Administrator rights are NOT needed.

if not exist "%~dp0tools\System_Report.ps1" goto NOTOOL

echo.
echo   PC Optimizer - System Report
echo   Starting PowerShell, please wait a few seconds.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\System_Report.ps1" -Root "%~dp0."
echo.
pause
exit /b

:NOTOOL
echo [ERROR] The "tools" folder was not found next to this file.
echo Keep this file in the same folder as 1_Start_Here and the tools folder.
pause
exit /b
