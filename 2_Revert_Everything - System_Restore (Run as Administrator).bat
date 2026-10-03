@echo off
title Revert Everything - System Restore
color 0C
cls
echo ===================================================================
echo   REVERT EVERYTHING WITH SYSTEM RESTORE
echo   Rolls the WHOLE PC back to the restore point "Before_PC_Optimizer"
echo   that the Master script creates in option 5 or option 6.
echo   Every tweak is undone - and so is anything else changed after
echo   that point, such as programs installed later.
echo.
echo   To undo only ONE tweak, use option 7 in the Master script instead.
echo ===================================================================
echo.
echo   Your PC WILL RESTART automatically once you confirm.
echo   Save any open work now.
echo.

net session >nul 2>&1
if errorlevel 1 goto NOADMIN

set "CONFIRM="
set /p "CONFIRM=Type YES to continue, anything else to cancel: "
if /i not "%CONFIRM%"=="YES" goto CANCEL

echo.
echo Looking for the "Before_PC_Optimizer" restore point...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$rp = Get-ComputerRestorePoint | Where-Object { $_.Description -eq 'Before_PC_Optimizer' } | Sort-Object SequenceNumber -Descending | Select-Object -First 1; if (-not $rp) { Write-Host 'No restore point named Before_PC_Optimizer was found.'; exit 1 } else { Write-Host ('Found restore point number ' + $rp.SequenceNumber + ' created ' + $rp.CreationTime); Restore-Computer -RestorePoint $rp.SequenceNumber -Confirm:$false }"
if errorlevel 1 goto MANUAL
pause
exit /b

:MANUAL
echo.
echo The automatic restore could not start. Opening System Restore -
echo pick "Before_PC_Optimizer" from the list yourself.
rstrui.exe
pause
exit /b

:CANCEL
echo Cancelled. Nothing was changed.
pause
exit /b

:NOADMIN
echo [ERROR] Please right-click this file and choose Run as administrator.
pause
exit /b
