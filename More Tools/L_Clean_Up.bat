@echo off
title PC Optimizer - Clean Up v4.22
color 0B
for %%I in ("%~dp0..") do set "ROOTDIR=%%~fI"

:: Shows the Logs and Backup folders and removes old files only when you choose.
:: Reports: the newest few of each kind are kept automatically (you can change the number).
:: Backups: older ones are listed with their size and removed only after you say yes.
:: Administrator rights are NOT needed.

if not exist "%ROOTDIR%\tools\Clean_Up.ps1" goto NOTOOL

echo.
echo   PC Optimizer - Clean Up
echo   Starting PowerShell, please wait a few seconds.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOTDIR%\tools\Clean_Up.ps1" -Root "%ROOTDIR%\."
echo.
pause
exit /b

:NOTOOL
echo [ERROR] The "tools" folder was not found next to the "More Tools" folder.
echo Keep this file in the "More Tools" folder, inside the folder that has 1_Start_Here and the tools folder.
pause
exit /b