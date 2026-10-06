@echo off
title PC Optimizer - Support Bundle v4.16
color 0B

:: Read-only. Collects the version, Windows build, Check Status, system report, PC health,
:: a driver scan and the latest logs into ONE text file you can attach to a problem report.
:: Private details are replaced. Nothing is changed and nothing is sent anywhere.
:: Administrator rights are NOT needed.

if not exist "%~dp0tools\Support_Bundle.ps1" goto NOTOOL

echo.
echo   PC Optimizer - Support Bundle
echo   Starting PowerShell, please wait a few seconds.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Support_Bundle.ps1" -Root "%~dp0."
echo.
pause
exit /b

:NOTOOL
echo [ERROR] The "tools" folder was not found next to this file.
echo Keep this file in the same folder as 1_Start_Here and the tools folder.
pause
exit /b