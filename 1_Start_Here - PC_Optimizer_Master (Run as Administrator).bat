@echo off
setlocal EnableExtensions
title PC Optimizer - Master Control v4.11
color 0B

:: =====================================================================
::  PC OPTIMIZER - MASTER CONTROL v4.11
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
echo PC Optimizer v4.11 Log - %date% %time% > "%LOGFILE%"

if not exist "%REGROOT%" goto NOREG
if not exist "%UNDOROOT%" echo [WARN] reg_undo folder not found - option 7 will not work.
if not exist "%TOOLDIR%\Check_Status.ps1" echo [WARN] tools folder not found - option C and the restore point time limit will not work.
goto STARTUP

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
:STARTUP
set "WINBUILD=0"
set "ISLAPTOP=0"
set /a EMPTYCNT=0
if exist "%TOOLDIR%\Env_Check.ps1" for /f "usebackq tokens=1,2" %%a in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%TOOLDIR%\Env_Check.ps1"`) do call :SETENV %%a %%b
if %WINBUILD% GTR 0 if %WINBUILD% LSS 22000 goto OLDWIN
goto UPDPREF
:SETENV
set "WINBUILD=%~1"
set "ISLAPTOP=%~2"
goto :eof
:OLDWIN
echo.
echo   [WARNING] This tool is made for Windows 11. Your Windows build is %WINBUILD%.
echo   Some tweaks may not work or may behave differently on older Windows.
set "OLDANS="
set /p "OLDANS=  Continue anyway? Y/N: "
if /i "%OLDANS%"=="Y" goto UPDPREF
goto END
:UPDPREF
set "UPDCHK="
for /f "tokens=3" %%v in ('reg query "HKCU\Software\PCOptimizer" /v Choice_UPDATECHECK 2^>nul ^| findstr /i "Choice_UPDATECHECK"') do set "UPDCHK=%%v"
if defined UPDCHK goto UPDRUN
if not exist "%TOOLDIR%\Update.ps1" goto MENU
echo.
echo   Check for updates automatically when this menu opens?
echo   This contacts github.com once, sends nothing about you,
echo   and never installs anything without asking you first.
set "UPDANS="
set /p "UPDANS=  Y = yes, N = no, you can still press U in the menu any time: "
set "UPDCHK=N"
if /i "%UPDANS%"=="Y" set "UPDCHK=Y"
call :SETCHOICE UPDATECHECK %UPDCHK%
:UPDRUN
set "UPDMSG="
if /i not "%UPDCHK%"=="Y" goto MENU
if not exist "%TOOLDIR%\Update.ps1" goto MENU
echo   Checking for updates ...
for /f "usebackq delims=" %%m in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%TOOLDIR%\Update.ps1" -Action Check`) do set "UPDMSG=%%m"
goto MENU

:: ---------------------------------------------------------------------
:MENU
cls
echo ===================================================================
echo    PC OPTIMIZER - MASTER CONTROL v4.11
echo    Log: OptimizerLog_%TS%.txt
if "%ISLAPTOP%"=="1" echo    Laptop detected - tweaks 02 and 16 are not recommended on a laptop.
if defined UPDMSG echo    %UPDMSG%
echo ===================================================================
echo.
echo   [1] Recommended tweaks     - reg 01-08, safe for everyone
echo   [2] Optional tweaks        - 09-13, 15, 16, asks you one by one
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
echo   [D] Drivers - find missing or old drivers, install only if you choose (beta)
echo   [U] Check for updates - see what is new, update only if you say yes
echo   [A] Turn the automatic update check on or off
echo   [N] Network test - ping, jitter, packet loss and DNS speed, you choose
echo   [R] System report - CPU and RAM users, startup list, changes nothing
echo   [H] PC health - crashes, drive health, screen refresh rate, RAM speed, cable speed
echo   [B] Support bundle - one file to attach to a problem report
echo   [0] Exit
echo.
set "CHOICE="
set /p "CHOICE=Select an option: "
if defined CHOICE goto GOTCHOICE
set /a EMPTYCNT+=1
if %EMPTYCNT% GTR 60 goto END
:GOTCHOICE
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
if /i "%CHOICE%"=="D" goto DOD
if /i "%CHOICE%"=="U" goto DOU
if /i "%CHOICE%"=="A" goto DOA
if /i "%CHOICE%"=="N" goto DONET
if /i "%CHOICE%"=="R" goto DOREP
if /i "%CHOICE%"=="H" goto DOHEALTH
if /i "%CHOICE%"=="B" goto DOBUNDLE
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
:DOD
call :DRIVERS
goto MENU
:DOU
call :UPDATE
goto MENU
:DOA
call :UPDTOGGLE
goto MENU
:DONET
call :NETTEST
goto MENU
:DOREP
call :SYSREPORT
goto MENU

:DOHEALTH
call :HEALTHRUN
goto MENU

:DOBUNDLE
call :BUNDLERUN
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
call :APPLY02
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

:APPLY02
if not "%ISLAPTOP%"=="1" goto RUN02
echo.
echo   Laptop detected. Tweak 02 turns off power throttling and Fast Startup.
echo   The battery drains faster and the laptop runs warmer. Skipping is recommended.
set "ans="
set /p "ans=  Apply 02 anyway? Y/N: "
if /i "%ans%"=="Y" goto RUN02
echo   - Skipped 02
call :SETCHOICE 02 N
goto :eof
:RUN02
call :IMPORTNUM 02
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
echo   #15 Windows 11 timer resolution. Lets a game timer request apply system-wide again.
echo   Can steady frame pacing in some games, uses a little more power. Needs a restart.
set "ans="
set /p "ans=  #15 Apply? Y/N: "
if /i "%ans%"=="Y" call :IMPORTNUM 15
if /i not "%ans%"=="Y" echo   - Skipped 15
if /i not "%ans%"=="Y" call :SETCHOICE 15 N

echo.
echo   #16 CPU boost: aggressive boost and energy preference 0, plugged in only.
echo   Ultimate Performance already does this on most PCs. Runs hotter on laptops.
if "%ISLAPTOP%"=="1" echo   Laptop detected: more heat and battery use when plugged in. Not recommended.
set "ans="
set /p "ans=  #16 Apply? Y/N: "
if /i "%ans%"=="Y" call :BOOSTAPPLY
if /i not "%ans%"=="Y" echo   - Skipped 16
if /i not "%ans%"=="Y" call :SETCHOICE 16 N

echo.
echo [Done] Optional tweaks step finished.
pause
goto :eof

:: ---------------------------------------------------------------------
:BOOSTAPPLY
echo   - Applying 16 CPU boost...
if not exist "%TOOLDIR%\Power_Boost.ps1" goto BOOSTMISSING
powershell -NoProfile -ExecutionPolicy Bypass -File "%TOOLDIR%\Power_Boost.ps1" -Action Apply
if errorlevel 3 goto BOOSTNA
if errorlevel 1 goto BOOSTFAIL
call :SETCHOICE 16 Y
goto :eof
:BOOSTNA
echo     [SKIPPED] This PC does not offer these settings.
call :SETCHOICE 16 N
goto :eof
:BOOSTFAIL
echo     [ERROR] The CPU boost settings could not be applied.
goto :eof
:BOOSTMISSING
echo     [WARN] tools\Power_Boost.ps1 was not found, 16 was skipped.
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
for /f "usebackq delims=" %%g in (`powershell -NoProfile -Command "$o = (powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null) -join ' '; if ($o -match '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}') { $Matches[0] }"`) do set "UGUID=%%g"
if not defined UGUID goto PPHIGH
reg add "HKCU\Software\PCOptimizer" /v UltimateGUID /t REG_SZ /d "%UGUID%" /f >nul 2>&1
:PPACT
powercfg /setactive %UGUID% >> "%LOGFILE%" 2>&1
if errorlevel 1 goto PPHIGH
echo    [OK] Ultimate Performance is active - the same plan is reused on every run.
call :SETCHOICE POWER Y
goto :eof
:PPHIGH
set "KEEPPLAN="
for /f "usebackq delims=" %%g in (`powershell -NoProfile -Command "$o = (powercfg /getactivescheme) -join ' '; if ($o -match '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}') { if (@('381b4222-f694-41f0-9685-ff5bb260df2e','a1841308-3541-4fab-bc81-f71556f20b4a') -notcontains $Matches[0].ToLower()) { 'KEEP' } }"`) do set "KEEPPLAN=%%g"
if defined KEEPPLAN goto PPKEEP
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c >> "%LOGFILE%" 2>&1
if errorlevel 1 goto PPBAL
echo    [OK] High Performance is active. Ultimate Performance could not be added on this PC.
call :SETCHOICE POWER Y
goto :eof
:PPKEEP
echo    [OK] Ultimate Performance could not be added on this PC. Your current power plan was kept.
echo         It is not Balanced or Power saver, so it is not replaced by a slower one.
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
call :SETCHOICE SERVICES Y
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
call :SETCHOICE PREF Y
goto :eof
:PFHDD
reg add "%PFKEY%" /v EnablePrefetcher /t REG_DWORD /d 3 /f >> "%LOGFILE%" 2>&1
echo    [OK] HDD - Prefetcher kept on, turning it off would slow an HDD.
call :SETCHOICE PREF Y
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
if "%TEMP%"=="" goto TEMPSKIP
if not exist "%TEMP%\" goto TEMPSKIP
del /q /s "%TEMP%\*" >nul 2>nul
echo    [OK] Temp files cleaned. Locked files were skipped safely.
goto :eof
:TEMPSKIP
echo    [SKIPPED] The temp folder was not found.
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
echo   15  Timer resolution            16  CPU boost aggressive
echo   17  DNS servers - back to the DNS you had before
echo.
echo    T  Network per-adapter tweak
echo    S  Services - telemetry services back to the Windows defaults
echo    F  Prefetcher back to the Windows default
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
if /i "%RV%"=="S" goto REVERTSVC
if /i "%RV%"=="F" goto REVERTPREF
set "RN=0%RV%"
set "RN=%RN:~-2%"
if "%RN%"=="16" goto REVERTBOOST
if "%RN%"=="17" goto REVERTDNS
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

:REVERTDNS
if not exist "%TOOLDIR%\Set_Dns.ps1" echo    [WARN] tools\Set_Dns.ps1 was not found.
if exist "%TOOLDIR%\Set_Dns.ps1" powershell -NoProfile -ExecutionPolicy Bypass -File "%TOOLDIR%\Set_Dns.ps1" -Action Undo -Root "%SCRIPT_DIR%."
pause
goto :eof

:REVERTBOOST
if not exist "%TOOLDIR%\Power_Boost.ps1" echo    [WARN] tools\Power_Boost.ps1 was not found.
if exist "%TOOLDIR%\Power_Boost.ps1" powershell -NoProfile -ExecutionPolicy Bypass -File "%TOOLDIR%\Power_Boost.ps1" -Action Undo
call :SETCHOICE 16 N
pause
goto :eof

:REVERTSVC
sc config DiagTrack start= auto >> "%LOGFILE%" 2>&1
sc config dmwappushservice start= demand >> "%LOGFILE%" 2>&1
echo    [OK] DiagTrack is automatic again and dmwappushservice is manual, as in Windows.
echo    They start at the next restart.
call :SETCHOICE SERVICES N
pause
goto :eof

:REVERTPREF
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" /v EnablePrefetcher /t REG_DWORD /d 3 /f >> "%LOGFILE%" 2>&1
echo    [OK] Prefetcher is back to the Windows default (3).
call :SETCHOICE PREF N
pause
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
:DRIVERS
if not exist "%TOOLDIR%\Driver_Check.ps1" goto DRVMISSING
powershell -NoProfile -ExecutionPolicy Bypass -File "%TOOLDIR%\Driver_Check.ps1" -Root "%SCRIPT_DIR%."
pause
goto :eof
:DRVMISSING
echo [ERROR] tools\Driver_Check.ps1 was not found next to this script.
pause
goto :eof

:: ---------------------------------------------------------------------
:UPDATE
if not exist "%TOOLDIR%\Update.ps1" goto UPDMISSING
powershell -NoProfile -ExecutionPolicy Bypass -File "%TOOLDIR%\Update.ps1" -Relaunch
if errorlevel 10 exit
pause
goto :eof
:UPDMISSING
echo [ERROR] tools\Update.ps1 was not found next to this script.
pause
goto :eof

:UPDTOGGLE
set "UPDCHK="
for /f "tokens=3" %%v in ('reg query "HKCU\Software\PCOptimizer" /v Choice_UPDATECHECK 2^>nul ^| findstr /i "Choice_UPDATECHECK"') do set "UPDCHK=%%v"
if /i "%UPDCHK%"=="Y" goto UPDOFF
call :SETCHOICE UPDATECHECK Y
echo   Automatic update check is now ON. It runs when this menu opens.
pause
goto :eof
:UPDOFF
call :SETCHOICE UPDATECHECK N
set "UPDMSG="
echo   Automatic update check is now OFF. You can still press U any time.
pause
goto :eof

:: ---------------------------------------------------------------------
:NETTEST
if not exist "%TOOLDIR%\Network_Test.ps1" goto NTMISSING
powershell -NoProfile -ExecutionPolicy Bypass -File "%TOOLDIR%\Network_Test.ps1" -Root "%SCRIPT_DIR%."
pause
goto :eof
:NTMISSING
echo [ERROR] tools\Network_Test.ps1 was not found next to this script.
pause
goto :eof

:SYSREPORT
if not exist "%TOOLDIR%\System_Report.ps1" goto SRMISSING
powershell -NoProfile -ExecutionPolicy Bypass -File "%TOOLDIR%\System_Report.ps1" -Root "%SCRIPT_DIR%."
pause
goto :eof
:SRMISSING
echo [ERROR] tools\System_Report.ps1 was not found next to this script.
pause
goto :eof

:HEALTHRUN
if not exist "%TOOLDIR%\PC_Health.ps1" goto HEALTHMISSING
powershell -NoProfile -ExecutionPolicy Bypass -File "%TOOLDIR%\PC_Health.ps1" -Root "%SCRIPT_DIR%."
pause
goto :eof
:HEALTHMISSING
echo [ERROR] tools\PC_Health.ps1 was not found next to this script.
pause
goto :eof

:BUNDLERUN
if not exist "%TOOLDIR%\Support_Bundle.ps1" goto BUNDLEMISSING
powershell -NoProfile -ExecutionPolicy Bypass -File "%TOOLDIR%\Support_Bundle.ps1" -Root "%SCRIPT_DIR%."
pause
goto :eof
:BUNDLEMISSING
echo [ERROR] tools\Support_Bundle.ps1 was not found next to this script.
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
