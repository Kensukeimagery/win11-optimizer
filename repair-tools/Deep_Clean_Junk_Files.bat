@echo off
cls
title Deep Disk Cleaner v2 (Auto-Configured + Space Report)
echo ==================================================
echo          Deep Disk Cleaner (Automated) v2
echo    Auto-select ALL cleanup options and Deep Clean
echo ==================================================
echo.

:: 1. Check Admin rights (needed to edit Registry)
net session >nul 2>&1
if %errorLevel% == 0 (
    echo [OK] Admin rights confirmed.
) else (
    echo [ERROR] Please Run as Administrator!
    pause
    exit
)

echo.
echo [1/5] Checking current free space on C: ...
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "[math]::Round((Get-PSDrive C).Free/1MB)"`) do set "FREEBEFORE=%%a"
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "[math]::Round(((Get-PSDrive C).Used+(Get-PSDrive C).Free)/1MB)"`) do set "TOTALMB=%%a"
set /a FREEPCTBEFORE=FREEBEFORE*100/TOTALMB
echo    Free space now: %FREEBEFORE% MB free of %TOTALMB% MB (about %FREEPCTBEFORE%%% free)

echo.
echo [2/5] Configuring cleanup settings...
:: Loop to auto-check every Disk Cleanup category (saved as Profile #50)
for /f "tokens=*" %%a in ('reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"') do (
    reg add "%%a" /v StateFlags0050 /t REG_DWORD /d 2 /f >nul 2>&1
)
echo [OK] All cleanup categories selected (Profile #50).

echo.
echo [3/5] Running Deep Clean (this may take a while, please wait)...
:: Run Disk Cleanup using Profile #50 we just configured
cleanmgr.exe /sagerun:50

echo.
echo [4/5] Clearing leftover Temp files that Disk Cleanup sometimes misses...
del /q /s "%TEMP%\*" >nul 2>nul
del /q /s "%WINDIR%\Temp\*" >nul 2>nul
echo    [OK] Done (locked/in-use files were safely skipped).

echo.
echo [5/5] Checking free space after cleanup...
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "[math]::Round((Get-PSDrive C).Free/1MB)"`) do set "FREEAFTER=%%a"
set /a FREEPCTAFTER=FREEAFTER*100/TOTALMB
set /a FREEDMB=FREEAFTER-FREEBEFORE
if %FREEDMB% LSS 0 set FREEDMB=0
echo    Free space now: %FREEAFTER% MB free of %TOTALMB% MB (about %FREEPCTAFTER%%% free)
echo    Freed approximately %FREEDMB% MB

if %FREEPCTAFTER% LSS 15 echo    [NOTE] Still under 15%% free space. Consider moving large files ^(videos, game installs^) to another drive.
if %FREEPCTAFTER% GEQ 15 echo    [OK] Free space is at a healthy level ^(15%% or more^).

echo.
echo ==================================================
echo    CLEANUP COMPLETE!
echo    You can close this window.
echo ==================================================
pause
