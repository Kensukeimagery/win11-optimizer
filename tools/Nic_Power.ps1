# PC Optimizer v4.30 - network card power saving (optional tweak 22)
# Stops Windows from switching off your network adapters to save power ("Allow the computer to turn off this device
# to save power"). A card that goes to sleep can drop the connection for a moment, which shows up as lag spikes
# or a lost match in online games. Only adapters that offer the setting are touched.
# The adapters that had it switched on are remembered, so Undo switches on exactly those again.
#   -Action Apply | Undo | Query
# Exit codes: 0 = done, 1 = failed, 2 = not administrator, 3 = no adapter offers this setting.
param(
    [ValidateSet('Apply', 'Undo', 'Query')][string]$Action = 'Query',
    [string]$StateKey = 'HKCU:\Software\PCOptimizer\NicPrev'   # a test passes a temporary key here
)

$ErrorActionPreference = 'Continue'

function Test-Admin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-NicState {
    # one entry per physical adapter that offers the setting: Name, Guid, Sleep ('Enabled' = Windows may switch it off)
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($ad in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)) {
        try {
            $pm = Get-NetAdapterPowerManagement -Name $ad.Name -ErrorAction Stop
            $v = [string]$pm.AllowComputerToTurnOffDevice
            if ($v -eq 'Enabled' -or $v -eq 'Disabled') { $list.Add([pscustomobject]@{ Name = $ad.Name; Guid = [string]$ad.InterfaceGuid; Sleep = $v }) }
        } catch { }
    }
    return $list.ToArray()   # not @($list): on Windows PowerShell 5.1 that fails with "Argument types do not match"
}

if ($MyInvocation.InvocationName -eq '.') { return }   # loaded by a test

$nics = @(Get-NicState)

if ($Action -eq 'Query') {
    if ($nics.Count -eq 0) { Write-Host 'No network adapter offers this setting.'; exit 0 }
    foreach ($n in $nics) { Write-Host ($n.Name + ': ' + $(if ($n.Sleep -eq 'Enabled') { 'Windows may switch it off' } else { 'stays on' })) }
    exit 0
}

if (-not (Test-Admin)) { Write-Host '   [ERROR] Please run this as administrator.'; exit 2 }

if ($Action -eq 'Apply') {
    if ($nics.Count -eq 0) { Write-Host '   No network adapter on this PC offers this setting. Nothing was changed.'; exit 3 }
    $failed = 0; $changed = 0
    foreach ($n in $nics) {
        if ($n.Sleep -ne 'Enabled') { continue }
        if (-not (Test-Path $StateKey)) { New-Item -Path $StateKey -Force | Out-Null }
        # remember the original state only once (a second Apply must not forget it)
        if ($null -eq (Get-ItemProperty -Path $StateKey -Name $n.Guid -ErrorAction SilentlyContinue)) {
            New-ItemProperty -Path $StateKey -Name $n.Guid -Value $n.Name -PropertyType String -Force | Out-Null
        }
        try {
            Set-NetAdapterPowerManagement -Name $n.Name -AllowComputerToTurnOffDevice Disabled -ErrorAction Stop
            $changed++
        } catch { $failed++; Write-Host ('   [FAILED] ' + $n.Name + ': ' + $_.Exception.Message) }
    }
    $after = @(Get-NicState | Where-Object { $_.Sleep -eq 'Enabled' })
    if ($failed -eq 0 -and $after.Count -eq 0) {
        Write-Host ('   [OK] ' + $nics.Count + ' network adapter(s) stay on (' + $changed + ' changed).')
        exit 0
    }
    Write-Host ('   [FAILED] ' + $after.Count + ' adapter(s) still allow Windows to switch them off.')
    exit 1
}

# Undo
if (-not (Test-Path $StateKey)) {
    Write-Host '   No saved earlier state was found, so there is nothing to undo here.'
    exit 0
}
$saved = @((Get-Item -Path $StateKey).Property | Where-Object { $_ })
$failed = 0
foreach ($n in $nics) {
    if ($saved -notcontains $n.Guid) { continue }
    try {
        Set-NetAdapterPowerManagement -Name $n.Name -AllowComputerToTurnOffDevice Enabled -ErrorAction Stop
        Remove-ItemProperty -Path $StateKey -Name $n.Guid -ErrorAction SilentlyContinue
    } catch { $failed++; Write-Host ('   [FAILED] ' + $n.Name + ': ' + $_.Exception.Message) }
}
if ($failed -eq 0) {
    $left = @((Get-Item -Path $StateKey -ErrorAction SilentlyContinue).Property | Where-Object { $_ })
    if ($left.Count -eq 0) { Remove-Item -Path $StateKey -Force -ErrorAction SilentlyContinue }
    Write-Host '   [OK] Back to your earlier state: the adapters that could be switched off by Windows can be again.'
    exit 0
}
exit 1
