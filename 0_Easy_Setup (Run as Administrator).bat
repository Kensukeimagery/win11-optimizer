@echo off
title PC Optimizer - Easy Setup v4.18
color 0B
chcp 65001 >nul 2>&1

:: ONE BUTTON for a new Windows install, for first-time users and for people who do not know computers.
:: It asks for the language (Thai or English), shows the plan, and then does everything in the best order:
:: restore point, drivers, Windows Update (guided), safe speed settings, and a one-page summary.
:: It must run as administrator. Nothing is deleted. Every change can be undone.

net session >nul 2>&1
if errorlevel 1 goto NOADMIN
if not exist "%~dp0tools\Easy_Setup.ps1" goto NOTOOL

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Easy_Setup.ps1" -Root "%~dp0."
echo.
pause
exit /b

:NOADMIN
echo.
echo   Easy Setup must run as administrator.
echo   Close this window, right-click this file, and choose Run as administrator.
echo.
pause
exit /b

:NOTOOL
echo [ERROR] The "tools" folder was not found next to this file.
echo Keep this file in the same folder as 1_Start_Here and the tools folder.
pause
exit /b