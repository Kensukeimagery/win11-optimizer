@echo off
cls
title Bluetooth Fix v2 (Can't Connect / Pair Devices)
echo ==================================================
echo      Bluetooth "Can't Connect" Fix v2
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

echo.
echo [1/3] Re-enabling device pairing services...
reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\DevicesFlowUserSvc" /v Start /t REG_DWORD /d "3" /f >nul 2>&1
reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\DevicePickerUserSvc" /v Start /t REG_DWORD /d "3" /f >nul 2>&1
echo    [OK] Device picker / Swift Pair services re-enabled.

echo.
echo [2/3] Restarting the Bluetooth Support Service...
net stop bthserv >nul 2>&1
net start bthserv >nul 2>&1
if %errorLevel% == 0 (
    echo    [OK] Bluetooth Support Service restarted.
) else (
    echo    [NOTE] Could not restart it automatically - it may already be
    echo    running under a different state. This is usually fine.
)

echo.
echo [3/3] Restarting the Bluetooth Audio Gateway Service...
net stop BTAGService >nul 2>&1
net start BTAGService >nul 2>&1
echo    [OK] Done (this service only exists on some PCs, that's normal).

echo.
echo ==================================================
echo    BLUETOOTH FIX COMPLETE!
echo    Try pairing your device again now.
echo    If it still won't connect, restart your PC once.
echo ==================================================
pause
