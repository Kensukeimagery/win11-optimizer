# PC Optimizer v4.7 - CPU boost helper (optional tweak 16)
# Plugged-in only: processor performance boost mode = Aggressive (2) and
# energy performance preference = 0 (favour performance) on the ACTIVE power plan.
# The values you had before are saved first, so Undo restores exactly those.
#   -Action Apply | Undo | Query
# Exit codes: 0 = done, 1 = failed, 3 = this PC does not offer these settings.
param([ValidateSet('Apply', 'Undo', 'Query')][string]$Action = 'Query')

$ErrorActionPreference = 'Continue'
$StateKey = 'HKCU:\Software\PCOptimizer'

function Get-PowerIndex([string]$Alias) {
    # Plugged-in (AC) value of one SUB_PROCESSOR setting, whatever the Windows display language.
    $out = & powercfg.exe /query SCHEME_CURRENT SUB_PROCESSOR $Alias 2>$null
    if ($LASTEXITCODE -ne 0 -or $null -eq $out) { return $null }
    $hex = @([regex]::Matches(($out -join "`n"), '0x[0-9a-fA-F]{8}') | ForEach-Object { $_.Value })
    if ($hex.Count -lt 2) { return $null }
    return [Convert]::ToInt64($hex[$hex.Count - 2], 16)   # the last two are AC then DC
}

function Set-PowerIndex([string]$Alias, [int64]$Value) {
    & powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR $Alias $Value *> $null
    return ($LASTEXITCODE -eq 0)
}

function Get-Saved([string]$Name) {
    try { return [int64](Get-ItemProperty -Path $StateKey -Name $Name -ErrorAction Stop).$Name } catch { return $null }
}

function Save-Value([string]$Name, [int64]$Value) {
    if (-not (Test-Path $StateKey)) { New-Item -Path $StateKey -Force | Out-Null }
    New-ItemProperty -Path $StateKey -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
}

$epp = Get-PowerIndex 'PERFEPP'
$boost = Get-PowerIndex 'PERFBOOSTMODE'

if ($Action -eq 'Query') {
    Write-Host ('EPP (plugged in): ' + $(if ($null -eq $epp) { 'not available' } else { $epp }))
    Write-Host ('Boost mode (plugged in): ' + $(if ($null -eq $boost) { 'not available' } else { $boost }))
    exit 0
}

if ($null -eq $epp -or $null -eq $boost) {
    Write-Host '   This PC does not offer CPU boost mode or energy preference settings. Nothing was changed.'
    exit 3
}

if ($Action -eq 'Apply') {
    # Keep the ORIGINAL values: only save them the first time.
    if ($null -eq (Get-Saved 'Prev_EPP')) { Save-Value 'Prev_EPP' $epp }
    if ($null -eq (Get-Saved 'Prev_BOOST')) { Save-Value 'Prev_BOOST' $boost }
    $ok1 = Set-PowerIndex 'PERFEPP' 0
    $ok2 = Set-PowerIndex 'PERFBOOSTMODE' 2
    & powercfg.exe /setactive SCHEME_CURRENT *> $null
    if (-not ($ok1 -and $ok2)) { Write-Host '   [FAILED] powercfg did not accept the values.'; exit 1 }
    $e2 = Get-PowerIndex 'PERFEPP'
    $b2 = Get-PowerIndex 'PERFBOOSTMODE'
    if ($e2 -eq 0 -and $b2 -eq 2) {
        Write-Host ('   [OK] Plugged-in CPU boost is Aggressive and energy preference is 0 (was boost ' + $boost + ', preference ' + $epp + ').')
        exit 0
    }
    Write-Host ('   [FAILED] Values read back as boost ' + $b2 + ', preference ' + $e2 + '.')
    exit 1
}

# Undo
$prevEpp = Get-Saved 'Prev_EPP'
$prevBoost = Get-Saved 'Prev_BOOST'
if ($null -eq $prevEpp -or $null -eq $prevBoost) {
    Write-Host '   No saved earlier values were found, so there is nothing to undo here.'
    Write-Host '   To reset every power plan to Windows defaults use menu 7, then P.'
    exit 0
}
$ok1 = Set-PowerIndex 'PERFEPP' $prevEpp
$ok2 = Set-PowerIndex 'PERFBOOSTMODE' $prevBoost
& powercfg.exe /setactive SCHEME_CURRENT *> $null
if (-not ($ok1 -and $ok2)) { Write-Host '   [FAILED] powercfg did not accept the old values.'; exit 1 }
Remove-ItemProperty -Path $StateKey -Name 'Prev_EPP' -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $StateKey -Name 'Prev_BOOST' -ErrorAction SilentlyContinue
Write-Host ('   [OK] Back to your earlier values: boost ' + $prevBoost + ', preference ' + $prevEpp + '.')
exit 0
