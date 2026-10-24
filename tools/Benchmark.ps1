# PC Optimizer v4.33 - measure before and after (reads only, changes nothing)
# Measures how busy your PC is at rest: processor use, memory in use, number of processes, services and startup programs,
# and three system activity rates (interrupts, DPCs, context switches). Run it BEFORE you use the tweaks, restart, run it
# again AFTER, and the tool shows both side by side. It tells you plainly when nothing changed: a tweak for latency or
# for one game often does not show up in numbers measured at rest.
#   -Action Before | After | Compare | Quick
#       Before   measure and save as the "before" result
#       After    measure, save as the "after" result and compare with the newest "before"
#       Compare  show the newest "before" and "after" again, measure nothing
#       Quick    measure and show the numbers, save nothing
#   -Samples 10 -IntervalSeconds 2   how many readings (the first one is thrown away) and how far apart
param(
    [ValidateSet('Before', 'After', 'Compare', 'Quick', 'Menu')][string]$Action = 'Quick',
    [string]$Root = '',
    [int]$Samples = 10,
    [int]$IntervalSeconds = 2,
    [switch]$NoPrompt
)

$ErrorActionPreference = 'Continue'
if ($Root -eq '') { $Root = Split-Path -Parent $PSScriptRoot }
$Root = (Resolve-Path -LiteralPath $Root).Path
. (Join-Path $PSScriptRoot 'Report_Files.ps1')

# every number is "lower is better" (less use, fewer things running, less activity)
$script:Metrics = @(
    @{ Key = 'cpu';    Title = 'Processor use at rest';     Unit = '%';  Digits = 1; Count = $false }
    @{ Key = 'ram';    Title = 'Memory in use';             Unit = 'MB'; Digits = 0; Count = $false }
    @{ Key = 'procs';  Title = 'Running processes';         Unit = '';   Digits = 0; Count = $true }
    @{ Key = 'svcs';   Title = 'Running services';          Unit = '';   Digits = 0; Count = $true }
    @{ Key = 'start';  Title = 'Startup programs';          Unit = '';   Digits = 0; Count = $true }
    @{ Key = 'dpc';    Title = 'DPC rate';                  Unit = '/s'; Digits = 0; Count = $false }
    @{ Key = 'irq';    Title = 'Interrupts';                Unit = '/s'; Digits = 0; Count = $false }
    @{ Key = 'ctx';    Title = 'Context switches';          Unit = '/s'; Digits = 0; Count = $false }
    @{ Key = 'faults'; Title = 'Page faults';               Unit = '/s'; Digits = 0; Count = $false }
)
$script:SameBelow = 0.10    # a change smaller than 10 percent is measurement noise, not a result

function Get-ChangeVerdict($Before, $After, [bool]$IsCount) {
    # 'better' (lower), 'worse' (higher) or 'same'. $null on either side means it could not be measured.
    if ($null -eq $Before -or $null -eq $After) { return 'n/a' }
    $b = [double]$Before; $a = [double]$After
    if ($IsCount) {
        if ($a -lt $b) { return 'better' }
        if ($a -gt $b) { return 'worse' }
        return 'same'
    }
    if ($b -eq 0 -and $a -eq 0) { return 'same' }
    $rel = ($a - $b) / [math]::Max([math]::Abs($b), 0.000001)
    if ([math]::Abs($rel) -lt $script:SameBelow) { return 'same' }
    if ($rel -lt 0) { return 'better' }
    return 'worse'
}

function Get-ChangeText($Before, $After) {
    if ($null -eq $Before -or $null -eq $After) { return '' }
    $b = [double]$Before; $a = [double]$After
    if ($b -eq 0) { if ($a -eq 0) { return '0 %' } else { return 'new' } }
    $pct = (($a - $b) / $b) * 100
    return ('{0:+0;-0;0} %' -f [math]::Round($pct))
}

function Get-Average($Values) {
    $v = @($Values | Where-Object { $null -ne $_ })
    if ($v.Count -eq 0) { return $null }
    return ($v | Measure-Object -Average).Average
}

function Read-Rates {
    # one reading of the activity counters through WMI (the class and property names are the same on every Windows language)
    $r = @{ cpu = $null; irq = $null; dpc = $null; ctx = $null; faults = $null }
    try {
        $p = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction Stop
        $r.cpu = [double]$p.PercentProcessorTime; $r.irq = [double]$p.InterruptsPersec; $r.dpc = [double]$p.DPCRate
    } catch { }
    try { $r.ctx = [double](Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_System -ErrorAction Stop).ContextSwitchesPersec } catch { }
    try { $r.faults = [double](Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Memory -ErrorAction Stop).PageFaultsPersec } catch { }
    return $r
}

function Measure-Pc([int]$Count, [int]$Interval) {
    $acc = @{ cpu = @(); irq = @(); dpc = @(); ctx = @(); faults = @() }
    for ($i = 0; $i -le $Count; $i++) {
        $r = Read-Rates
        if ($i -gt 0) { foreach ($k in @($acc.Keys)) { $acc[$k] += $r[$k] } }   # the first reading is only a starting point (the key list is copied: the table changes inside the loop)
        if ($i -lt $Count) { Start-Sleep -Seconds $Interval }
    }
    $m = [ordered]@{}
    foreach ($k in 'cpu', 'irq', 'dpc', 'ctx', 'faults') { $m[$k] = Get-Average $acc[$k] }
    try { $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop; $m['ram'] = [double][math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1024) } catch { $m['ram'] = $null }
    try { $m['procs'] = [double]@(Get-Process -ErrorAction Stop).Count } catch { $m['procs'] = $null }
    try { $m['svcs'] = [double]@(Get-Service -ErrorAction Stop | Where-Object { $_.Status -eq 'Running' }).Count } catch { $m['svcs'] = $null }
    try { $m['start'] = [double]@(Get-CimInstance -ClassName Win32_StartupCommand -ErrorAction Stop).Count } catch { $m['start'] = $null }
    return $m
}

function Format-Value($Value, $Metric) {
    if ($null -eq $Value) { return 'n/a' }
    $s = ([double]$Value).ToString('F' + $Metric.Digits, [Globalization.CultureInfo]::InvariantCulture)
    if ($Metric.Unit -ne '') { $s += ' ' + $Metric.Unit }
    return $s
}

function Get-ComparisonRows($Before, $After) {
    $rows = @()
    foreach ($m in $script:Metrics) {
        $b = $Before[$m.Key]; $a = $After[$m.Key]
        $rows += [pscustomobject]@{ Title = $m.Title; Before = (Format-Value $b $m); After = (Format-Value $a $m); Change = (Get-ChangeText $b $a); Verdict = (Get-ChangeVerdict $b $a $m.Count) }
    }
    return $rows
}

function Get-Summary($Rows) {
    $better = @($Rows | Where-Object { $_.Verdict -eq 'better' }).Count
    $worse = @($Rows | Where-Object { $_.Verdict -eq 'worse' }).Count
    $same = @($Rows | Where-Object { $_.Verdict -eq 'same' }).Count
    $text = 'Of ' + ($better + $worse + $same) + ' measurements, ' + $better + ' are lower, ' + $same + ' are about the same and ' + $worse + ' are higher than before.'
    if ($better -eq 0 -and $worse -eq 0) { $text += ' Nothing changed that these numbers can show. That is normal for tweaks that only help latency or one game.' }
    elseif ($worse -gt $better) { $text += ' More things are running than before: something was started or installed in between, or the PC was busy.' }
    return $text
}

function Save-Measurement([string]$Phase, $Measurement) {
    $path = New-ReportPath $Root ('Benchmark' + $Phase)
    $obj = [ordered]@{ Phase = $Phase; Time = (Get-Date -Format 's'); Windows = [Environment]::OSVersion.Version.ToString(); Values = $Measurement }
    [IO.File]::WriteAllText($path, ($obj | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
    return $path
}

function Read-Measurement([string]$Phase) {
    $f = @(Get-ReportFiles (Get-LogsDir $Root) | Where-Object { $_.Prefix -eq ('Benchmark' + $Phase) } | Sort-Object Stamp -Descending | Select-Object -First 1)
    if ($f.Count -eq 0) { return $null }
    try {
        $o = ([IO.File]::ReadAllText($f[0].Path) | ConvertFrom-Json)
        $h = @{}
        foreach ($p in $o.Values.PSObject.Properties) { $h[$p.Name] = $(if ($null -eq $p.Value) { $null } else { [double]$p.Value }) }
        return [pscustomobject]@{ Values = $h; Time = [string]$o.Time }
    } catch { return $null }
}

function Show-Table($Rows) {
    Write-Host ('   ' + 'Measurement'.PadRight(26) + 'Before'.PadLeft(12) + 'After'.PadLeft(12) + 'Change'.PadLeft(9) + '  Result')
    foreach ($r in $Rows) {
        $color = 'Gray'
        if ($r.Verdict -eq 'better') { $color = 'Green' } elseif ($r.Verdict -eq 'worse') { $color = 'Yellow' }
        Write-Host ('   ' + $r.Title.PadRight(26) + $r.Before.PadLeft(12) + $r.After.PadLeft(12) + $r.Change.PadLeft(9) + '  ' + $r.Verdict) -ForegroundColor $color
    }
}

function Show-Comparison($Before, $After) {
    $rows = Get-ComparisonRows $Before.Values $After.Values
    Write-Host ''
    Write-Host ('   Before: ' + $Before.Time + '    After: ' + $After.Time) -ForegroundColor Cyan
    Write-Host ''
    Show-Table $rows
    Write-Host ''
    $summary = Get-Summary $rows
    Write-Host ('   ' + $summary) -ForegroundColor White
    Write-Host '   Readings at rest differ a little from run to run, so only a change of more than 10 percent (or one more or less' -ForegroundColor DarkGray
    Write-Host '   process, service or startup program) is counted. Measure both times the same way: after a restart, nothing else open.' -ForegroundColor DarkGray
    $report = New-ReportPath $Root 'BenchmarkReport'
    $lines = @('PC Optimizer - measurements before and after', ('Before: ' + $Before.Time + '   After: ' + $After.Time), '')
    foreach ($r in $rows) { $lines += ($r.Title.PadRight(26) + $r.Before.PadLeft(12) + $r.After.PadLeft(12) + $r.Change.PadLeft(9) + '  ' + $r.Verdict) }
    $lines += ''; $lines += $summary
    try { [IO.File]::WriteAllLines($report, $lines); Remove-OldReports $Root | Out-Null; Write-Host ''; Write-Host ('   Report saved: ' + (Split-Path -Leaf $report)) -ForegroundColor DarkGray } catch { }
}

if ($MyInvocation.InvocationName -eq '.') { return }   # loaded by a test: only the functions are wanted

if ($Action -eq 'Menu') {
    Write-Host '=================================================================='
    Write-Host '   PC OPTIMIZER - MEASURE BEFORE AND AFTER (nothing is changed)'
    Write-Host '=================================================================='
    Write-Host ''
    Write-Host '   1  Measure BEFORE you use the tweaks'
    Write-Host '   2  Measure AFTER (restart first) and compare with BEFORE'
    Write-Host '   3  Show the last comparison again'
    Write-Host '   4  Quick look: measure now and save nothing'
    Write-Host ''
    $choice = ''
    try { $choice = [string](Read-Host '   Your choice, Enter = leave') } catch { }
    switch ($choice.Trim()) { '1' { $Action = 'Before' } '2' { $Action = 'After' } '3' { $Action = 'Compare' } '4' { $Action = 'Quick' } default { exit 0 } }
}

Write-Host '=================================================================='
Write-Host '   PC OPTIMIZER - MEASURE BEFORE AND AFTER (nothing is changed)'
Write-Host '=================================================================='
Write-Host ''

if ($Action -eq 'Compare') {
    $b = Read-Measurement 'Before'; $a = Read-Measurement 'After'
    if ($null -eq $b -or $null -eq $a) { Write-Host '   There is no pair of measurements yet. Measure BEFORE, use the tweaks, restart, then measure AFTER.'; exit 0 }
    Show-Comparison $b $a
    exit 0
}

if ($Action -eq 'After' -and $null -eq (Read-Measurement 'Before')) {
    Write-Host '   There is no BEFORE measurement yet, so there is nothing to compare with. This one is saved as AFTER anyway.' -ForegroundColor Yellow
}
Write-Host '   For a fair number: close games, browsers and downloads, and measure after a fresh restart.'
Write-Host ('   Measuring takes about ' + ($Samples * $IntervalSeconds) + ' seconds. Please do not use the PC meanwhile...')
Write-Host ''
$m = Measure-Pc $Samples $IntervalSeconds
if ($Action -eq 'Quick') {
    foreach ($x in $script:Metrics) { Write-Host ('   ' + $x.Title.PadRight(26) + (Format-Value $m[$x.Key] $x).PadLeft(12)) }
    exit 0
}
$phase = $(if ($Action -eq 'Before') { 'Before' } else { 'After' })
$saved = Save-Measurement $phase $m
Write-Host ('   Saved as the ' + $phase.ToUpper() + ' measurement: ' + (Split-Path -Leaf $saved)) -ForegroundColor Green
if ($Action -eq 'Before') {
    Write-Host '   Now use the tweaks, restart the PC, and run this again with the AFTER choice.'
    exit 0
}
$before = Read-Measurement 'Before'
if ($null -ne $before) { Show-Comparison $before (Read-Measurement 'After') }
exit 0
