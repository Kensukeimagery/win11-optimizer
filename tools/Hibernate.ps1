# PC Optimizer v4.33 - hibernation (optional tweak 27)
# Turns hibernation off: powercfg /hibernate off. Windows then deletes the file hiberfil.sys, which is as large as a
# good part of your RAM (often 6 to 12 GB), and the Hibernate choice disappears from the power menu. Sleep and Shut down
# are not affected. (Fast Startup, which is built on hibernation, is already turned off by tweak 02.)
# The state you had before is saved first: Undo turns hibernation on again only if it was on.
#   -Action Apply | Undo | Query
# Exit codes: 0 = done, 1 = failed, 2 = not administrator.
param(
    [ValidateSet('Apply', 'Undo', 'Query')][string]$Action = 'Query',
    [string]$StateKey = 'HKCU:\Software\PCOptimizer',   # a test passes a temporary key here
    [string]$PowerKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'
)

$ErrorActionPreference = 'Continue'

function Test-Admin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-HibernateOn {
    # Windows writes HibernateEnabled = 0 when hibernation is off; on a PC where it is on the value is 1 (or not there)
    try {
        $v = (Get-ItemProperty -Path $PowerKey -Name 'HibernateEnabled' -ErrorAction Stop).HibernateEnabled
        return ([int]$v -ne 0)
    } catch { return $true }
}

function Get-Saved {
    try { return [string](Get-ItemProperty -Path $StateKey -Name 'Prev_HIB' -ErrorAction Stop).Prev_HIB } catch { return $null }
}

if ($MyInvocation.InvocationName -eq '.') { return }   # loaded by a test

$on = Get-HibernateOn

if ($Action -eq 'Query') {
    Write-Host ('Hibernation: ' + $(if ($on) { 'on' } else { 'off' }))
    exit 0
}

if (-not (Test-Admin)) { Write-Host '   [ERROR] Please run this as administrator.'; exit 2 }

if ($Action -eq 'Apply') {
    # keep the ORIGINAL state: only saved the first time
    if ($null -eq (Get-Saved)) {
        if (-not (Test-Path $StateKey)) { New-Item -Path $StateKey -Force | Out-Null }
        New-ItemProperty -Path $StateKey -Name 'Prev_HIB' -Value $(if ($on) { 'on' } else { 'off' }) -PropertyType String -Force | Out-Null
    }
    if (-not $on) { Write-Host '   [OK] Hibernation is already off.'; exit 0 }
    & powercfg.exe /hibernate off *> $null
    if ($LASTEXITCODE -ne 0) { Write-Host '   [FAILED] powercfg did not turn hibernation off.'; exit 1 }
    if (Get-HibernateOn) { Write-Host '   [FAILED] Hibernation still reads as on.'; exit 1 }
    Write-Host '   [OK] Hibernation is off (hiberfil.sys is removed and the disk space is free).'
    exit 0
}

# Undo
$prev = Get-Saved
if ($null -eq $prev) {
    Write-Host '   No saved earlier state was found, so there is nothing to undo here.'
    Write-Host '   To turn hibernation on by hand: open a command prompt as administrator and type  powercfg /hibernate on'
    exit 0
}
if ($prev -eq 'off') {
    Write-Host '   Hibernation was already off before this tool changed anything, so it stays off.'
} else {
    & powercfg.exe /hibernate on *> $null
    if ($LASTEXITCODE -ne 0) { Write-Host '   [FAILED] powercfg did not turn hibernation on.'; exit 1 }
    Write-Host '   [OK] Hibernation is on again.'
}
Remove-ItemProperty -Path $StateKey -Name 'Prev_HIB' -ErrorAction SilentlyContinue
exit 0
