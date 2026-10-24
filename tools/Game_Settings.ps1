# PC Optimizer v4.32 - windowed-games helper (optional tweak 21)
# Turns on "Optimizations for windowed games" (Settings - System - Display - Graphics).
# Windows then presents DirectX 10 and 11 games in windowed and borderless mode with the modern flip model:
# lower frame latency, and variable refresh rate and Auto HDR can work there. Microsoft documents this setting.
# The setting is the flag SwapEffectUpgradeEnable inside ONE text value that also holds other graphics flags
# (for example AutoHDREnable and the chosen graphics adapter). Only that one flag is changed, all others are kept,
# and Undo puts the flag back to what it was (or removes it again).
#   -Action Apply | Undo | Query
# Exit codes: 0 = done, 1 = failed.
param(
    [ValidateSet('Apply', 'Undo', 'Query')][string]$Action = 'Query',
    [string]$GfxKey = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences',   # a test passes a temporary key here
    [string]$StateKey = 'HKCU:\Software\PCOptimizer'
)

$ErrorActionPreference = 'Continue'
$GfxName = 'DirectXUserGlobalSettings'
$FlagName = 'SwapEffectUpgradeEnable'

function Get-FlagList([string]$Text) {
    # "AutoHDREnable=0;SwapEffectUpgradeEnable=1;" -> @('AutoHDREnable=0', 'SwapEffectUpgradeEnable=1')
    return @(([string]$Text) -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}

function Get-FlagValue([string]$Text, [string]$Name) {
    foreach ($f in (Get-FlagList $Text)) {
        $p = $f -split '=', 2
        if ($p.Count -eq 2 -and $p[0] -ieq $Name) { return $p[1] }
    }
    return $null
}

function Set-FlagValue([string]$Text, [string]$Name, [string]$Value) {
    # Changes one flag, keeps every other flag and its order; adds the flag at the end if it is not there.
    $out = New-Object System.Collections.Generic.List[string]
    $done = $false
    foreach ($f in (Get-FlagList $Text)) {
        $p = $f -split '=', 2
        if ($p.Count -eq 2 -and $p[0] -ieq $Name) {
            if (-not $done) { $out.Add($Name + '=' + $Value); $done = $true }
        } else { $out.Add($f) }
    }
    if (-not $done) { $out.Add($Name + '=' + $Value) }
    return (($out -join ';') + ';')
}

function Remove-FlagValue([string]$Text, [string]$Name) {
    $out = @(Get-FlagList $Text | Where-Object { -not (($_ -split '=', 2)[0] -ieq $Name) })
    if ($out.Count -eq 0) { return '' }
    return (($out -join ';') + ';')
}

function Get-CurrentText {
    try { return [string](Get-ItemProperty -Path $GfxKey -Name $GfxName -ErrorAction Stop).$GfxName } catch { return $null }
}

function Set-CurrentText([string]$Text) {
    try {
        if ($Text -eq '') {
            Remove-ItemProperty -Path $GfxKey -Name $GfxName -ErrorAction SilentlyContinue
        } else {
            if (-not (Test-Path $GfxKey)) { New-Item -Path $GfxKey -Force | Out-Null }
            New-ItemProperty -Path $GfxKey -Name $GfxName -Value $Text -PropertyType String -Force | Out-Null
        }
        return $true
    } catch { return $false }
}

function Get-Saved {
    try { return [string](Get-ItemProperty -Path $StateKey -Name 'Prev_SWAP' -ErrorAction Stop).Prev_SWAP } catch { return $null }
}

if ($MyInvocation.InvocationName -eq '.') { return }   # loaded by a test: only the functions are wanted

$cur = Get-CurrentText
$now = Get-FlagValue $cur $FlagName

if ($Action -eq 'Query') {
    Write-Host ('Optimizations for windowed games: ' + $(if ($null -eq $now) { 'not set (Windows decides)' } elseif ($now -eq '1') { 'on' } else { 'off' }))
    exit 0
}

if ($Action -eq 'Apply') {
    # keep the ORIGINAL state of the flag: only saved the first time ("absent" = there was no such flag)
    if ($null -eq (Get-Saved)) {
        if (-not (Test-Path $StateKey)) { New-Item -Path $StateKey -Force | Out-Null }
        New-ItemProperty -Path $StateKey -Name 'Prev_SWAP' -Value $(if ($null -eq $now) { 'absent' } else { $now }) -PropertyType String -Force | Out-Null
    }
    $new = Set-FlagValue $(if ($null -eq $cur) { '' } else { $cur }) $FlagName '1'
    if (-not (Set-CurrentText $new)) { Write-Host '   [FAILED] The graphics preference could not be written.'; exit 1 }
    $chk = Get-FlagValue (Get-CurrentText) $FlagName
    if ($chk -eq '1') {
        Write-Host ('   [OK] Optimizations for windowed games are on (the flag was ' + $(if ($null -eq $now) { 'not set' } else { $now }) + '). Restart the game.')
        exit 0
    }
    Write-Host '   [FAILED] The value did not read back.'
    exit 1
}

# Undo
$prev = Get-Saved
if ($null -eq $prev) {
    Write-Host '   No saved earlier state was found, so there is nothing to undo here.'
    Write-Host '   You can also switch it by hand: Settings - System - Display - Graphics.'
    exit 0
}
$text = $(if ($null -eq $cur) { '' } else { $cur })
if ($prev -eq 'absent') { $text = Remove-FlagValue $text $FlagName } else { $text = Set-FlagValue $text $FlagName $prev }
if (-not (Set-CurrentText $text)) { Write-Host '   [FAILED] The graphics preference could not be written.'; exit 1 }
Remove-ItemProperty -Path $StateKey -Name 'Prev_SWAP' -ErrorAction SilentlyContinue
Write-Host ('   [OK] Back to your earlier state (' + $(if ($prev -eq 'absent') { 'flag not set' } else { 'flag ' + $prev }) + ').')
exit 0
