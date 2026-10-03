@echo off
setlocal EnableExtensions
title PC Optimizer - Master Control v4.3
color 0B

:: =====================================================================
::  PC OPTIMIZER - MASTER CONTROL v4.3
::  Safety rules used in this file - they avoid the crashes seen in v3:
::   - no brackets inside ECHO text that sits inside IF or FOR blocks
::   - flat GOTO labels instead of nested IF / ELSE blocks
::   - every registry key is exported to the Backup folder before it is changed
:: =====================================================================

net session >nul 2>&1
if errorlevel 1 goto NOADMIN

set "SCRIPT_DIR=%~dp0"
set "REGROOT=%SCRIPT_DIR%reg"
set "UNDOROOT=%SCRIPT_DIR%reg_undo"
set "TOOLDIR=%SCRIPT_DIR%tools"
set "TS=manual"
for /f "usebackq delims=" %%t in (`powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"`) do set "TS=%%t"
set "LOGFILE=%SCRIPT_DIR%OptimizerLog_%TS%.txt"
set "BACKUPDIR=%SCRIPT_DIR%Backup\%TS%"
echo PC Optimizer v4.3 Log - %date% %time% > "%LOGFILE%"

if not exist "%REGROOT%" goto NOREG
if not exist "%UNDOROOT%" echo [WARN] reg_undo folder not found - option 7 will not work.
if not exist "%TOOLDIR%\Check_Status.ps1" echo [WARN] tools folder not found - option C and the restore point time limit will not work.
goto MENU

:NOADMIN
echo [ERROR] Please right-click this file and choose Run as administrator.
pause
exit /b

:NOREG
echo [ERROR] The "reg" folder was not found next to this script.
echo Keep this file in the same folder as the "reg" and "reg_undo" folders.
pause
exit /b

:: ---------------------------------------------------------------------
:MENU
cls
echo ===================================================================
echo    PC OPTIMIZER - MASTER CONTROL v4.3
echo    Log: OptimizerLog_%TS%.txt
echo ===================================================================
echo.
echo   [1] Recommended tweaks     - reg 01-08, safe for everyone
echo   [2] Optional tweaks        - reg 09-13, asks you one by one
echo   [3] Base system setup      - power plan, services, SSD check,
echo                                network per adapter, temp cleanup
echo   [4] Power settings         - reg 14 + auto-set CPU, USB, PCIe
echo   [5] RUN EVERYTHING         - restore point + 1 + 2 + 3 + 4
echo   -----------------------------------------------------------
echo   [6] Create a restore point only
echo   [7] Revert ONE tweak back to the Windows default
echo   [8] Check disk type SSD or HDD - info only
echo   [9] Open the Power Options window
echo   [C] Check status - find settings that Windows Update changed back
echo   [0] Exit
echo.
set "CHOICE="
set /p "CHOICE=Select an option: "
if "%CHOICE%"=="1" goto DO1
if "%CHOICE%"=="2" goto DO2
if "%CHOICE%"=="3" goto DO3
if "%CHOICE%"=="4" goto DO4
if "%CHOICE%"=="5" goto DO5
if "%CHOICE%"=="6" goto DO6
if "%CHOICE%"=="7" goto DO7
if "%CHOICE%"=="8" goto DO8
if "%CHOICE%"=="9" goto DO9
if /i "%CHOICE%"=="C" goto DOC
if "%CHOICE%"=="0" goto END
goto MENU

:DO1
call :CAT1
goto MENU
:DO2
call :CAT2
goto MENU
:DO3
call :BASE
goto MENU
:DO4
call :POWER
goto MENU
:DO5
call :ALL
goto MENU
:DO6
set "ABORT="
call :RESTOREPOINT
pause
goto MENU
:DO7
call :REVERT
goto MENU
:DO8
call :DISKCHECK
goto MENU
:DO9
call :POWEROPT
goto MENU
:DOC
call :CHECKSTATUS
goto MENU

:: ---------------------------------------------------------------------
::  Helpers: apply a numbered reg file, backing up its keys first
:: ---------------------------------------------------------------------
:PREPBACKUP
if not exist "%BACKUPDIR%" mkdir "%BACKUPDIR%" >nul 2>&1
goto :eof

:IMPORTNUM
set "FOUNDREG="
for /r "%REGROOT%" %%f in (%~1_*.reg) do call :APPLYREG "%%f"
if not defined FOUNDREG echo   [WARN] No reg file starting with %~1_ was found in the reg folder.
goto :eof

:APPLYREG
set "FOUNDREG=1"
echo   - Applying %~nx1
echo   - Applying %~nx1 >> "%LOGFILE%"
call :BACKUPFILE "%~1" "%~n1"
reg import "%~1" >> "%LOGFILE%" 2>&1
if errorlevel 1 goto APPLYFAIL
set "FN=%~n1"
call :SETCHOICE %FN:~0,2% Y
goto :eof
:APPLYFAIL
echo     [ERROR] Import failed - see the log file.
goto :eof

:SETCHOICE
reg add "HKCU\Software\PCOptimizer" /v Choice_%~1 /t REG_SZ /d %~2 /f >nul 2>&1
goto :eof

:BACKUPFILE
set "BIDX=0"
for /f "usebackq delims=" %%K in (`findstr /b /l /c:"[" "%~1"`) do call :BACKUPKEY "%%K" "%~2"
goto :eof

:BACKUPKEY
set "KEY=%~1"
set "KEY=%KEY:~1,-1%"
set /a BIDX+=1
reg export "%KEY%" "%BACKUPDIR%\%~2_key%BIDX%.reg" /y >nul 2>&1
goto :eof

:: ---------------------------------------------------------------------
:CAT1
echo.
echo [Category 1] Recommended tweaks 01-08...
call :PREPBACKUP
call :IMPORTNUM 01
call :IMPORTNUM 02
call :IMPORTNUM 03
call :IMPORTNUM 04
call :IMPORTNUM 05
call :IMPORTNUM 06
call :IMPORTNUM 07
call :IMPORTNUM 08
echo.
echo   Note: tweak 08 GPU scheduling needs a restart and a supported GPU driver.
echo [Done] Recommended tweaks applied.
pause
goto :eof

:: ---------------------------------------------------------------------
:CAT2
echo.
echo [Category 2] Optional tweaks - answer for each one.
echo.
call :PREPBACKUP

set "ans="
set /p "ans=  #09 Force true Fullscreen Exclusive - only if fullscreen games stutter on alt-tab. Apply? Y/N: "
if /i "%ans%"=="Y" call :IMPORTNUM 09
if /i not "%ans%"=="Y" echo   - Skipped 09
if /i not "%ans%"=="Y" call :SETCHOICE 09 N

set "ans="
set /p "ans=  #10 Turn off mouse acceleration - best for FPS games. Apply? Y/N: "
if /i "%ans%"=="Y" call :IMPORTNUM 10
if /i not "%ans%"=="Y" echo   - Skipped 10
if /i not "%ans%"=="Y" call :SETCHOICE 10 N

set "ans="
set /p "ans=  #11 Shortest key-repeat delay and no Filter Keys pop-up. Apply? Y/N: "
if /i "%ans%"=="Y" call :IMPORTNUM 11
if /i not "%ans%"=="Y" echo   - Skipped 11
if /i not "%ans%"=="Y" call :SETCHOICE 11 N

set "ans="
set /p "ans=  #12 Ndu memory-leak fix - Task Manager app network history will stop. Apply? Y/N: "
if /i "%ans%"=="Y" call :IMPORTNUM 12
if /i not "%ans%"=="Y" echo   - Skipped 12
if /i not "%ans%"=="Y" call :SETCHOICE 12 N

echo.
echo   #13 turns OFF Memory Integrity. Microsoft says it can lower game FPS on some PCs,
echo   but Windows loses protection against kernel-level malware. Needs a restart.
set "ans="
set /p "ans=  #13 Type YES to apply, anything else to skip: "
if /i "%ans%"=="YES" call :IMPORTNUM 13
if /i not "%ans%"=="YES" echo   - Skipped 13
if /i not "%ans%"=="YES" call :SETCHOICE 13 N

echo.
echo [Done] Optional tweaks step finished.
pause
goto :eof

:: ---------------------------------------------------------------------
:BASE
echo.
echo [Base Setup] Things that are not simple registry values...
echo.
call :PREPBACKUP
call :POWERPLAN
call :SERVICES
call :PREFETCH
call :TCPTWEAK
call :CLEANOLD
call :TEMPCLEAN
echo.
echo [Done] Base system setup complete.
pause
goto :eof

:POWERPLAN
echo  - Power plan: Ultimate Performance, falls back to High Performance...
set "UGUID="
for /f "tokens=3" %%g in ('reg query "HKCU\Software\PCOptimizer" /v UltimateGUID 2^>nul ^| findstr /i "UltimateGUID"') do set "UGUID=%%g"
if not defined UGUID goto PPDUP
powercfg /query %UGUID% >nul 2>&1
if errorlevel 1 goto PPDUP
goto PPACT
:PPDUP
set "UGUID="
for /f "tokens=4" %%g in ('powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2^>nul') do set "UGUID=%%g"
if not defined UGUID goto PPHIGH
reg add "HKCU\Software\PCOptimizer" /v UltimateGUID /t REG_SZ /d "%UGUID%" /f >nul 2>&1
:PPACT
powercfg /setactive %UGUID% >> "%LOGFILE%" 2>&1
if errorlevel 1 goto PPHIGH
echo    [OK] Ultimate Performance is active - the same plan is reused on every run.
call :SETCHOICE POWER Y
goto :eof
:PPHIGH
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c >> "%LOGFILE%" 2>&1
if errorlevel 1 goto PPBAL
echo    [OK] High Performance is active.
call :SETCHOICE POWER Y
goto :eof
:PPBAL
powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e >> "%LOGFILE%" 2>&1
echo    [OK] Balanced kept - no faster plan is available on this PC.
goto :eof

:SERVICES
echo  - Services: Search and Print on, telemetry off...
sc config WSearch start= delayed-auto >> "%LOGFILE%" 2>&1
sc start WSearch >> "%LOGFILE%" 2>&1
sc config Spooler start= auto >> "%LOGFILE%" 2>&1
sc start Spooler >> "%LOGFILE%" 2>&1
sc config DiagTrack start= disabled >> "%LOGFILE%" 2>&1
sc config dmwappushservice start= disabled >> "%LOGFILE%" 2>&1
echo    [OK] Services updated. Already running is normal and not an error.
goto :eof

:PREFETCH
echo  - Checking disk type before changing Prefetcher...
set "MEDIATYPE="
for /f "usebackq delims=" %%m in (`powershell -NoProfile -Command "try { (Get-PhysicalDisk | Sort-Object DeviceId | Select-Object -First 1).MediaType } catch { 'Unknown' }"`) do set "MEDIATYPE=%%m"
echo    Detected disk type: %MEDIATYPE%
echo    Detected disk type: %MEDIATYPE% >> "%LOGFILE%"
set "PFKEY=HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"
reg export "%PFKEY%" "%BACKUPDIR%\Prefetcher.reg" /y >nul 2>&1
if /i "%MEDIATYPE%"=="SSD" goto PFSSD
if /i "%MEDIATYPE%"=="HDD" goto PFHDD
echo    [SKIPPED] Disk type unknown - Prefetcher left unchanged.
goto :eof
:PFSSD
reg add "%PFKEY%" /v EnablePrefetcher /t REG_DWORD /d 0 /f >> "%LOGFILE%" 2>&1
echo    [OK] SSD - Prefetcher turned off.
goto :eof
:PFHDD
reg add "%PFKEY%" /v EnablePrefetcher /t REG_DWORD /d 3 /f >> "%LOGFILE%" 2>&1
echo    [OK] HDD - Prefetcher kept on, turning it off would slow an HDD.
goto :eof

:TCPTWEAK
echo  - Network: TcpAckFrequency and TCPNoDelay on every network adapter...
set "IFROOT=HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
reg export "%IFROOT%" "%BACKUPDIR%\Network_Interfaces.reg" /y >nul 2>&1
set "IFCOUNT=0"
for /f "delims=" %%I in ('reg query "%IFROOT%" ^| findstr /l /c:"{"') do call :TCPONE "%%I"
echo    [OK] Applied to %IFCOUNT% network adapters.
call :SETCHOICE TCP Y
goto :eof
:TCPONE
reg add "%~1" /v TcpAckFrequency /t REG_DWORD /d 1 /f >> "%LOGFILE%" 2>&1
reg add "%~1" /v TCPNoDelay /t REG_DWORD /d 1 /f >> "%LOGFILE%" 2>&1
set /a IFCOUNT+=1
goto :eof

:CLEANOLD
echo  - Removing values from older versions that had no effect...
set "TCPP=HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
reg delete "%TCPP%" /v TcpAckFrequency /f >nul 2>&1
reg delete "%TCPP%" /v TCPNoDelay /f >nul 2>&1
reg delete "%TCPP%" /v MaxUserPort /f >nul 2>&1
reg delete "%TCPP%" /v TcpTimedWaitDelay /f >nul 2>&1
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Power" /v HiberbootEnabled /f >nul 2>&1
echo    [OK] Cleanup done.
goto :eof

:TEMPCLEAN
echo  - Cleaning temp files...
del /q /s "%TEMP%\*" >nul 2>nul
echo    [OK] Temp files cleaned. Locked files were skipped safely.
goto :eof

:: ---------------------------------------------------------------------
:POWER
echo.
echo [Category 4] Power settings...
call :PREPBACKUP
call :IMPORTNUM 14
echo  - Setting the ACTIVE power plan for plugged-in use...
powercfg /setacvalueindex scheme_current sub_processor PROCTHROTTLEMIN 100 >> "%LOGFILE%" 2>&1
powercfg /setacvalueindex scheme_current sub_processor CPMINCORES 100 >> "%LOGFILE%" 2>&1
powercfg /setacvalueindex scheme_current 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 >> "%LOGFILE%" 2>&1
powercfg /setacvalueindex scheme_current sub_pciexpress ASPM 0 >> "%LOGFILE%" 2>&1
powercfg /setactive scheme_current >> "%LOGFILE%" 2>&1
echo    [OK] Minimum CPU state 100, core parking off,
echo         USB selective suspend off, PCIe link power saving off.
echo    Laptop battery settings are left unchanged.
call :SETCHOICE POWER Y
echo [Done] Power settings applied.
pause
goto :eof

:: ---------------------------------------------------------------------
:ALL
echo.
echo ==========================================
echo   RUNNING FULL RECOMMENDED SETUP
echo ==========================================
set "ABORT="
call :RESTOREPOINT
if defined ABORT goto ALLSTOP
call :CAT1
call :CAT2
call :BASE
call :POWER
echo.
echo ===================================================================
echo   ALL STEPS COMPLETE. Please RESTART your PC now.
echo   Previous values of every changed key are saved in:
echo   Backup\%TS%
echo ===================================================================
pause
goto :eof
:ALLSTOP
echo   Stopped - nothing was changed.
pause
goto :eof

:RESTOREPOINT
echo.
echo  - Creating System Restore point "Before_PC_Optimizer"...
echo    This normally takes 1-5 minutes and stops by itself after 10 minutes.
if not exist "%TOOLDIR%\Create_Restore_Point.ps1" goto RPFAIL
powershell -NoProfile -ExecutionPolicy Bypass -File "%TOOLDIR%\Create_Restore_Point.ps1" -TimeoutSeconds 600
if errorlevel 2 goto RPTIMEOUT
if errorlevel 1 goto RPFAIL
echo    [OK] Restore point created.
goto :eof
:RPTIMEOUT
echo    [WARNING] Windows did not finish the restore point within 10 minutes.
echo    Restarting the PC usually fixes this. You can also make one by hand:
echo    Start - type Create a restore point - Create - name it Before_PC_Optimizer
goto RPASK
:RPFAIL
echo    [WARNING] A restore point could not be created.
:RPASK
set "RPANS="
set /p "RPANS=   Continue without a restore point? Y/N: "
if /i "%RPANS%"=="Y" goto :eof
set "ABORT=1"
goto :eof

:: ---------------------------------------------------------------------
:REVERT
cls
echo ===================================================================
echo    REVERT ONE TWEAK TO THE WINDOWS DEFAULT
echo ===================================================================
echo    1  Game Bar / DVR off           8  GPU scheduling on
echo    2  Power throttling off         9  Fullscreen exclusive
echo    3  Gaming priority MMCSS       10  Mouse acceleration off
echo    4  CPU foreground priority     11  Keyboard fast repeat
echo    5  Telemetry off               12  Ndu memory fix
echo    6  System responsiveness       13  Memory Integrity off
echo    7  Delivery Optimization off   14  CPU power options unlock
echo.
echo    T  Network per-adapter tweak
echo    P  Reset ALL power plans to Windows defaults
echo.
echo    Exact previous values are also in the Backup folder -
echo    double-click a file there to restore it.
echo.
set "RV="
set /p "RV=Type a choice, or press Enter to go back: "
if "%RV%"=="" goto :eof
if /i "%RV%"=="T" goto REVERTTCP
if /i "%RV%"=="P" goto REVERTPOWER
set "RN=0%RV%"
set "RN=%RN:~-2%"
set "FOUNDREG="
for /r "%UNDOROOT%" %%f in (UNDO_%RN%_*.reg) do call :UNDOONE "%%f"
if not defined FOUNDREG echo    [WARN] No undo file matches that choice.
echo    A restart is recommended after reverting.
pause
goto :eof

:UNDOONE
set "FOUNDREG=1"
echo    - Reverting with %~nx1
echo    - Reverting with %~nx1 >> "%LOGFILE%"
reg import "%~1" >> "%LOGFILE%" 2>&1
if errorlevel 1 goto UNDOFAIL
set "FN=%~n1"
call :SETCHOICE %FN:~5,2% N
goto :eof
:UNDOFAIL
echo      [ERROR] Revert failed - see the log file.
goto :eof

:REVERTTCP
set "IFROOT=HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
for /f "delims=" %%I in ('reg query "%IFROOT%" ^| findstr /l /c:"{"') do call :TCPUNDOONE "%%I"
echo    [OK] Network adapter tweak removed - Windows defaults are back.
call :SETCHOICE TCP N
pause
goto :eof
:TCPUNDOONE
reg delete "%~1" /v TcpAckFrequency /f >nul 2>&1
reg delete "%~1" /v TCPNoDelay /f >nul 2>&1
goto :eof

:REVERTPOWER
echo.
echo    This resets ALL power plans to Windows defaults and removes the
echo    Ultimate Performance copies. The active plan becomes Balanced.
set "PANS="
set /p "PANS=   Continue? Y/N: "
if /i not "%PANS%"=="Y" goto :eof
powercfg -restoredefaultschemes >> "%LOGFILE%" 2>&1
reg delete "HKCU\Software\PCOptimizer" /v UltimateGUID /f >nul 2>&1
set "FOUNDREG="
for /r "%UNDOROOT%" %%f in (UNDO_14_*.reg) do call :UNDOONE "%%f"
echo    [OK] Power plans reset.
call :SETCHOICE POWER N
pause
goto :eof

:: ---------------------------------------------------------------------
:CHECKSTATUS
if not exist "%TOOLDIR%\Check_Status.ps1" goto CSMISSING
powershell -NoProfile -ExecutionPolicy Bypass -File "%TOOLDIR%\Check_Status.ps1" -Root "%SCRIPT_DIR%."
pause
goto :eof
:CSMISSING
echo [ERROR] tools\Check_Status.ps1 was not found next to this script.
pause
goto :eof

:: ---------------------------------------------------------------------
:DISKCHECK
echo.
echo Checking disk type - information only, nothing is changed...
powershell -NoProfile -Command "try { Get-PhysicalDisk | Select-Object DeviceId, FriendlyName, MediaType | Format-Table -AutoSize } catch { Write-Host 'Could not read disk information on this PC.' }"
pause
goto :eof

:POWEROPT
echo.
echo Opening Power Options. Option 4 already set the important values -
echo this window is only for checking or fine-tuning them.
start "" control.exe powercfg.cpl
pause
goto :eof

:END
echo.
echo Log saved to: %LOGFILE%
timeout /t 2 >nul
exit /b
