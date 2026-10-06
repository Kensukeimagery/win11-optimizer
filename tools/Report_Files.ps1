# Shared by the tools: where reports and logs are saved (the Logs folder), how many are kept, and removing the old ones.
# Only files whose names match the exact report names inside <Root>\Logs are ever removed by the automatic cleanup.
# Backups (<Root>\Backup) are never removed automatically: Clean_Up.ps1 lists them and asks first.
# This file has no parameters on purpose: dot-source it, then call the functions.

$script:ReportNameRegex = '^(?<p>OptimizerLog|CheckReport|NetworkTest|SystemReport|UpdateLog|DriverReport|DriverCleanReport|PCHealth|PCSpecs|SupportBundle)_(?<ts>\d{8}_\d{6})(?<after>_after)?\.txt$'
$script:KeepDefault = 3
$script:SupportBundleExtra = 2   # a support bundle is made on purpose to be shared, so it is kept a little longer

# How many backups of each kind are kept when you ask for a cleanup (newest first). Anything not listed here is never touched.
$script:BackupRules = @(
    @{ Group = 'drivers_removed'; Regex = '^drivers_removed_(?<ts>\d{8}_\d{6})$'; Keep = 2; Text = 'copies of drivers removed by the driver cleanup' }
    @{ Group = 'drivers'; Regex = '^drivers_(?<ts>\d{8}_\d{6})$'; Keep = 1; Text = 'full copies of your drivers (made before installing drivers)' }
    @{ Group = 'update'; Regex = '^update_(?<v>[0-9.]+)_(?<ts>\d{8}_\d{6})$'; Keep = 2; Text = 'earlier versions of this program (made by the updater)' }
    @{ Group = 'check'; Regex = '^(?<ts>\d{8}_\d{6})_check$'; Keep = 10; Text = 'registry copies made by Check Status' }
    @{ Group = 'registry'; Regex = '^(?<ts>\d{8}_\d{6})$'; Keep = 10; Text = 'registry copies made by the main menu' }
)

function Get-KeepSetting {
    $n = $script:KeepDefault
    try {
        $v = (Get-ItemProperty -Path 'HKCU:\Software\PCOptimizer' -Name 'LogKeep' -ErrorAction Stop).LogKeep
        $parsed = 0
        if ([int]::TryParse([string]$v, [ref]$parsed)) { $n = [math]::Max(0, [math]::Min(99, $parsed)) }
    } catch { }
    return $n
}

function Set-KeepSetting([int]$Count) {
    $n = [math]::Max(0, [math]::Min(99, $Count))
    if (-not (Test-Path 'HKCU:\Software\PCOptimizer')) { New-Item -Path 'HKCU:\Software\PCOptimizer' -Force | Out-Null }
    New-ItemProperty -Path 'HKCU:\Software\PCOptimizer' -Name 'LogKeep' -Value ([string]$n) -PropertyType String -Force | Out-Null
}

function Get-LogsDir([string]$Root) { return (Join-Path $Root 'Logs') }

function New-ReportPath([string]$Root, [string]$Prefix, [string]$Suffix = '') {
    # The full path for a new report, e.g. <Root>\Logs\PCHealth_20261006_154453.txt. The Logs folder is created when needed.
    $dir = Get-LogsDir $Root
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    return (Join-Path $dir ($Prefix + '_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + $Suffix + '.txt'))
}

function Get-ReportFiles([string]$Dir) {
    $out = @()
    if (-not (Test-Path -LiteralPath $Dir)) { return $out }
    foreach ($f in @(Get-ChildItem -LiteralPath $Dir -File -ErrorAction SilentlyContinue)) {
        $m = [regex]::Match($f.Name, $script:ReportNameRegex)
        if ($m.Success) {
            $kind = $m.Groups['p'].Value + $(if ($m.Groups['after'].Success) { '_after' } else { '' })
            $out += [pscustomobject]@{ Name = $f.Name; Path = $f.FullName; Kind = $kind; Prefix = $m.Groups['p'].Value; Stamp = $m.Groups['ts'].Value; Bytes = [int64]$f.Length }
        }
    }
    return $out
}

function Select-ReportsToRemove($Files, [int]$Keep) {
    # Pure rule: per kind of report keep the newest $Keep (a support bundle keeps 2 more); everything older is returned. Keep 0 = remove nothing.
    if ($Keep -le 0) { return @() }
    $remove = @()
    foreach ($g in @($Files | Group-Object Kind)) {
        $n = $Keep
        if ($g.Name -eq 'SupportBundle') { $n = $Keep + $script:SupportBundleExtra }
        $remove += @($g.Group | Sort-Object Stamp -Descending | Select-Object -Skip $n)
    }
    return $remove
}

function Test-PathInside([string]$Path, [string]$Parent) {
    # True only when $Path is below $Parent and is not a link that points somewhere else.
    try {
        $full = [IO.Path]::GetFullPath($Path)
        $par = [IO.Path]::GetFullPath($Parent).TrimEnd('\') + '\'
        if (-not $full.StartsWith($par, [StringComparison]::OrdinalIgnoreCase)) { return $false }
        $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
        return $true
    } catch { return $false }
}

function Remove-OldReports([string]$Root, [int]$Keep = -1, [switch]$DryRun) {
    # Removes old report files in <Root>\Logs. Returns @{ Count; Bytes }.
    if ($Keep -lt 0) { $Keep = Get-KeepSetting }
    $dir = Get-LogsDir $Root
    $count = 0; $bytes = [int64]0
    foreach ($f in @(Select-ReportsToRemove (Get-ReportFiles $dir) $Keep)) {
        if (-not (Test-PathInside $f.Path $dir)) { continue }
        if ($DryRun) { $count++; $bytes += $f.Bytes; continue }
        try { [IO.File]::Delete($f.Path); $count++; $bytes += $f.Bytes } catch { }
    }
    return @{ Count = $count; Bytes = $bytes }
}

function Move-ReportsToLogs([string]$Root) {
    # Older versions saved the reports next to the scripts. Move them into Logs once. Nothing is overwritten or deleted.
    $moved = 0
    foreach ($f in @(Get-ReportFiles $Root)) {
        $dir = Get-LogsDir $Root
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $dest = Join-Path $dir $f.Name
        if (Test-Path -LiteralPath $dest) { continue }
        try { [IO.File]::Move($f.Path, $dest); $moved++ } catch { }
    }
    return $moved
}

function Get-FolderBytes([string]$Path) {
    $sum = $null
    try { $sum = (Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum } catch { }
    if ($null -eq $sum) { return [int64]0 }
    return [int64]$sum
}

function Get-BackupItems([string]$Root) {
    # The folders in <Root>\Backup that this program made, with their group, time stamp and size. Other things in Backup are ignored.
    $out = @()
    $dir = Join-Path $Root 'Backup'
    if (-not (Test-Path -LiteralPath $dir)) { return $out }
    foreach ($d in @(Get-ChildItem -LiteralPath $dir -Directory -ErrorAction SilentlyContinue)) {
        foreach ($rule in $script:BackupRules) {
            $m = [regex]::Match($d.Name, $rule.Regex)
            if ($m.Success) {
                $out += [pscustomobject]@{ Name = $d.Name; Path = $d.FullName; Group = $rule.Group; Stamp = $m.Groups['ts'].Value; Keep = $rule.Keep; Text = $rule.Text; Bytes = (Get-FolderBytes $d.FullName) }
                break
            }
        }
    }
    return $out
}

function Select-BackupsToRemove($Items) {
    # Pure rule: per group keep the newest N (see $script:BackupRules), return the older ones.
    $remove = @()
    foreach ($g in @($Items | Group-Object Group)) {
        $keep = [int]($g.Group | Select-Object -First 1).Keep
        $remove += @($g.Group | Sort-Object Stamp -Descending | Select-Object -Skip $keep)
    }
    return $remove
}

function Remove-BackupItems($Items, [string]$Root) {
    $dir = Join-Path $Root 'Backup'
    $count = 0; $bytes = [int64]0
    foreach ($i in @($Items)) {
        if (-not (Test-PathInside $i.Path $dir)) { continue }
        try { [IO.Directory]::Delete($i.Path, $true); $count++; $bytes += $i.Bytes } catch { }
    }
    return @{ Count = $count; Bytes = $bytes }
}

function Format-Size([int64]$Bytes) {
    if ($Bytes -ge 1GB) { return ([math]::Round($Bytes / 1GB, 1).ToString() + ' GB') }
    if ($Bytes -ge 1MB) { return ([math]::Round($Bytes / 1MB, 1).ToString() + ' MB') }
    return ([math]::Round($Bytes / 1KB).ToString() + ' KB')
}
