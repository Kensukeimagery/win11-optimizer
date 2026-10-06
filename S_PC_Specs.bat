@echo off
title PC Optimizer - PC Specs v4.15
color 0B

:: Read-only. Shows your PC on one page in plain words: processor, memory, graphics card,
:: screens, drives, network and the security features some games need.
:: No serial numbers, MAC addresses or IP addresses are shown. It does not change any setting.
:: Administrator rights are NOT needed (the TPM line is shown more often when you run it as administrator).

if not exist "%~dp0tools\PC_Specs.ps1" goto NOTOOL

echo.
echo   PC Optimizer - PC Specs
echo   Starting PowerShell, please wait a few seconds.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\PC_Specs.ps1" -Root "%~dp0."
echo.
pause
exit /b

:NOTOOL
echo [ERROR] The "tools" folder was not found next to this file.
echo Keep this file in the same folder as 1_Start_Here and the tools folder.
pause
exit /b