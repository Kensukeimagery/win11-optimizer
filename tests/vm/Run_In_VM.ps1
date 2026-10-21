# Runs the VM test suite inside a VirtualBox virtual machine from the host, and brings the report back.
#   powershell -File tests\vm\Run_In_VM.ps1 [-Vm "test win11"] [-Snapshot "02 clean Windows, UAC prompt off"] [-Edition E:\win11-optimizer-vm-test] [-SkipEasyFull]
# What it does: restore the snapshot (cold boot), wait for Guest Additions, copy the VM test edition into the VM, start the suite
# elevated (needs "ConsentPromptBehaviorAdmin = 0" in the VM, which the snapshot above has), wait for the summary, copy the reports to
# <Edition>\_reports\run_<time>. The VM account is the throwaway one that VirtualBox's unattended install makes (vboxuser / changeme).
# Take snapshots only while the VM is powered off: this host cannot restore the saved state of a running VM.
param(
    [string]$Vm = 'test win11',
    [string]$Snapshot = '02 clean Windows, UAC prompt off',
    [string]$Edition = 'E:\win11-optimizer-vm-test',
    [string]$User = 'vboxuser',
    [string]$Password = 'changeme',
    [int]$TimeoutMin = 90,
    [switch]$SkipEasyFull,
    [switch]$NoRestore
)

$ErrorActionPreference = 'Continue'
$vbm = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
if (-not (Test-Path -LiteralPath $vbm)) { throw 'VirtualBox was not found.' }
if (-not (Test-Path -LiteralPath (Join-Path $Edition 'VM_TEST\vm_tests.ps1'))) { throw ('Not a VM test edition: ' + $Edition + ' (build it with tests\vm\Make_VM_Edition.ps1)') }
$cred = @('--username', $User, '--password', $Password)

function Say([string]$t, [string]$c = 'Gray') { Write-Host ((Get-Date -Format 'HH:mm:ss') + '  ' + $t) -ForegroundColor $c }
function Vm-State { return ((& $vbm showvminfo $Vm --machinereadable | Select-String '^VMState=').Line -replace '^VMState="|"$', '') }
function Guest([string]$Cmd, [int]$TimeoutMs = 120000) {
    return (& $vbm guestcontrol $Vm run @cred --exe 'C:\Windows\System32\cmd.exe' --wait-stdout --wait-stderr --timeout $TimeoutMs -- cmd.exe /c $Cmd 2>&1)
}
function Wait-Guest([int]$Minutes = 10) {
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalMinutes -lt $Minutes) {
        Start-Sleep 10
        $null = & $vbm guestcontrol $Vm run @cred --exe 'C:\Windows\System32\cmd.exe' --wait-stdout --timeout 30000 -- cmd.exe /c 'echo up' 2>&1
        if ($LASTEXITCODE -eq 0) { return $true }
    }
    return $false
}

if (-not $NoRestore) {
    if ((Vm-State) -ne 'poweroff') { Say 'Powering the VM off'; & $vbm controlvm $Vm poweroff 2>&1 | Out-Null; Start-Sleep 8 }
    Say ('Restoring the snapshot "' + $Snapshot + '"')
    & $vbm snapshot $Vm restore $Snapshot 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'The snapshot could not be restored.' }
    & $vbm discardstate $Vm 2>&1 | Out-Null
    & $vbm startvm $Vm --type gui 2>&1 | Out-Null
} elseif ((Vm-State) -ne 'running') {
    & $vbm startvm $Vm --type gui 2>&1 | Out-Null
}
Say 'Waiting for Windows and the Guest Additions'
if (-not (Wait-Guest 12)) { throw 'The guest did not become ready in 12 minutes.' }
Start-Sleep 20

Say 'Copying the test edition into the VM'
$null = Guest 'rmdir /s /q C:\win11-optimizer-vm-test 2>nul & rmdir /s /q C:\PCOpt_Reports 2>nul & del C:\Users\Public\vmtest_done.txt C:\Users\Public\vmtest_console.txt 2>nul'
& $vbm guestcontrol $Vm copyto @cred --recursive --target-directory 'C:\' $Edition 2>&1 | Out-Null
$leaf = Split-Path -Leaf $Edition
if ($leaf -ne 'win11-optimizer-vm-test') { $null = Guest ('ren "C:\' + $leaf + '" win11-optimizer-vm-test') }
$extra = $(if ($SkipEasyFull) { ' -SkipEasyFull' } else { '' })
$wrap = Join-Path $env:TEMP 'run_vmtests.cmd'
[IO.File]::WriteAllText($wrap, ("@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File C:\win11-optimizer-vm-test\VM_TEST\vm_tests.ps1 -ReportDir C:\PCOpt_Reports" + $extra + " > C:\Users\Public\vmtest_console.txt 2>&1`r`necho %errorlevel% > C:\Users\Public\vmtest_done.txt`r`n"), (New-Object System.Text.ASCIIEncoding))
& $vbm guestcontrol $Vm copyto @cred --target-directory 'C:\Users\Public\' $wrap 2>&1 | Out-Null

Say 'Starting the suite (elevated)'
# the launcher is a file: quoting a Start-Process command through cmd.exe does not survive
$launch = Join-Path $env:TEMP 'launch_suite.ps1'
[IO.File]::WriteAllText($launch, "Start-Process cmd.exe -ArgumentList '/c C:\Users\Public\run_vmtests.cmd' -Verb RunAs -WindowStyle Hidden`r`n", (New-Object System.Text.ASCIIEncoding))
& $vbm guestcontrol $Vm copyto @cred --target-directory 'C:\Users\Public\launch_suite.ps1' $launch 2>&1 | Out-Null
& $vbm guestcontrol $Vm run @cred --exe 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' --wait-stdout --wait-stderr --timeout 60000 -- powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\Public\launch_suite.ps1 2>&1 | Out-Null

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$out = Join-Path $Edition ('_reports\run_' + $stamp)
New-Item -ItemType Directory -Path $out -Force | Out-Null
$console = Join-Path $out 'console.txt'
$t0 = Get-Date; $done = $false; $seen = 0
while (((Get-Date) - $t0).TotalMinutes -lt $TimeoutMin) {
    Start-Sleep 45
    & $vbm guestcontrol $Vm copyfrom @cred --target-directory $console 'C:\Users\Public\vmtest_console.txt' 2>&1 | Out-Null
    if (-not (Test-Path -LiteralPath $console)) { continue }
    $lines = @(Get-Content -LiteralPath $console)
    for ($i = $seen; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^(>>|   \[(PASS|FAIL)\])') { Say $lines[$i].Substring(0, [math]::Min(200, $lines[$i].Length)) } }
    $seen = $lines.Count
    if (($lines -join "`n") -match '\d+ passed, \d+ failed') { $done = $true; break }
}
Say $(if ($done) { 'The suite finished' } else { 'Timed out before the suite finished' }) $(if ($done) { 'Green' } else { 'Yellow' })
& $vbm guestcontrol $Vm copyfrom @cred --recursive --target-directory $out 'C:\PCOpt_Reports' 2>&1 | Out-Null
Say ('Reports saved in ' + $out)
$summary = @(Get-Content -LiteralPath $console -ErrorAction SilentlyContinue | Select-Object -Last 25)
$summary
if ($done -and ($summary -join ' ') -match ' 0 failed') { exit 0 } else { exit 1 }
