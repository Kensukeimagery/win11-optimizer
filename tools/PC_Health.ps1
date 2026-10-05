# PC Optimizer v4.11 - PC health check
# Read-only: it only reads the Windows event log, the drives, the battery, the memory and the displays. It changes nothing.
# Shows: crashes and blue screens, drive health, battery wear (laptops), and three things that matter for games:
# the screen refresh rate, whether the RAM runs at its rated speed, and the speed of the network cable link.
#   -Root <folder>  also save the report as PCHealth_<time>.txt in that folder
#   -Days <n>       how far back to look in the event log (default 30)
param(
    [string]$Root = '',
    [int]$Days = 30
)

$ErrorActionPreference = 'Continue'
$script:Lines = New-Object System.Collections.Generic.List[string]
$script:Flags = 0
$user = [string]$env:USERNAME
$pcName = [string]$env:COMPUTERNAME

function Hide-Private([string]$Text) {
    if ($user -ne '') { $Text = $Text -replace [regex]::Escape($user), '<user>' }
    if ($pcName -ne '') { $Text = $Text -replace [regex]::Escape($pcName), '<pc>' }
    return $Text
}
function Write-Log([string]$Text, [string]$Color = 'Gray') {
    $safe = Hide-Private $Text
    Write-Host $safe -ForegroundColor $Color
    $script:Lines.Add($safe)
}
function Write-Check([string]$Text) { $script:Flags++; Write-Log ('     [CHECK] ' + $Text) 'Yellow' }
function Write-Good([string]$Text) { Write-Log ('     [OK]    ' + $Text) 'Green' }
function Write-Note([string]$Text) { Write-Log ('     [INFO]  ' + $Text) 'Gray' }

# ---------------------------------------------------------------- rules (pure functions, tested without touching the PC)
function Get-BugcheckInfo([string]$Code) {
    # Plain-words name and the usual direction for the most common blue screen codes.
    $n = 0
    try { $n = [Convert]::ToInt64(($Code -replace '^0[xX]', ''), 16) } catch { return @{ Name = 'unknown'; Hint = 'The code could not be read.' } }
    switch ($n) {
        0x0A { return @{ Name = 'IRQL_NOT_LESS_OR_EQUAL'; Hint = 'a driver or memory problem; update drivers, test the RAM' } }
        0x1A { return @{ Name = 'MEMORY_MANAGEMENT'; Hint = 'often faulty RAM or an unstable memory overclock (XMP/EXPO); test the RAM' } }
        0x1E { return @{ Name = 'KMODE_EXCEPTION_NOT_HANDLED'; Hint = 'usually a driver; note which driver the blue screen names' } }
        0x3B { return @{ Name = 'SYSTEM_SERVICE_EXCEPTION'; Hint = 'usually a driver or security software' } }
        0x50 { return @{ Name = 'PAGE_FAULT_IN_NONPAGED_AREA'; Hint = 'faulty RAM, a driver or a disk problem' } }
        0x7A { return @{ Name = 'KERNEL_DATA_INPAGE_ERROR'; Hint = 'a failing drive, a bad cable or RAM; check the drive health below' } }
        0x7B { return @{ Name = 'INACCESSIBLE_BOOT_DEVICE'; Hint = 'Windows could not reach the boot drive; storage driver or drive problem' } }
        0x7E { return @{ Name = 'SYSTEM_THREAD_EXCEPTION_NOT_HANDLED'; Hint = 'usually a driver' } }
        0x9F { return @{ Name = 'DRIVER_POWER_STATE_FAILURE'; Hint = 'a driver that does not handle sleep or power saving well' } }
        0xC2 { return @{ Name = 'BAD_POOL_CALLER'; Hint = 'a driver bug' } }
        0xD1 { return @{ Name = 'DRIVER_IRQL_NOT_LESS_OR_EQUAL'; Hint = 'a driver, often network or graphics' } }
        0xEF { return @{ Name = 'CRITICAL_PROCESS_DIED'; Hint = 'a damaged system file or a failing drive; the repair tools can help' } }
        0xF4 { return @{ Name = 'CRITICAL_OBJECT_TERMINATION'; Hint = 'a failing drive or cable' } }
        0x101 { return @{ Name = 'CLOCK_WATCHDOG_TIMEOUT'; Hint = 'a CPU core stopped responding; overclock, undervolt or power problem' } }
        0x116 { return @{ Name = 'VIDEO_TDR_FAILURE'; Hint = 'the graphics driver or card stopped responding; driver, heat or power' } }
        0x117 { return @{ Name = 'VIDEO_TDR_TIMEOUT_DETECTED'; Hint = 'the graphics driver or card stopped responding' } }
        0x124 { return @{ Name = 'WHEA_UNCORRECTABLE_ERROR'; Hint = 'a hardware error reported by the CPU; heat, overclock, power or a failing part' } }
        0x133 { return @{ Name = 'DPC_WATCHDOG_VIOLATION'; Hint = 'a driver or a drive firmware that hangs; update the SSD firmware and drivers' } }
        default { return @{ Name = 'code ' + ('0x{0:X}' -f $n); Hint = 'search this code together with the word bugcheck' } }
    }
}

function Get-DiskHints($Disk) {
    # Disk: Name, Media, Health, Status, Temp, Wear, ReadErrors, WriteErrors
    $out = @()
    if ($Disk.Health -and $Disk.Health -ne 'Healthy') { $out += ('Windows reports the health as ' + $Disk.Health + '. Back up your files now.') }
    if ($Disk.Status -and $Disk.Status -notin @('OK', 'Unknown')) { $out += ('the drive status is ' + $Disk.Status) }
    if ($null -ne $Disk.Wear -and [int]$Disk.Wear -ge 80) { $out += ('about ' + $Disk.Wear + '% of the rated write life is used; plan a replacement') }
    $limit = 70
    if ($Disk.Media -eq 'HDD') { $limit = 55 }
    if ($null -ne $Disk.Temp -and [int]$Disk.Temp -ge $limit) { $out += ('it is hot (' + $Disk.Temp + ' C); check the airflow') }
    $errs = 0
    if ($null -ne $Disk.ReadErrors) { $errs += [int64]$Disk.ReadErrors }
    if ($null -ne $Disk.WriteErrors) { $errs += [int64]$Disk.WriteErrors }
    if ($errs -gt 0) { $out += ('the drive has logged ' + $errs + ' read/write errors') }
    return $out
}

function Get-RamHint([int]$RunningMhz, [int]$RatedMhz, [int]$Modules) {
    $out = @()
    if ($RatedMhz -gt 0 -and $RunningMhz -gt 0 -and $RunningMhz -lt ($RatedMhz * 0.9)) {
        $out += ('the RAM runs at ' + $RunningMhz + ' MT/s but the modules are rated for ' + $RatedMhz + '. XMP / EXPO is probably off in the BIOS; turning it on is free speed for games')
    }
    if ($Modules -eq 1) { $out += 'only one RAM module is installed (single channel). Two matching modules usually give more memory bandwidth' }
    return $out
}

function Get-LanHint([string]$Description, [double]$Mbps) {
    # An adapter that says Gigabit but links at 100 Mbps or less: cable, port or router.
    if ($Description -match 'GbE|Gigabit|1000|2\.5G|2\.5 G' -and $Mbps -gt 0 -and $Mbps -le 100) {
        return ('the adapter supports Gigabit but the link is only ' + $Mbps + ' Mbps. Try another cable (Cat5e or better) or another router port')
    }
    return ''
}

function Get-RefreshHint([int]$Current, [int]$Max) {
    if ($Max -gt 0 -and $Current -gt 0 -and $Current -lt ($Max - 1)) {
        return ('Windows uses ' + $Current + ' Hz but this screen supports ' + $Max + ' Hz at this resolution. Settings > System > Display > Advanced display (some laptops lower it on purpose to save battery)')
    }
    return ''
}

function Get-BatteryHealthPercent($Design, $Full) {
    if ($null -eq $Design -or $null -eq $Full -or [double]$Design -le 0) { return $null }
    return [int][math]::Round(100.0 * [double]$Full / [double]$Design)
}

# ---------------------------------------------------------------- data collection
function Get-Events([string]$Log, [int]$Id, [string]$Provider, [datetime]$Since) {
    $filter = @{ LogName = $Log; Id = $Id; StartTime = $Since }
    if ($Provider -ne '') { $filter['ProviderName'] = $Provider }
    try { return @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop) } catch { return @() }
}

function Show-Crashes {
    $since = (Get-Date).AddDays(-$Days)
    Write-Log ''
    Write-Log ('   A. Crashes and blue screens (last ' + $Days + ' days)') 'White'
    $bug = @(Get-Events 'System' 1001 'Microsoft-Windows-WER-SystemErrorReporting' $since)
    $power = @(Get-Events 'System' 41 'Microsoft-Windows-Kernel-Power' $since)
    $tdr = @(Get-Events 'System' 4101 'Display' $since)
    $whea = @()
    foreach ($wid in 1, 18, 20) { $whea += @(Get-Events 'System' $wid 'Microsoft-Windows-WHEA-Logger' $since) }   # the fatal ones; corrected errors are common noise

    if ($bug.Count -eq 0) { Write-Good 'No blue screens were recorded.' }
    else {
        $script:Flags++
        Write-Log ('     [CHECK] ' + $bug.Count + ' blue screen(s) were recorded. Most recent first:') 'Yellow'
        foreach ($e in @($bug | Sort-Object TimeCreated -Descending | Select-Object -First 5)) {
            $code = ''
            try { $m = [regex]::Match([string]$e.Properties[0].Value, '0x[0-9a-fA-F]+'); if ($m.Success) { $code = $m.Value } } catch { }
            if ($code -eq '') { Write-Log ('        ' + $e.TimeCreated.ToString('yyyy-MM-dd HH:mm') + '  (the code could not be read)') 'Gray'; continue }
            $info = Get-BugcheckInfo $code
            Write-Log ('        ' + $e.TimeCreated.ToString('yyyy-MM-dd HH:mm') + '  ' + $code + ' ' + $info.Name + ' - ' + $info.Hint) 'Gray'
        }
        Write-Note 'One blue screen is not proof of a faulty part. The same code again and again is worth following up.'
    }
    if ($power.Count -eq 0) { Write-Good 'No unexpected shutdowns or power-offs were recorded.' }
    else { Write-Check ([string]$power.Count + ' time(s) the PC shut down without a clean shutdown (power loss, hard reset or a crash); the latest was ' + (($power | Sort-Object TimeCreated -Descending | Select-Object -First 1).TimeCreated.ToString('yyyy-MM-dd HH:mm')) + '. If you did not press reset or the power button, check the power supply, the power cable and the temperatures.') }
    if ($tdr.Count -eq 0) { Write-Good 'The graphics driver did not stop responding.' }
    else { Write-Check ('the graphics driver stopped responding and recovered ' + $tdr.Count + ' time(s). Common causes: an unstable overclock, heat, or a driver problem. Update the graphics driver first.') }
    if ($whea.Count -gt 0) { Write-Check ([string]$whea.Count + ' fatal hardware error(s) were reported by the CPU/PCIe (WHEA). Heat, overclock or a failing part can cause this.') }

    $apps = @(Get-Events 'Application' 1000 'Application Error' $since)
    if ($apps.Count -gt 0) {
        $names = @($apps | ForEach-Object { try { [string]$_.Properties[0].Value } catch { '' } } | Where-Object { $_ -ne '' } | Group-Object | Sort-Object Count -Descending | Select-Object -First 5)
        Write-Note ('programs that crashed: ' + (($names | ForEach-Object { $_.Name + ' x' + $_.Count }) -join ', '))
    }
}

function Show-Disks {
    Write-Log ''
    Write-Log '   B. Drives' 'White'
    $disks = @()
    try { $disks = @(Get-PhysicalDisk -ErrorAction Stop) } catch { }
    if ($disks.Count -eq 0) { Write-Note 'Windows did not report any physical drive on this PC.'; return }
    foreach ($d in $disks) {
        $rel = $null
        try { $rel = $d | Get-StorageReliabilityCounter -ErrorAction Stop } catch { }
        $info = [pscustomobject]@{
            Name = [string]$d.FriendlyName; Media = [string]$d.MediaType; Health = [string]$d.HealthStatus; Status = [string]$d.OperationalStatus
            Temp = $(if ($rel) { $rel.Temperature } else { $null }); Wear = $(if ($rel) { $rel.Wear } else { $null })
            ReadErrors = $(if ($rel) { $rel.ReadErrorsTotal } else { $null }); WriteErrors = $(if ($rel) { $rel.WriteErrorsTotal } else { $null })
            Hours = $(if ($rel) { $rel.PowerOnHours } else { $null })
        }
        $line = $info.Name + ', ' + $info.Media + ', ' + [math]::Round($d.Size / 1GB) + ' GB, health ' + $info.Health
        if ($null -ne $info.Temp -and [int]$info.Temp -gt 0) { $line += ', ' + $info.Temp + ' C' }
        if ($null -ne $info.Wear) { $line += ', ' + $info.Wear + '% worn' }
        if ($null -ne $info.Hours -and [int64]$info.Hours -gt 0) { $line += ', ' + $info.Hours + ' hours on' }
        $hints = @(Get-DiskHints $info)
        if ($hints.Count -eq 0) { Write-Good $line }
        else { Write-Log ('     ' + $line) 'Gray'; foreach ($h in $hints) { Write-Check $h } }
    }
    Write-Note 'Temperature and wear are shown when the drive reports them (some need administrator rights).'
}

function Show-Battery {
    Write-Log ''
    Write-Log '   C. Battery' 'White'
    $laptop = $false
    try {
        $types = @((Get-CimInstance Win32_SystemEnclosure -ErrorAction Stop).ChassisTypes)
        $laptop = (@($types | Where-Object { $_ -in 8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32 }).Count -gt 0)
    } catch { }
    if (-not $laptop) { Write-Note 'This is a desktop, so there is no laptop battery to check.'; return }
    $design = $null; $full = $null
    try { $design = (Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction Stop | Select-Object -First 1).DesignedCapacity } catch { }
    try { $full = (Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction Stop | Select-Object -First 1).FullChargedCapacity } catch { }
    $pct = Get-BatteryHealthPercent $design $full
    if ($null -eq $pct) { Write-Note 'The battery capacity could not be read on this PC.'; return }
    $text = 'the battery holds about ' + $pct + '% of its original capacity (' + $full + ' of ' + $design + ' mWh)'
    if ($pct -lt 60) { Write-Check ($text + '. It is worn; a new battery would give much longer use.') }
    elseif ($pct -lt 80) { Write-Note ($text + '. Some wear is normal.') }
    else { Write-Good $text }
}

function Initialize-DisplayApi {
    if ('PCOptDisplay' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class PCOptDisplay {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion; public short dmDriverVersion; public short dmSize; public short dmDriverExtra;
        public int dmFields; public int dmPositionX; public int dmPositionY; public int dmDisplayOrientation; public int dmDisplayFixedOutput;
        public short dmColor; public short dmDuplex; public short dmYResolution; public short dmTTOption; public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels; public int dmBitsPerPel; public int dmPelsWidth; public int dmPelsHeight; public int dmDisplayFlags;
        public int dmDisplayFrequency; public int dmICMMethod; public int dmICMIntent; public int dmMediaType; public int dmDitherType;
        public int dmReserved1; public int dmReserved2; public int dmPanningWidth; public int dmPanningHeight;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DISPLAY_DEVICE {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
    }
    [DllImport("user32.dll", CharSet = CharSet.Ansi)] public static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);
    [DllImport("user32.dll", CharSet = CharSet.Ansi)] public static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);
    public static string[] Describe() {
        var rows = new System.Collections.Generic.List<string>();
        for (uint i = 0; i < 16; i++) {
            DISPLAY_DEVICE dd = new DISPLAY_DEVICE(); dd.cb = Marshal.SizeOf(dd);
            if (!EnumDisplayDevices(null, i, ref dd, 0)) break;
            if ((dd.StateFlags & 1) == 0) continue;   // not attached to the desktop
            DEVMODE cur = new DEVMODE(); cur.dmSize = (short)Marshal.SizeOf(cur);
            if (!EnumDisplaySettings(dd.DeviceName, -1, ref cur)) continue;
            int max = cur.dmDisplayFrequency;
            for (int m = 0; m < 4000; m++) {
                DEVMODE dm = new DEVMODE(); dm.dmSize = (short)Marshal.SizeOf(dm);
                if (!EnumDisplaySettings(dd.DeviceName, m, ref dm)) break;
                if (dm.dmPelsWidth == cur.dmPelsWidth && dm.dmPelsHeight == cur.dmPelsHeight && dm.dmDisplayFrequency > max) max = dm.dmDisplayFrequency;
            }
            DISPLAY_DEVICE mon = new DISPLAY_DEVICE(); mon.cb = Marshal.SizeOf(mon);
            string name = "";
            if (EnumDisplayDevices(dd.DeviceName, 0, ref mon, 0)) name = mon.DeviceString;
            rows.Add(name + "|" + cur.dmPelsWidth + "|" + cur.dmPelsHeight + "|" + cur.dmDisplayFrequency + "|" + max);
        }
        return rows.ToArray();
    }
}
'@
}

function Show-GamingChecks {
    Write-Log ''
    Write-Log '   D. Things that matter for games' 'White'
    # screens
    $rows = @()
    try { Initialize-DisplayApi; $rows = @([PCOptDisplay]::Describe()) } catch { }
    if ($rows.Count -eq 0) { Write-Note 'Screens: Windows did not report an active screen to this tool.' }
    $n = 0
    foreach ($r in $rows) {
        $n++
        $p = $r -split '\|'
        $line = 'Screen ' + $n + $(if ($p[0] -ne '') { ' (' + $p[0] + ')' } else { '' }) + ': ' + $p[1] + 'x' + $p[2] + ' at ' + $p[3] + ' Hz'
        $hint = Get-RefreshHint ([int]$p[3]) ([int]$p[4])
        if ($hint -eq '') { Write-Good ($line + $(if ([int]$p[4] -gt [int]$p[3]) { '' } else { ' (the highest this screen reports at this resolution)' })) }
        else { Write-Log ('     ' + $line) 'Gray'; Write-Check $hint }
    }
    # memory
    $mods = @()
    try { $mods = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop) } catch { }
    if ($mods.Count -eq 0) { Write-Note 'Memory: the module details could not be read on this PC.' }
    else {
        $running = 0; $rated = 0; $total = 0
        foreach ($m in $mods) {
            if ([int]$m.ConfiguredClockSpeed -gt $running) { $running = [int]$m.ConfiguredClockSpeed }
            if ([int]$m.Speed -gt $rated) { $rated = [int]$m.Speed }
            $total += [double]$m.Capacity
        }
        $line = 'Memory: ' + $mods.Count + ' module(s), ' + [math]::Round($total / 1GB) + ' GB, running at ' + $running + ' MT/s (modules rated ' + $rated + ')'
        $hints = @(Get-RamHint $running $rated $mods.Count)
        if ($hints.Count -eq 0) { Write-Good $line } else { Write-Log ('     ' + $line) 'Gray'; foreach ($h in $hints) { Write-Check $h } }
    }
    # network cable / wi-fi
    $ads = @()
    try { $ads = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' }) } catch { }
    if ($ads.Count -eq 0) { Write-Note 'Network: no active adapter was found.' }
    foreach ($a in $ads) {
        $mbps = 0.0
        try { $mbps = [math]::Round([double]$a.ReceiveLinkSpeed / 1000000, 0) } catch { }
        $line = 'Network ' + $a.Name + ' (' + $a.InterfaceDescription + '): link ' + $mbps + ' Mbps'
        $hint = ''
        if ([string]$a.PhysicalMediaType -match '802\.3') { $hint = Get-LanHint ([string]$a.InterfaceDescription) $mbps }
        if ($hint -eq '') { Write-Good $line } else { Write-Log ('     ' + $line) 'Gray'; Write-Check $hint }
    }
    Write-Note 'These are things to look at, not faults. Where a game runs at a lower refresh rate than the screen allows, that alone can feel like input lag.'
}

# ---------------------------------------------------------------- main
function Start-PcHealth {
    $rootDir = ''
    if ($Root -ne '') { try { $rootDir = (Resolve-Path -LiteralPath $Root).Path } catch { } }
    Write-Log '==================================================================' 'Cyan'
    Write-Log '   PC OPTIMIZER v4.11 - PC HEALTH (nothing is changed)' 'Cyan'
    Write-Log ('   ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')) 'Cyan'
    Write-Log '==================================================================' 'Cyan'
    Write-Log ''
    Write-Log '   Reading the event log, drives and hardware, about 10-30 seconds. No key press is needed...' 'DarkGray'
    Show-Crashes
    Show-Disks
    Show-Battery
    Show-GamingChecks
    Write-Log ''
    if ($script:Flags -eq 0) { Write-Log '   Nothing needs your attention.' 'Green' }
    else { Write-Log ('   ' + $script:Flags + ' item(s) are worth a look (marked CHECK above).') 'Yellow' }
    Write-Log '   This is a quick look, not a full diagnosis. Tell a technician or attach this report to an issue if something looks wrong.' 'DarkGray'
    if ($rootDir -ne '') {
        try { [IO.File]::WriteAllLines((Join-Path $rootDir ('PCHealth_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.txt')), $script:Lines) } catch { }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Start-PcHealth
    exit 0
}
