@echo off
title PC Optimizer - VM test suite
color 0B

:: Runs the VM test suite. Use it INSIDE the virtual machine only: right-click, Run as administrator.
:: It copies this folder to C:\PCOpt_Test first (a fresh copy every time, this folder stays untouched), then runs the tests there.
:: Options are passed on: add -SkipEasyFull to skip the long real Easy Setup run.

net session >nul 2>&1
if errorlevel 1 (
    echo.
    echo   Run this file as administrator: right-click it and choose Run as administrator.
    echo.
    pause
    exit /b 1
)

set "SRC=%~dp0"
set "DST=C:\PCOpt_Test"
echo.
echo   Copying the test edition to %DST% ...
robocopy "%SRC%." "%DST%" /MIR /XD Logs Backup _reports /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 (
    echo   The copy failed.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%DST%\VM_TEST\vm_tests.ps1" %*
echo.
pause
