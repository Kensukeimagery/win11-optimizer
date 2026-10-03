@echo off
cls
title System File Scan & Repair v2 (SFC + DISM)
echo ==================================================
echo    System File Scan and Repair v2
echo    This can take 15-40 minutes total. Please be
echo    patient and do not close this window.
echo ==================================================
echo.

:: 1. Check Admin rights
net session >nul 2>&1
if %errorLevel% == 0 (
    echo [OK] Admin rights confirmed.
) else (
    echo [ERROR] Please Run as Administrator!
    pause
    exit
)

:: NOTE ON ORDER: DISM repairs the underlying Windows component store
:: (WinSxS). SFC then uses that same store to fix system files. Running
:: DISM before SFC (this order) is Microsoft's own recommended sequence -
:: the previous version of this script ran them the other way around.

echo.
echo [1/4] Running DISM ScanHealth (quick check, ~2-5 min)...
DISM /Online /Cleanup-Image /ScanHealth

echo.
echo [2/4] Running DISM CheckHealth (quick check)...
DISM /Online /Cleanup-Image /CheckHealth

echo.
echo [3/4] Running DISM RestoreHealth (the actual repair, ~10-20 min)...
DISM /Online /Cleanup-Image /RestoreHealth

echo.
echo [4/4] Running SFC scan (~10-15 min)...
sfc /scannow

echo.
echo ==================================================
echo    CORE REPAIR STEPS FINISHED.
echo ==================================================
echo.
echo One more OPTIONAL step is available: StartComponentCleanup /ResetBase.
echo This permanently deletes old Windows Update backup files to free up
echo disk space (can be several GB) - but afterwards you can NO LONGER
echo uninstall any Windows updates that were installed before now.
echo This cannot be undone.
echo.
set /p RESETBASE="Run this optional cleanup step too? (Y/N): "
if /i "%RESETBASE%"=="Y" (
    echo.
    echo Running DISM StartComponentCleanup /ResetBase, please wait...
    DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase
)
if /i not "%RESETBASE%"=="Y" echo Skipped the optional cleanup step.

echo.
echo ==================================================
echo    ALL DONE! You can close this window.
echo    A restart is recommended to finish applying repairs.
echo ==================================================
pause
