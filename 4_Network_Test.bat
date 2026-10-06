@echo off
title PC Optimizer - Network Test v4.15
color 0B

:: Read-only. Pings your router, 1.1.1.1, 8.8.8.8 and an optional game server,
:: then shows ping, jitter and packet loss. It does not change any setting.
:: Administrator rights are NOT needed.

if not exist "%~dp0tools\Network_Test.ps1" goto NOTOOL

echo.
echo   PC Optimizer - Network Test
echo   Starting PowerShell, please wait a few seconds.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Network_Test.ps1" -Root "%~dp0."
echo.
pause
exit /b

:NOTOOL
echo [ERROR] The "tools" folder was not found next to this file.
echo Keep this file in the same folder as 1_Start_Here and the tools folder.
pause
exit /b
