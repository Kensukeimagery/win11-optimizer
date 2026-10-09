# PC Optimizer v4.17 - PC specs on one page
# Read-only. Shows your PC in plain words on one page: computer, Windows, processor, memory, graphics card, screens, drives,
# network and the security features some games ask for. Meant for people who do not know where to look for the specs,
# and for sharing when you ask for help or sell the PC. No serial numbers, MAC addresses or IP addresses are shown.
# It ends with a short check-up: do the drivers fit the hardware (no device without a driver, a maker graphics driver) and do the settings fit
# (the optimizer settings still in place, screens at their highest refresh rate, RAM at its rated speed, cable at full speed)?
#   -Root <folder>  also save the page as PCSpecs_<time>.txt in that folder
param([string]$Root = '')

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'Report_Files.ps1')
$script:Lines = New-Object System.Collections.Generic.List[string]
$user = [string]$env:USERNAME
$pcName = [string]$env:COMPUTERNAME

. (Join-Path $PSScriptRoot 'Display_Info.ps1')
. (Join-Path $PSScriptRoot 'Check_Rules.ps1')

function Hide-Private([string]$Text) {
    if ($user -ne '') { $Text = $Text -replace ('(?<![A-Za-z0-9])' + [regex]::Escape($user) + '(?![A-Za-z0-9])'), '<user>' }
    if ($pcName -ne '' -and $pcName.Length -ge 2) { $Text = $Text -replace ('(?<![A-Za-z0-9])' + [regex]::Escape($pcName) + '(?![A-Za-z0-9])'), '<pc>' }
    return $Text
}
function Write-Log([string]$Text, [string]$Color = 'Gray') {
    $safe = Hide-Private $Text
    Write-Host $safe -ForegroundColor $Color
    $script:Lines.Add($safe)
}
function Write-Row([string]$Label, [string]$Value) {
    Write-Log (('   ' + $Label.PadRight(15) + $Value).TrimEnd()) 'Gray'
}

# ---------------------------------------------------------------- rules (pure functions, tested without touching the PC)
function Get-RamMemoryType([int]$Code) {
    switch ($Code) { 20 { 'DDR' } 21 { 'DDR2' } 24 { 'DDR3' } 26 { 'DDR4' } 34 { 'DDR5' } default { '' } }
}

function Get-RamNote([double]$Gb) {
    if ($Gb -le 8) { return '8 GB or less is tight for current games with a browser open. 16 GB is the usual recommendation.' }
    if ($Gb -lt 16) { return 'Enough for lighter and older games. 16 GB is the usual recommendation today.' }
    if ($Gb -lt 32) { return 'Good for nearly all games.' }
    return 'Plenty for games and for several programs at the same time.'
}

function Get-VramNote([double]$Gb) {
    if ($Gb -le 0) { return '' }
    if ($Gb -lt 4) { return 'Low for current games: high-resolution textures may stutter. Lower the texture quality.' }
    if ($Gb -lt 8) { return 'Fine for 1080p. Very high texture settings in new games may need more.' }
    return 'Plenty for 1080p and 1440p in most games.'
}

function Get-StorageNote([string]$Media, [double]$FreePercent) {
    $out = @()
    if ($Media -eq 'HDD') { $out += 'Windows is on a hard drive (HDD). An SSD is the single biggest speed-up for start-up, loading and general feel.' }
    if ($FreePercent -ge 0 -and $FreePercent -lt 15) { $out += 'The Windows drive is more than 85% full. Free some space: Windows and games run worse on a nearly full drive.' }
    return $out
}

function Get-NvidiaDriverNumber([string]$WindowsVersion) {
    # 32.0.15.8266 is NVIDIA driver 582.66: the last digit of the third part plus the fourth part, written as 3+2 digits.
    $p = $WindowsVersion -split '\.'
    if ($p.Count -ne 4) { return '' }
    $s = $p[2].Substring($p[2].Length - 1) + $p[3]
    if ($s.Length -ne 5) { return '' }
    return ($s.Substring(0, 3) + '.' + $s.Substring(3))
}

function Test-PlaceholderText([string]$Text) {
    return ([string]::IsNullOrWhiteSpace($Text) -or $Text -match 'To be filled|Default string|System (Product|manufacturer|Version)|O\.E\.M\.|Not Applicable|None|Unknown|^\s*0\s*$')
}

function ConvertTo-Gb([double]$Bytes) { return [math]::Round($Bytes / 1GB, 1) }

# ---------------------------------------------------------------- collectors (each one is allowed to fail on its own)
function Get-Cim([string]$Class, [string]$Namespace = 'root\cimv2') {
    try { return @(Get-CimInstance -Namespace $Namespace -ClassName $Class -ErrorAction Stop) } catch { return @() }
}

function Show-Computer {
    $cs = @(Get-Cim 'Win32_ComputerSystem') | Select-Object -First 1
    $bb = @(Get-Cim 'Win32_BaseBoard') | Select-Object -First 1
    $bios = @(Get-Cim 'Win32_BIOS') | Select-Object -First 1
    $enc = @(Get-Cim 'Win32_SystemEnclosure') | Select-Object -First 1
    $laptop = $false
    if ($enc) { $laptop = (@(@($enc.ChassisTypes) | Where-Object { $_ -in 8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32 }).Count -gt 0) }
    $kind = $(if ($laptop) { 'Laptop' } else { 'Desktop PC' })
    $model = ''
    if ($cs -and -not (Test-PlaceholderText ([string]$cs.Model))) { $model = (([string]$cs.Manufacturer + ' ' + [string]$cs.Model).Trim()) }
    $board = ''
    if ($bb) { $board = (([string]$bb.Manufacturer + ' ' + [string]$bb.Product).Trim()) }
    if ($model -ne '') { Write-Row 'Computer' ($kind + ': ' + $model) } else { Write-Row 'Computer' $kind }
    if ($board -ne '' -and -not (Test-PlaceholderText $board)) { Write-Row 'Motherboard' $board }
    if ($bios) {
        $d = ''
        try { $d = ', dated ' + ([datetime]$bios.ReleaseDate).ToString('yyyy-MM-dd') } catch { }
        Write-Row 'BIOS' (([string]$bios.Manufacturer + ' ' + [string]$bios.SMBIOSBIOSVersion).Trim() + $d)
    }
}

function Show-Windows {
    $os = @(Get-Cim 'Win32_OperatingSystem') | Select-Object -First 1
    if (-not $os) { Write-Row 'Windows' 'could not be read'; return }
    $disp = ''
    try { $disp = [string](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop).DisplayVersion } catch { }
    $line = ([string]$os.Caption -replace '^Microsoft\s+', '') + ', ' + [string]$os.OSArchitecture
    if ($disp -ne '') { $line += ', version ' + $disp }
    $line += ' (build ' + [string]$os.BuildNumber + ')'
    Write-Row 'Windows' $line
    try { Write-Row 'Installed' ([datetime]$os.InstallDate).ToString('yyyy-MM-dd') } catch { }
    if ([string]$os.Caption -match 'Windows 10') { Write-Row '' 'Windows 10 reached the end of its support in October 2025. Windows 11 is recommended where the PC supports it.' }
}

function Show-Processor {
    $cpu = @(Get-Cim 'Win32_Processor')
    if ($cpu.Count -eq 0) { Write-Row 'Processor' 'could not be read'; return }
    $c = $cpu[0]
    $name = (([string]$c.Name) -replace '\s+', ' ').Trim()
    Write-Row 'Processor' $name
    $cores = 0; $threads = 0
    foreach ($x in $cpu) { $cores += [int]$x.NumberOfCores; $threads += [int]$x.NumberOfLogicalProcessors }
    $ghz = ''
    if ([int]$c.MaxClockSpeed -gt 0) { $ghz = ', rated ' + [math]::Round([int]$c.MaxClockSpeed / 1000, 2) + ' GHz' }
    Write-Row '' ($cores.ToString() + ' cores, ' + $threads.ToString() + ' threads' + $ghz)
}

function Show-Memory {
    $mods = @(Get-Cim 'Win32_PhysicalMemory')
    if ($mods.Count -eq 0) {
        $cs = @(Get-Cim 'Win32_ComputerSystem') | Select-Object -First 1
        if ($cs) { Write-Row 'Memory (RAM)' ((ConvertTo-Gb ([double]$cs.TotalPhysicalMemory)).ToString() + ' GB (the module details could not be read)') } else { Write-Row 'Memory (RAM)' 'could not be read' }
        return
    }
    $total = 0.0; $speed = 0; $rated = 0; $type = ''
    foreach ($m in $mods) {
        $total += [double]$m.Capacity
        if ([int]$m.ConfiguredClockSpeed -gt $speed) { $speed = [int]$m.ConfiguredClockSpeed }
        if ([int]$m.Speed -gt $rated) { $rated = [int]$m.Speed }
        $t = Get-RamMemoryType ([int]$m.SMBIOSMemoryType)
        if ($t -ne '') { $type = $t }
    }
    $sizes = @($mods | ForEach-Object { [math]::Round([double]$_.Capacity / 1GB) })
    $each = ''
    if (@($sizes | Select-Object -Unique).Count -eq 1) { $each = ' (' + $mods.Count + ' x ' + $sizes[0] + ' GB)' } else { $each = ' (' + ($sizes -join ' + ') + ' GB)' }
    $slots = 0
    foreach ($a in @(Get-Cim 'Win32_PhysicalMemoryArray')) { $slots += [int]$a.MemoryDevices }
    $line = (ConvertTo-Gb $total).ToString() + ' GB' + $each
    if ($type -ne '') { $line += ', ' + $type }
    if ($speed -gt 0) { $line += ', running at ' + $speed + ' MT/s' }
    Write-Row 'Memory (RAM)' $line
    $extra = ''
    if ($slots -gt 0) { $extra = $mods.Count.ToString() + ' of ' + $slots + ' slots used' }
    if ($rated -gt 0 -and $speed -gt 0 -and $speed -lt ($rated * 0.9)) { $extra += $(if ($extra -ne '') { '; ' } else { '' }) + 'modules are rated ' + $rated + ' MT/s, so XMP / EXPO may be off in the BIOS' }
    if ($extra -ne '') { Write-Row '' $extra }
    Write-Row '' (Get-RamNote ($total / 1GB))
}

function Get-VideoMemoryGb($Gpu) {
    # Win32_VideoController.AdapterRAM stops at 4 GB, so read the real size from the driver's registry entry when it exists.
    try {
        $pnp = ([string]$Gpu.PNPDeviceID).ToLower()
        $m = [regex]::Match($pnp, 'pci\\ven_[0-9a-f]{4}&dev_[0-9a-f]{4}')
        if ($m.Success) {
            $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
            foreach ($k in @(Get-ChildItem $base -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' })) {
                $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
                if (([string]$p.MatchingDeviceId).ToLower().StartsWith($m.Value)) {
                    $v = $p.'HardwareInformation.qwMemorySize'
                    if ($null -ne $v) {
                        if ($v -is [byte[]]) { $v = [BitConverter]::ToUInt64($v, 0) }
                        if ([double]$v -gt 0) { return [math]::Round([double]$v / 1GB, 0) }
                    }
                }
            }
        }
    } catch { }
    if ($Gpu.AdapterRAM -and [double]$Gpu.AdapterRAM -gt 0) { return [math]::Round([double]$Gpu.AdapterRAM / 1GB, 0) }
    return 0
}

function Show-Graphics {
    $gpus = @(Get-Cim 'Win32_VideoController' | Where-Object { [string]$_.Name -notmatch 'Remote|Virtual|Meta|Parsec|Citrix' })
    if ($gpus.Count -eq 0) { Write-Row 'Graphics card' 'none was reported'; return }
    $first = $true
    foreach ($g in $gpus) {
        $label = $(if ($first) { 'Graphics card' } else { '' })
        $first = $false
        Write-Row $label ([string]$g.Name)
        $parts = @()
        $gb = Get-VideoMemoryGb $g
        if ($gb -gt 0) { $parts += ($gb.ToString() + ' GB video memory') }
        $drv = 'driver ' + [string]$g.DriverVersion
        if ([string]$g.PNPDeviceID -match 'VEN_10DE') { $n = Get-NvidiaDriverNumber ([string]$g.DriverVersion); if ($n -ne '') { $drv = 'NVIDIA driver ' + $n + ' (Windows number ' + [string]$g.DriverVersion + ')' } }
        if ($g.DriverDate) { $drv += ', dated ' + ([datetime]$g.DriverDate).ToString('yyyy-MM-dd') }
        $parts += $drv
        Write-Row '' ($parts -join ', ')
        if ([string]$g.Name -match 'Basic') { Write-Row '' 'This is the basic Windows driver. Games run slowly until the maker driver is installed.' }
        elseif ($gb -gt 0) { $vn = Get-VramNote $gb; if ($vn -ne '') { Write-Row '' $vn } }
    }
}

function Show-Screens {
    $rows = @()
    try { Initialize-DisplayApi; $rows = @([PCOptDisplay]::Describe()) } catch { }
    $names = @()
    try {
        foreach ($mon in @(Get-Cim 'WmiMonitorID' 'root\wmi')) {
            $n = (($mon.UserFriendlyName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join '').Trim()
            if ($n -ne '') { $names += $n }
        }
    } catch { }
    if ($rows.Count -eq 0) { Write-Row 'Screens' 'Windows did not report an active screen to this tool.'; return }
    $i = 0
    foreach ($r in $rows) {
        $i++
        $p = $r -split '\|'
        $line = $p[1] + 'x' + $p[2] + ' at ' + $p[3] + ' Hz'
        if ([int]$p[4] -gt [int]$p[3] + 1) { $line += ' (this screen can do ' + $p[4] + ' Hz: Settings > System > Display > Advanced display)' }
        Write-Row $(if ($i -eq 1) { 'Screens' } else { '' }) ('Screen ' + $i + ': ' + $line)
    }
    if ($names.Count -gt 0) { Write-Row '' ('Monitor models: ' + ($names -join ', ')) }
}

function Show-Storage {
    $disks = @()
    try { $disks = @(Get-PhysicalDisk -ErrorAction Stop | Sort-Object { [int]$_.DeviceId }) } catch { }
    $sysLetter = ([string]$env:SystemDrive).Substring(0, 1)
    $sysDisk = $null
    try { $sysDisk = (Get-Partition -DriveLetter $sysLetter -ErrorAction Stop | Get-Disk -ErrorAction Stop | Select-Object -First 1).Number } catch { }
    if ($disks.Count -eq 0) { Write-Row 'Drives' 'Windows did not report any physical drive.' }
    $first = $true
    $sysMedia = ''
    foreach ($d in $disks) {
        $letters = @()
        try { $letters = @(Get-Partition -DiskNumber ([int]$d.DeviceId) -ErrorAction Stop | Where-Object { $_.DriveLetter } | ForEach-Object { [string]$_.DriveLetter + ':' }) } catch { }
        $bus = $(if ([string]$d.BusType -eq 'NVMe') { 'NVMe SSD' } elseif ([string]$d.MediaType -eq 'SSD') { 'SSD' } elseif ([string]$d.MediaType -eq 'HDD') { 'hard drive (HDD)' } else { [string]$d.MediaType })
        $line = [string]$d.FriendlyName + ', ' + $bus + ', ' + [math]::Round($d.Size / 1GB) + ' GB'
        if ($letters.Count -gt 0) { $line += ' [' + ($letters -join ' ') + ']' }
        if ($null -ne $sysDisk -and [int]$d.DeviceId -eq [int]$sysDisk) { $line += ' <- Windows is here'; $sysMedia = [string]$d.MediaType }
        Write-Row $(if ($first) { 'Drives' } else { '' }) $line
        $first = $false
    }
    $freeLines = @()
    $sysFree = -1.0
    try {
        foreach ($v in @(Get-Volume -ErrorAction Stop | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.Size -gt 0 } | Sort-Object DriveLetter)) {
            $pct = [math]::Round(100.0 * $v.SizeRemaining / $v.Size)
            $freeLines += ([string]$v.DriveLetter + ': ' + [math]::Round($v.SizeRemaining / 1GB) + ' GB free of ' + [math]::Round($v.Size / 1GB) + ' GB (' + $pct + '% free)')
            if ([string]$v.DriveLetter -eq $sysLetter) { $sysFree = $pct }
        }
    } catch { }
    foreach ($l in $freeLines) { Write-Row '' $l }
    foreach ($n in @(Get-StorageNote $sysMedia $sysFree)) { Write-Row '' $n }
}

function Show-Network {
    $ads = @()
    try { $ads = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' }) } catch { }
    if ($ads.Count -eq 0) { Write-Row 'Network' 'no active network adapter'; return }
    $first = $true
    foreach ($a in $ads) {
        $kind = $(if ([string]$a.PhysicalMediaType -match '802\.3') { 'Cable' } elseif ([string]$a.PhysicalMediaType -match '802\.11|Native') { 'Wi-Fi' } else { 'Adapter' })
        $mbps = 0
        try { $mbps = [math]::Round([double]$a.ReceiveLinkSpeed / 1000000, 0) } catch { }
        Write-Row $(if ($first) { 'Network' } else { '' }) ($kind + ': ' + [string]$a.InterfaceDescription + ', link ' + $mbps + ' Mbps')
        $first = $false
        $note = $(if ($kind -eq 'Cable') { Get-LanHint ([string]$a.InterfaceDescription) $mbps } else { '' })
        if ($note -ne '') { Write-Row '' ($note.Substring(0, 1).ToUpper() + $note.Substring(1)) }
    }
}

function Show-Security {
    $sb = 'unknown'
    try {
        $v = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction Stop).UEFISecureBootEnabled
        $sb = $(if ([int]$v -eq 1) { 'on' } else { 'off' })
    } catch { $sb = 'not available (the PC may start in legacy BIOS mode)' }
    Write-Row 'Secure Boot' $sb
    $tpm = 'unknown (run as administrator to see it)'
    try {
        $t = @(Get-CimInstance -Namespace 'root\cimv2\security\microsofttpm' -ClassName Win32_Tpm -ErrorAction Stop) | Select-Object -First 1
        if ($t) {
            $ver = (([string]$t.SpecVersion) -split ',')[0].Trim()
            $tpm = $(if ($t.IsEnabled_InitialValue) { 'present, version ' + $ver + ', enabled' } else { 'present, version ' + $ver + ', turned off' })
        } else { $tpm = 'not found' }
    } catch { }
    Write-Row 'TPM' $tpm
    Write-Row '' 'Windows 11 and some games (for example Valorant on Windows 11) need Secure Boot on and TPM 2.0. If they are off, the switch is in the BIOS.'
}

# ---------------------------------------------------------------- check-up: do the drivers and the settings fit together?
$script:Flags = 0
function Write-Mark([string]$Kind, [string]$Text) {
    if ($Kind -eq 'CHECK') { $script:Flags++; Write-Log ('   [CHECK] ' + $Text) 'Yellow' }
    elseif ($Kind -eq 'OK') { Write-Log ('   [OK]    ' + $Text) 'Green' }
    else { Write-Log ('   [INFO]  ' + $Text) 'Gray' }
}

function ConvertTo-RealDate($Date, [datetime]$Now) {
    # some PCs (Thai regional format) return a driver date 543 years too early; put it back, or give up (null) when it is not plausible
    if ($null -eq $Date) { return $null }
    try { $d = [datetime]$Date } catch { return $null }
    if ($d.Year -ge 1990 -and $d -le $Now.AddDays(2)) { return $d }
    if ($d.Year -lt 1990) {
        $fixed = $d.AddYears(543)
        if ($fixed.Year -ge 1990 -and $fixed -le $Now.AddDays(2)) { return $fixed }
    }
    return $null
}

function Test-OldThirdPartyDriver([string]$Class, [string]$Maker, $Date, [datetime]$Now) {
    # a maker driver for network, graphics, sound or Bluetooth that is more than 4 years old
    $Date = ConvertTo-RealDate $Date $Now
    if ($null -eq $Date) { return $false }
    if (@('NET', 'DISPLAY', 'MEDIA', 'BLUETOOTH') -notcontains $Class.ToUpper()) { return $false }
    if ($Maker -match 'Microsoft') { return $false }
    return (($Now - [datetime]$Date).TotalDays -gt (4 * 365))
}

function Get-OptimizerSummary($Items) {
    $all = @($Items)
    $auto = @($all | Where-Object { [string]$_.Key -like 'REG*' -and [string]$_.Kind -eq 'auto' })
    $notApplied = ($auto.Count -gt 0 -and @($auto | Where-Object { $_.Status -eq 'MISSING' -or $_.Status -eq 'CHANGED' }).Count -eq $auto.Count)
    return @{
        Total = $all.Count
        Ok = @($all | Where-Object { $_.Status -eq 'OK' }).Count
        Bad = @($all | Where-Object { $_.Status -eq 'CHANGED' -or $_.Status -eq 'MISSING' })
        Skipped = @($all | Where-Object { $_.Status -eq 'SKIPPED' -or $_.Status -eq 'NOT CHOSEN' }).Count
        NotApplied = $notApplied
    }
}

function Show-Consistency {
    Write-Log '   Check-up: do the drivers and the settings fit together?' 'White'
    Write-Log '   Drivers' 'White'
    # devices with a driver problem
    $skipCodes = @(0, 22, 24, 45)
    $bad = @(Get-Cim 'Win32_PnPEntity' | Where-Object { ($skipCodes -notcontains [int]$_.ConfigManagerErrorCode) -and ([string]$_.PNPDeviceID -notmatch '^(SWD|ROOT)\\') })
    if ($bad.Count -eq 0) { Write-Mark 'OK' 'Every device has a working driver.' }
    else {
        $names = @($bad | ForEach-Object { if ([string]$_.Name -ne '') { [string]$_.Name } else { 'unknown device' } } | Select-Object -Unique -First 5)
        Write-Mark 'CHECK' ($bad.Count.ToString() + ' device(s) have a driver problem: ' + ($names -join ', ') + '. Run 7_Driver_Check (menu D).')
    }
    # graphics driver from the maker
    foreach ($g in @(Get-Cim 'Win32_VideoController' | Where-Object { [string]$_.Name -notmatch 'Remote|Virtual|Meta|Parsec|Citrix' })) {
        if ([string]$g.Name -match 'Basic') { Write-Mark 'CHECK' ([string]$g.Name + ' uses the basic Windows driver. Install the maker driver (menu D opens the right page).'); continue }
        $months = $null
        if ($g.DriverDate) { $months = [int][math]::Floor(((Get-Date) - [datetime]$g.DriverDate).TotalDays / 30.4) }
        if ($null -ne $months -and $months -ge 6) { Write-Mark 'INFO' ([string]$g.Name + ': the driver is ' + $months + ' months old. A newer one from the maker may help new games.') }
        else { Write-Mark 'OK' ([string]$g.Name + ': a current maker driver is installed.') }
    }
    # old third-party drivers
    $old = @()
    try {
        $now = Get-Date
        foreach ($d in @(Get-Cim 'Win32_PnPSignedDriver')) {
            if ([string]$d.DeviceName -ne '' -and (Test-OldThirdPartyDriver ([string]$d.DeviceClass) ([string]$d.Manufacturer) $d.DriverDate $now)) { $old += ([string]$d.DeviceName + ' (' + (ConvertTo-RealDate $d.DriverDate $now).Year + ')') }
        }
    } catch { }
    $old = @($old | Select-Object -Unique)
    if ($old.Count -eq 0) { Write-Mark 'OK' 'No network, graphics, sound or Bluetooth driver is older than 4 years.' }
    else { Write-Mark 'INFO' ('Older than 4 years: ' + (($old | Select-Object -First 5) -join ', ') + '. Old is not always bad; look at it if that part gives trouble.') }

    Write-Log '   Settings' 'White'
    # the optimizer's own settings
    $items = $null
    try {
        $csPath = Join-Path $PSScriptRoot 'Check_Status.ps1'
        $rootDir = Split-Path -Parent $PSScriptRoot
        $items = & {
            . $csPath -Root $rootDir
            Invoke-Checks (Join-Path $rootDir 'reg') (Join-Path ([IO.Path]::GetTempPath()) 'pcopt_specs_unused')
            $script:Items
        }
    } catch { }
    if ($null -eq $items) { Write-Mark 'INFO' 'The optimizer settings could not be checked here.' }
    else {
        $s = Get-OptimizerSummary $items
        if ($s.NotApplied) { Write-Mark 'INFO' 'The optimizer settings have not been applied on this PC yet (main menu option 5). Nothing is wrong; they are optional.' }
        elseif ($s.Bad.Count -eq 0) { Write-Mark 'OK' ('All ' + $s.Ok + ' optimizer settings that apply are in place.') }
        else { Write-Mark 'CHECK' ($s.Bad.Count.ToString() + ' optimizer setting(s) changed back (Windows updates can do that): ' + ((@($s.Bad | ForEach-Object { [string]$_.Title }) | Select-Object -First 5) -join ', ') + '. Press C in the main menu to put them back.') }
    }
    # screens at their highest refresh rate
    $rows = @()
    try { Initialize-DisplayApi; $rows = @([PCOptDisplay]::Describe()) } catch { }
    $slow = @(); $n = 0
    foreach ($row in $rows) { $n++; $p = $row -split '\|'; if ((Get-RefreshHint ([int]$p[3]) ([int]$p[4])) -ne '') { $slow += ('screen ' + $n + ' runs at ' + $p[3] + ' Hz but can do ' + $p[4] + ' Hz') } }
    if ($rows.Count -gt 0) { if ($slow.Count -eq 0) { Write-Mark 'OK' 'Every screen runs at its highest refresh rate.' } else { Write-Mark 'CHECK' (($slow -join '; ') + '. Settings > System > Display > Advanced display.') } }
    # memory at its rated speed
    $mods = @(Get-Cim 'Win32_PhysicalMemory')
    if ($mods.Count -gt 0) {
        $run = 0; $rated = 0
        foreach ($m in $mods) { if ([int]$m.ConfiguredClockSpeed -gt $run) { $run = [int]$m.ConfiguredClockSpeed }; if ([int]$m.Speed -gt $rated) { $rated = [int]$m.Speed } }
        $rh = @(Get-RamHint $run $rated $mods.Count)
        if ($rh.Count -eq 0) { Write-Mark 'OK' 'The memory runs at its rated speed.' } else { foreach ($h in $rh) { Write-Mark 'CHECK' ($h.Substring(0, 1).ToUpper() + $h.Substring(1) + '.') } }
    }
    # cable speed
    foreach ($a in @(try { Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' -and [string]$_.PhysicalMediaType -match '802\.3' } } catch { })) {
        $mbps = 0; try { $mbps = [math]::Round([double]$a.ReceiveLinkSpeed / 1000000, 0) } catch { }
        $lh = Get-LanHint ([string]$a.InterfaceDescription) $mbps
        if ($lh -eq '') { Write-Mark 'OK' ('The cable link of ' + [string]$a.Name + ' runs at ' + $mbps + ' Mbps, as the adapter allows.') } else { Write-Mark 'CHECK' ($lh.Substring(0, 1).ToUpper() + $lh.Substring(1) + '.') }
    }
    Write-Log ''
    if ($script:Flags -eq 0) { Write-Log '   Everything fits together.' 'Green' } else { Write-Log ('   ' + $script:Flags + ' item(s) are worth a look (marked CHECK).') 'Yellow' }
}
# ---------------------------------------------------------------- main
function Start-PcSpecs {
    $rootDir = ''
    if ($Root -ne '') { try { $rootDir = (Resolve-Path -LiteralPath $Root).Path } catch { } }
    Write-Log '==================================================================' 'Cyan'
    Write-Log '   PC OPTIMIZER v4.17 - YOUR PC ON ONE PAGE (nothing is changed)' 'Cyan'
    Write-Log ('   ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')) 'Cyan'
    Write-Log '==================================================================' 'Cyan'
    Write-Log ''
    Write-Log '   Reading the hardware and checking the settings, about 15-30 seconds. No key press is needed...' 'DarkGray'
    Write-Log ''
    Show-Computer
    Show-Windows
    Write-Log ''
    Show-Processor
    Show-Memory
    Write-Log ''
    Show-Graphics
    Show-Screens
    Write-Log ''
    Show-Storage
    Write-Log ''
    Show-Network
    Write-Log ''
    Show-Security
    Write-Log ''
    Show-Consistency
    Write-Log ''
    Write-Log '   The notes under each part are general guidelines, not verdicts: what counts as enough depends on the games you play.' 'DarkGray'
    Write-Log '   No serial numbers, MAC addresses or IP addresses are shown, so this page can be shared when you ask for help.' 'DarkGray'
    if ($rootDir -ne '') {
        try { [IO.File]::WriteAllLines((New-ReportPath $rootDir 'PCSpecs'), $script:Lines); Remove-OldReports $rootDir | Out-Null } catch { }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Start-PcSpecs
    exit 0
}
