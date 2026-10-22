@echo off
title PC Optimizer - Support Bundle v4.31
color 0B
for %%I in ("%~dp0..") do set "ROOTDIR=%%~fI"

:: Read-only. Collects the version, Windows build, Check Status, system report, PC health,
:: a driver scan and the latest logs into ONE text file you can attach to a problem report.
:: Private details are replaced. Nothing is changed and nothing is sent anywhere.
:: Administrator rights are NOT needed.

if not exist "%ROOTDIR%\tools\Support_Bundle.ps1" goto NOTOOL

echo.
echo   PC Optimizer - Support Bundle
echo   Starting PowerShell, please wait a few seconds.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOTDIR%\tools\Support_Bundle.ps1" -Root "%ROOTDIR%\."
echo.
pause
exit /b

:NOTOOL
echo [ERROR] The "tools" folder was not found next to the "More Tools" folder.
echo Keep this file in the "More Tools" folder, inside the folder that has 1_Start_Here and the tools folder.
pause
exit /b