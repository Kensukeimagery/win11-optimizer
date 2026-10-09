# PC Optimizer v4.17 - System report (read-only: changes nothing on your PC)
# Shows what is using your CPU and RAM, what starts with Windows, disk space, GPU driver age
# and plain-language hints. The saved report hides your Windows user name.
param([string]$Root = '')

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'Report_Files.ps1')
$script:Lines = New-Object System.Collections.Generic.List[string]
$script:Hints = New-Object System.Collections.Generic.List[string]
$user = [string]$env:USERNAME

function Hide-Private([string]$Text) {
    if ($user -ne '') { $Text = $Text -replace [regex]::Escape($user), '<user>' }
    return $Text
}

function Write-Log([string]$Text, [string]$Color = 'Gray') {
    $safe = Hide-Private $Text
    Write-Host $safe -ForegroundColor $Color
    $script:Lines.Add($safe)
}

function Get-Short([string]$Text, [int]$Max) {
    if ($Text.Length -le $Max) { return $Text }
    return $Text.Substring(0, $Max - 3) + '...'
}

Write-Log '==================================================================' 'Cyan'
Write-Log '   PC OPTIMIZER v4.17 - SYSTEM REPORT (nothing is changed)' 'Cyan'
Write-Log ('   ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')) 'Cyan'
Write-Log '==================================================================' 'Cyan'
Write-Log ''
Write-Log '   Collecting information, please wait about 10 seconds. No key press is needed...' 'DarkGray'
Write-Log ''

# ---------------------------------------------------------------- basics
$os = $null; $cpu = $null
try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop } catch { }
try { $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1 } catch { }
$logical = 1
if ($null -ne $cpu -and $cpu.NumberOfLogicalProcessors) { $logical = [int]$cpu.NumberOfLogicalProcessors }

Write-Log '   System' 'White'
if ($null -ne $os) {
    Write-Log ('     Windows      ' + $os.Caption + ', build ' + $os.BuildNumber)
    $up = (Get-Date) - $os.LastBootUpTime
    Write-Log ('     Uptime       ' + [math]::Floor($up.TotalDays) + ' days ' + $up.Hours + ' hours since the last full start')
    if ($up.TotalDays -ge 14) { $script:Hints.Add('The PC has not been fully restarted for ' + [math]::Floor($up.TotalDays) + ' days. A restart clears leaks and finishes pending updates. Note: with Fast Startup on, Shutdown does not count, use Restart.') }
    $totalGb = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $freeGb = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $usedPct = [math]::Round(100 * ($totalGb - $freeGb) / $totalGb)
    Write-Log ('     RAM          ' + $totalGb + ' GB total, ' + $usedPct + '% in use')
    if ($usedPct -ge 85) { $script:Hints.Add('RAM is ' + $usedPct + '% full. Close programs you do not need before gaming (see the RAM list below).') }
    if ($totalGb -lt 15) { $script:Hints.Add('You have less than 16 GB of RAM. Modern games benefit from 16 GB or more, and some tweaks (like 12) are not suited to 8 GB.') }
}
if ($null -ne $cpu) { Write-Log ('     CPU          ' + $cpu.Name.Trim() + ', ' + $cpu.NumberOfCores + ' cores / ' + $cpu.NumberOfLogicalProcessors + ' threads') }

try {
    $plan = (& powercfg.exe /getactivescheme 2>$null) -join ' '
    $m = [regex]::Match($plan, '\((?<n>[^)]+)\)\s*$')
    if ($m.Success) { Write-Log ('     Power plan   ' + $m.Groups['n'].Value) }
} catch { }

# ---------------------------------------------------------------- GPU
Write-Log ''
Write-Log '   Graphics' 'White'
try {
    $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { $_.Name -notmatch 'Basic|Remote|Virtual|Meta' })
    if ($gpus.Count -eq 0) { Write-Log '     No graphics card was reported.' }
    foreach ($g in $gpus) {
        $age = ''
        if ($g.DriverDate) {
            $months = [math]::Floor(((Get-Date) - $g.DriverDate).TotalDays / 30.4)
            $age = ', driver dated ' + $g.DriverDate.ToString('yyyy-MM-dd') + ' (' + $months + ' months old)'
            if ($months -ge 6) { $script:Hints.Add('The driver for ' + $g.Name + ' is ' + $months + ' months old. Install the latest one directly from NVIDIA, AMD or Intel (not from a driver-updater program).') }
        }
        Write-Log ('     ' + $g.Name + ', version ' + $g.DriverVersion + $age)
    }
    if ($gpus.Count -gt 1) { $script:Hints.Add('You have more than one graphics adapter. Make sure each game uses the fast one: Settings > System > Display > Graphics.') }
} catch { Write-Log '     Could not read graphics information.' 'DarkYellow' }

# ---------------------------------------------------------------- disks
Write-Log ''
Write-Log '   Storage' 'White'
try {
    foreach ($d in @(Get-PhysicalDisk -ErrorAction Stop | Sort-Object DeviceId)) {
        Write-Log ('     ' + $d.FriendlyName + ', ' + $d.MediaType + ', ' + [math]::Round($d.Size / 1GB) + ' GB, health ' + $d.HealthStatus)
        if ([string]$d.HealthStatus -ne 'Healthy') { $script:Hints.Add('Disk "' + $d.FriendlyName + '" reports health "' + $d.HealthStatus + '". Back up your files and check it.') }
    }
} catch { Write-Log '     Could not read disk information.' 'DarkYellow' }
try {
    foreach ($v in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop)) {
        $pct = [math]::Round(100.0 * $v.FreeSpace / $v.Size)
        Write-Log ('     ' + $v.DeviceID + ' ' + [math]::Round($v.FreeSpace / 1GB) + ' GB free of ' + [math]::Round($v.Size / 1GB) + ' GB (' + $pct + '% free)')
        if ($pct -lt 15) { $script:Hints.Add('Drive ' + $v.DeviceID + ' has only ' + $pct + '% free. Below 15% SSDs slow down. Use repair-tools\Deep_Clean_Junk_Files.bat or move large files.') }
    }
} catch { }

# ---------------------------------------------------------------- processes
Write-Log ''
Write-Log '   Measuring CPU use for 3 seconds...' 'DarkGray'
$first = @{}
foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) { try { $first[$p.Id] = [double]$p.TotalProcessorTime.TotalSeconds } catch { } }
Start-Sleep -Seconds 3
$rows = New-Object System.Collections.Generic.List[object]
foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) {
    try {
        if ($first.ContainsKey($p.Id)) {
            $delta = [double]$p.TotalProcessorTime.TotalSeconds - $first[$p.Id]
            $rows.Add([pscustomobject]@{ Name = $p.ProcessName; Id = $p.Id; Cpu = [math]::Round(100.0 * $delta / 3 / $logical, 1); RamMb = [math]::Round($p.WorkingSet64 / 1MB) })
        }
    } catch { }
}
# One line per program: add up every process that has the same name (a browser has many)
$rows = @($rows | Group-Object Name | ForEach-Object {
    $label = $_.Name
    if ($_.Count -gt 1) { $label = $_.Name + ' (x' + $_.Count + ')' }
    [pscustomobject]@{ Name = $label; Cpu = [math]::Round((($_.Group | Measure-Object Cpu -Sum).Sum), 1); RamMb = [int](($_.Group | Measure-Object RamMb -Sum).Sum) }
})
Write-Log ''
Write-Log '   Using the most CPU right now (percent of the whole CPU)' 'White'
foreach ($r in @($rows | Sort-Object Cpu -Descending | Select-Object -First 8)) {
    Write-Log ('     ' + $r.Name.PadRight(30) + ([string]$r.Cpu + ' %').PadLeft(8))
}
$busy = @($rows | Where-Object { $_.Cpu -ge 10 -and $_.Name -notmatch '^(Idle|System)$' })
if ($busy.Count -gt 0) {
    $busyNames = (@($busy | Select-Object -First 3 | ForEach-Object { $_.Name })) -join ', '
    $script:Hints.Add('Something is using noticeable CPU right now (' + $busyNames + '). Close it before gaming if you do not need it.')
}
Write-Log ''
Write-Log '   Using the most RAM' 'White'
foreach ($r in @($rows | Sort-Object RamMb -Descending | Select-Object -First 8)) {
    Write-Log ('     ' + $r.Name.PadRight(30) + ([string]$r.RamMb + ' MB').PadLeft(10))
}

# ---------------------------------------------------------------- startup
Write-Log ''
Write-Log '   Programs that start with Windows' 'White'
try {
    $startup = @(Get-CimInstance Win32_StartupCommand -ErrorAction Stop | Sort-Object Name)
    if ($startup.Count -eq 0) { Write-Log '     None found.' }
    foreach ($s in $startup) { Write-Log ('     ' + (Get-Short ([string]$s.Name) 32).PadRight(34) + (Get-Short ([string]$s.Command) 60)) }
    if ($startup.Count -ge 12) { $script:Hints.Add([string]$startup.Count + ' programs start with Windows. Turn off the ones you do not need in Task Manager > Startup apps.') }
    Write-Log '     (Some programs start through scheduled tasks instead. Task Manager > Startup apps shows the full list.)' 'DarkGray'
} catch { Write-Log '     Could not read the startup list.' 'DarkYellow' }

# ---------------------------------------------------------------- hints
Write-Log ''
Write-Log '   What to look at' 'White'
if ($script:Hints.Count -eq 0) {
    Write-Log '     Nothing stands out. This PC looks healthy.' 'Green'
} else {
    foreach ($h in $script:Hints) { Write-Log ('     - ' + $h) 'Yellow' }
}
Write-Log ''
Write-Log '   Before you share this report: it lists program names and paths. Your Windows user name is hidden, but check it anyway.' 'DarkGray'

if ($Root -ne '') {
    try {
        $file = New-ReportPath (Resolve-Path -LiteralPath $Root).Path 'SystemReport'
        [IO.File]::WriteAllLines($file, $script:Lines)
        Remove-OldReports (Resolve-Path -LiteralPath $Root).Path | Out-Null
        Write-Host ''
        Write-Host ('   Report saved: ' + (Split-Path -Leaf $file)) -ForegroundColor DarkGray
    } catch { }
}
exit 0
