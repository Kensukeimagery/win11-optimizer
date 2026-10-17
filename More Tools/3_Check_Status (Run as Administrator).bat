@echo off
title PC Optimizer - Check Status v4.24
color 0B
for %%I in ("%~dp0..") do set "ROOTDIR=%%~fI"

:: Checks whether every optimizer setting is still in place, for example
:: after a Windows Update, and offers to re-apply only what changed.

net session >nul 2>&1
if errorlevel 1 goto NOADMIN
if not exist "%ROOTDIR%\tools\Check_Status.ps1" goto NOTOOL
if not exist "%ROOTDIR%\reg" goto NOTOOL

echo.
echo   PC Optimizer - Check Status
echo   Starting PowerShell, please wait a few seconds. No key press is needed.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOTDIR%\tools\Check_Status.ps1" -Root "%ROOTDIR%\."
echo.
pause
exit /b

:NOADMIN
echo [ERROR] Please right-click this file and choose Run as administrator.
pause
exit /b

:NOTOOL
echo [ERROR] The "tools" or "reg" folder was not found next to the "More Tools" folder.
echo Keep this file in the "More Tools" folder, inside the folder that has 1_Start_Here and the tools folder.
pause
exit /b
