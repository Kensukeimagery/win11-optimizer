@echo off
title PC Optimizer - Driver Check v4.30
color 0B
for %%I in ("%~dp0..") do set "ROOTDIR=%%~fI"

:: Scans for missing or outdated drivers and offers Windows Update drivers.
:: Nothing is installed unless you choose it. BETA.

net session >nul 2>&1
if errorlevel 1 goto NOADMIN
if not exist "%ROOTDIR%\tools\Driver_Check.ps1" goto NOTOOL

echo.
echo   PC Optimizer - Driver Check
echo   Starting PowerShell, please wait a few seconds. No key press is needed.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOTDIR%\tools\Driver_Check.ps1" -Root "%ROOTDIR%\."
echo.
pause
exit /b

:NOADMIN
echo [ERROR] Please right-click this file and choose Run as administrator.
pause
exit /b

:NOTOOL
echo [ERROR] The "tools" folder was not found next to the "More Tools" folder.
echo Keep this file in the "More Tools" folder, inside the folder that has 1_Start_Here and the tools folder.
pause
exit /b