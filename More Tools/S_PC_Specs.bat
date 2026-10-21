@echo off
title PC Optimizer - PC Specs v4.29
color 0B
for %%I in ("%~dp0..") do set "ROOTDIR=%%~fI"

:: Read-only. Shows your PC on one page in plain words: processor, memory, graphics card,
:: screens, drives, network and the security features some games need.
:: No serial numbers, MAC addresses or IP addresses are shown. It does not change any setting.
:: Administrator rights are NOT needed (the TPM line is shown more often when you run it as administrator).

if not exist "%ROOTDIR%\tools\PC_Specs.ps1" goto NOTOOL

echo.
echo   PC Optimizer - PC Specs
echo   Starting PowerShell, please wait a few seconds.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOTDIR%\tools\PC_Specs.ps1" -Root "%ROOTDIR%\."
echo.
pause
exit /b

:NOTOOL
echo [ERROR] The "tools" folder was not found next to the "More Tools" folder.
echo Keep this file in the "More Tools" folder, inside the folder that has 1_Start_Here and the tools folder.
pause
exit /b