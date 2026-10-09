@echo off
title PC Optimizer - PC Health v4.17
color 0B

:: Read-only. Looks at crashes and blue screens, drive health, the battery (laptops),
:: the screen refresh rate, the RAM speed and the network cable speed.
:: It does not change any setting. Administrator rights are NOT needed,
:: but drive temperature and wear are shown more often when you run it as administrator.

if not exist "%~dp0tools\PC_Health.ps1" goto NOTOOL

echo.
echo   PC Optimizer - PC Health
echo   Starting PowerShell, please wait a few seconds.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\PC_Health.ps1" -Root "%~dp0."
echo.
pause
exit /b

:NOTOOL
echo [ERROR] The "tools" folder was not found next to this file.
echo Keep this file in the same folder as 1_Start_Here and the tools folder.
pause
exit /b