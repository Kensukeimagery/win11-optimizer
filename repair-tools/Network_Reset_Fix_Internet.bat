@echo off
cls
title Ultimate Network Fix v2 (Clean Version)
echo ==================================================
echo         Ultimate Network Optimizer v2
echo    Fix Download Speed, Reduce Ping, Reset DNS
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
echo [1/6] Resetting Network Protocols (IPv4 + IPv6)...
:: Reset Network Adapter settings back to default
netsh winsock reset
netsh int ip reset
netsh int ipv6 reset

echo.
echo [2/6] Releasing and Renewing IP Address...
:: Drops and re-requests an IP address from the router/DHCP server
ipconfig /release
ipconfig /renew

echo.
echo [3/6] Flushing and Renewing DNS...
:: Clear stale DNS records
ipconfig /flushdns
ipconfig /registerdns

echo.
echo [4/6] Optimizing TCP for High Speed Downloads...
:: Enable Auto-Tuning (important for fast connections)
netsh int tcp set global autotuninglevel=normal
:: Enable RSS so multiple CPU cores can help process network traffic
netsh int tcp set global rss=enabled

echo.
echo [5/6] Finalizing (Clearing ARP Cache)...
:: Clear the ARP cache using the modern command
netsh interface ip delete arpcache

echo.
echo [6/6] Verifying connection...
ping -n 2 8.8.8.8 >nul 2>&1
if %errorLevel% == 0 (
    echo    [OK] Internet connection responded successfully.
) else (
    echo    [NOTE] Could not reach the internet yet - this is normal right
    echo    after a reset. Restart your PC, then check your connection again.
)

echo.
echo ==================================================
echo    NETWORK OPTIMIZATION COMPLETE!
echo    YOU MUST RESTART YOUR PC NOW.
echo ==================================================
echo.
pause
