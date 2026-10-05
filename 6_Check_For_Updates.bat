@echo off
title PC Optimizer - Check For Updates v4.11
color 0B

:: Looks for a newer version on GitHub. It only installs one if you say yes,
:: saves the old version first, and never touches your Backup folder or reports.
:: Administrator rights are NOT needed.

if not exist "%~dp0tools\Update.ps1" goto NOTOOL

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Update.ps1"
if errorlevel 10 exit
echo.
pause
exit /b

:NOTOOL
echo [ERROR] The "tools" folder was not found next to this file.
echo Keep this file in the same folder as 1_Start_Here and the tools folder.
pause
exit /b