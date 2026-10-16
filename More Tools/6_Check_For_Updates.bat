@echo off
title PC Optimizer - Check For Updates v4.23
color 0B
for %%I in ("%~dp0..") do set "ROOTDIR=%%~fI"

:: Looks for a newer version on GitHub. It only installs one if you say yes,
:: saves the old version first, and never touches your Backup folder or reports.
:: Administrator rights are NOT needed.

if not exist "%ROOTDIR%\tools\Update.ps1" goto NOTOOL

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOTDIR%\tools\Update.ps1"
if errorlevel 10 exit
echo.
pause
exit /b

:NOTOOL
echo [ERROR] The "tools" folder was not found next to the "More Tools" folder.
echo Keep this file in the "More Tools" folder, inside the folder that has 1_Start_Here and the tools folder.
pause
exit /b