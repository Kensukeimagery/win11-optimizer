@echo off
title PC Optimizer - Driver Check v4.11
color 0B

:: Scans for missing or outdated drivers and offers Windows Update drivers.
:: Nothing is installed unless you choose it. BETA.

net session >nul 2>&1
if errorlevel 1 goto NOADMIN
if not exist "%~dp0tools\Driver_Check.ps1" goto NOTOOL

echo.
echo   PC Optimizer - Driver Check
echo   Starting PowerShell, please wait a few seconds. No key press is needed.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Driver_Check.ps1" -Root "%~dp0."
echo.
pause
exit /b

:NOADMIN
echo [ERROR] Please right-click this file and choose Run as administrator.
pause
exit /b

:NOTOOL
echo [ERROR] The "tools" folder was not found next to this file.
echo Keep this file in the same folder as 1_Start_Here and the tools folder.
pause
exit /b