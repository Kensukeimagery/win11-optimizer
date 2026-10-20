@echo off
title PC Optimizer - PC Health v4.26
color 0B
for %%I in ("%~dp0..") do set "ROOTDIR=%%~fI"

:: Read-only. Looks at crashes and blue screens, drive health, the battery (laptops),
:: the screen refresh rate, the RAM speed and the network cable speed.
:: It does not change any setting. Administrator rights are NOT needed,
:: but drive temperature and wear are shown more often when you run it as administrator.

if not exist "%ROOTDIR%\tools\PC_Health.ps1" goto NOTOOL

echo.
echo   PC Optimizer - PC Health
echo   Starting PowerShell, please wait a few seconds.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOTDIR%\tools\PC_Health.ps1" -Root "%ROOTDIR%\."
echo.
pause
exit /b

:NOTOOL
echo [ERROR] The "tools" folder was not found next to the "More Tools" folder.
echo Keep this file in the "More Tools" folder, inside the folder that has 1_Start_Here and the tools folder.
pause
exit /b