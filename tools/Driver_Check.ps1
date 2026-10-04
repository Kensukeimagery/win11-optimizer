# PC Optimizer - driver check (BETA)
# 1. Scans: devices with no working driver, the graphics card, and the driver updates Windows Update offers.
# 2. Asks what to do. Nothing is installed unless you choose it.
# Installing uses Windows Update (Microsoft-signed drivers), after a restore point and a copy of your current drivers.
# Graphics, chipset, BIOS and firmware are NOT installed automatically: the tool tells you where to get them.
#   -SkipUpdateSearch  scan only the PC itself (no internet, used for testing)
#   -NoPrompt          print the report and stop
#   -DryRun            show what would be installed and install nothing
param(
    [string]$Root = '',
    [switch]$SkipUpdateSearch,
    [switch]$NoPrompt,
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'
$script:Lines = New-Object System.Collections.Generic.List[string]
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
function Test-IsAdmin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Read-Answer([string]$Prompt, [string[]]$Allowed) {
    # Enter or closed input means the first (safe) answer.
    for ($try = 0; $try -lt 20; $try++) {
        $raw = Read-Host $Prompt
        if ($null -eq $raw) { break }
        $a = ([string]$raw).Trim().ToUpper()
        if ($a -eq '') { $a = $Allowed[0] }
        if ($Allowed -contains $a) { return $a }
        Write-Host ('   Please type one of: ' + ($Allowed -join ', ')) -ForegroundColor DarkYellow
    }
    return $Allowed[0]
}

# ---------------------------------------------------------------- rules (kept simple and testable)
$script:ImportantClasses = @('Display', 'Net', 'WLAN', 'Media', 'Bluetooth', 'System', 'SCSIAdapter', 'HDC', 'USB', 'Camera', 'Image', 'Biometric', 'SoftwareComponent')

function Get-OfferCategory([string]$Class, [string]$Title, $WuDate, $InstalledDate, [bool]$VendorGpuInstalled) {
    # Returns a hashtable: Category = recommended | optional | skip, Reason = text for skip.
    if ($Class -eq 'Firmware' -or $Title -match 'Firmware') {
        return @{ Category = 'skip'; Reason = 'firmware: use the maker tool, a wrong firmware can stop the PC from starting' }
    }
    if ($Class -eq 'Display' -and $VendorGpuInstalled) {
        return @{ Category = 'skip'; Reason = 'your graphics driver comes from the maker, use the maker page below (Windows Update can be older)' }
    }
    if ($null -ne $InstalledDate -and $null -ne $WuDate -and $WuDate -le $InstalledDate) {
        return @{ Category = 'skip'; Reason = 'not newer than the driver you already have' }
    }
    if ($script:ImportantClasses -contains $Class) { return @{ Category = 'recommended'; Reason = '' } }
    return @{ Category = 'optional'; Reason = '' }
}

function Get-ProblemText([int]$Code) {
    switch ($Code) {
        28 { return 'no driver is installed' }
        10 { return 'the device cannot start' }
        31 { return 'the device is not working properly' }
        39 { return 'the driver is damaged or missing' }
        43 { return 'Windows stopped the device because it reported a problem' }
        52 { return 'the driver is not signed' }
        default { return ('the device has a problem, code ' + $Code) }
    }
}

# ---------------------------------------------------------------- scanning
function Get-ProblemDevices {
    $skipCodes = @(0, 22, 24, 45)   # 22 disabled by you, 24 not present, 45 not connected: not a driver problem
    $out = @()
    try {
        # SWD and ROOT entries are software components (audio effect packs and the like), not hardware that needs a driver.
        foreach ($d in @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop | Where-Object { ($skipCodes -notcontains [int]$_.ConfigManagerErrorCode) -and ([string]$_.PNPDeviceID -notmatch '^(SWD|ROOT)\\') })) {
            $name = [string]$d.Name
            if ($name -eq '') { $name = 'Unknown device (' + [string]$d.PNPDeviceID + ')' }
            $out += [pscustomobject]@{ Name = $name; Code = [int]$d.ConfigManagerErrorCode; Class = [string]$d.PNPClass; Id = [string]$d.PNPDeviceID }
        }
    } catch { }
    return $out
}

function Get-GpuInfo {
    $list = @()
    try {
        foreach ($g in @(Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { $_.Name -notmatch 'Remote|Virtual|Meta' })) {
            $vendor = 'unknown'
            $pnp = [string]$g.PNPDeviceID
            if ($pnp -match 'VEN_10DE') { $vendor = 'NVIDIA' } elseif ($pnp -match 'VEN_1002|VEN_1022') { $vendor = 'AMD' } elseif ($pnp -match 'VEN_8086') { $vendor = 'Intel' }
            $basic = ([string]$g.Name -match 'Basic')
            $months = $null
            if ($g.DriverDate) { $months = [int][math]::Floor(((Get-Date) - $g.DriverDate).TotalDays / 30.4) }
            $list += [pscustomobject]@{ Name = [string]$g.Name; Version = [string]$g.DriverVersion; Date = $g.DriverDate; Months = $months; Vendor = $vendor; Basic = $basic }
        }
    } catch { }
    return $list
}

function Get-InstalledDriverIndex {
    $idx = @{}
    try {
        foreach ($d in @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop)) {
            foreach ($id in @($d.HardWareID, $d.CompatID)) { if ($id) { $idx[([string]$id).ToUpper()] = $d } }
        }
    } catch { }
    return $idx
}

function Get-DriverOffers([bool]$VendorGpuInstalled) {
    $session = New-Object -ComObject Microsoft.Update.Session
    $result = $session.CreateUpdateSearcher().Search("IsInstalled=0 and Type='Driver' and IsHidden=0")
    $index = Get-InstalledDriverIndex
    $offers = @()
    for ($i = 0; $i -lt $result.Updates.Count; $i++) {
        $u = $result.Updates.Item($i)
        $hw = [string]$u.DriverHardwareID
        $inst = $null
        if ($hw -ne '' -and $index.ContainsKey($hw.ToUpper())) { $inst = $index[$hw.ToUpper()] }
        $instDate = $null
        if ($null -ne $inst -and $inst.DriverDate) { $instDate = $inst.DriverDate }
        $cat = Get-OfferCategory ([string]$u.DriverClass) ([string]$u.Title) $u.DriverVerDate $instDate $VendorGpuInstalled
        $offers += [pscustomobject]@{ Update = $u; Title = [string]$u.Title; Class = [string]$u.DriverClass; Maker = [string]$u.DriverManufacturer; Date = $u.DriverVerDate; SizeMb = [math]::Round($u.MaxDownloadSize / 1MB, 1); Category = $cat.Category; Reason = $cat.Reason }
    }
    return @{ Session = $session; Offers = $offers }
}

# ---------------------------------------------------------------- install
function Install-Offers($Session, $Chosen, [string]$RootDir) {
    if ($Chosen.Count -eq 0) { Write-Log '   Nothing selected.' 'DarkGray'; return }
    if ($DryRun) {
        Write-Log '   [DRY RUN] These would be installed:' 'Yellow'
        foreach ($o in $Chosen) { Write-Log ('     - ' + $o.Title) }
        return
    }
    if (-not (Test-IsAdmin)) {
        Write-Log '   [ERROR] Installing drivers needs administrator rights. Run 7_Driver_Check as administrator. Nothing was changed.' 'Red'
        return
    }
    Write-Log ''
    Write-Log '   Step 1 of 3: restore point (so you can go back)' 'White'
    $rp = Join-Path $PSScriptRoot 'Create_Restore_Point.ps1'
    $rpOk = $false
    if (Test-Path -LiteralPath $rp) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $rp -TimeoutSeconds 600 -Description 'Before_Driver_Install'
        $rpOk = ($LASTEXITCODE -eq 0)
    }
    if ($rpOk) { Write-Log '   [OK] Restore point created (named Before_Driver_Install).' 'Green' }
    else {
        Write-Log '   [WARNING] A restore point could not be created.' 'Yellow'
        $go = Read-Answer '   Install drivers without a restore point? Y/N (Enter = N)' @('N', 'Y')
        if ($go -ne 'Y') { Write-Log '   Stopped. Nothing was changed.' 'DarkGray'; return }
    }
    Write-Log ''
    Write-Log '   Step 2 of 3: saving a copy of your current drivers (about 1 to 5 GB and a few minutes)' 'White'
    $backup = ''
    if ($RootDir -ne '') { $backup = Join-Path $RootDir ('Backup\drivers_' + (Get-Date -Format 'yyyyMMdd_HHmmss')) }
    if ($backup -ne '') {
        $freeGb = $null
        try { $freeGb = [math]::Round((New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($backup))).AvailableFreeSpace / 1GB, 1) } catch { }
        if ($null -ne $freeGb -and $freeGb -lt 10) {
            Write-Log ('   [WARNING] Only ' + $freeGb + ' GB are free where the copy would go. The copy needs up to about 5 GB.') 'Yellow'
            $go3 = Read-Answer '   Continue without saving a copy of the drivers? Y/N (Enter = N)' @('N', 'Y')
            if ($go3 -ne 'Y') { Write-Log '   Stopped. Nothing was changed.' 'DarkGray'; return }
            $backup = ''
        }
    }
    if ($backup -ne '') {
        try {
            New-Item -ItemType Directory -Force -Path $backup | Out-Null
            Export-WindowsDriver -Online -Destination $backup -ErrorAction Stop | Out-Null
            Write-Log ('   [OK] Saved to Backup\' + (Split-Path -Leaf $backup)) 'Green'
        } catch {
            Write-Log ('   [WARNING] Could not save a copy of the drivers: ' + $_.Exception.Message) 'Yellow'
            $go2 = Read-Answer '   Continue anyway? Y/N (Enter = N)' @('N', 'Y')
            if ($go2 -ne 'Y') { Write-Log '   Stopped. Nothing was changed.' 'DarkGray'; return }
        }
    }
    Write-Log ''
    Write-Log ('   Step 3 of 3: installing ' + $Chosen.Count + ' driver(s) one at a time') 'White'
    $okCount = 0; $failCount = 0; $reboot = $false
    $n = 0
    foreach ($o in $Chosen) {
        $n++
        Write-Log ('   [' + $n + '/' + $Chosen.Count + '] ' + $o.Title) 'Gray'
        try {
            $u = $o.Update
            if (-not $u.EulaAccepted) { $u.AcceptEula() }
            $coll = New-Object -ComObject Microsoft.Update.UpdateColl
            [void]$coll.Add($u)
            $dl = $Session.CreateUpdateDownloader(); $dl.Updates = $coll
            $dres = $dl.Download()
            if ($dres.ResultCode -ne 2) { throw ('download result ' + $dres.ResultCode) }
            $ins = $Session.CreateUpdateInstaller(); $ins.Updates = $coll
            $ires = $ins.Install()
            if ($ires.ResultCode -eq 2 -or $ires.ResultCode -eq 3) {
                $okCount++
                if ($ires.RebootRequired) { $reboot = $true }
                Write-Log ('       [OK] installed' + $(if ($ires.RebootRequired) { ' (restart needed)' } else { '' })) 'Green'
            } else {
                $failCount++
                Write-Log ('       [FAILED] result code ' + $ires.ResultCode) 'Red'
            }
        } catch {
            $failCount++
            Write-Log ('       [FAILED] ' + $_.Exception.Message) 'Red'
        }
    }
    Write-Log ''
    Write-Log ('   Done: ' + $okCount + ' installed, ' + $failCount + ' failed.') 'White'
    if ($okCount -gt 0) { Write-Log '   Restart the PC now so the new drivers load. The tool never restarts it for you.' 'Yellow' }
    Write-Log '   If something stops working: Device Manager > the device > Properties > Driver > Roll Back Driver, or System Restore (2_Revert_Everything), or reinstall from the saved copy in Backup\drivers_*.' 'DarkGray'
}

# ---------------------------------------------------------------- main
function Start-DriverCheck {
    $rootDir = ''
    if ($Root -ne '') { try { $rootDir = (Resolve-Path -LiteralPath $Root).Path } catch { } }

    Write-Log '==================================================================' 'Cyan'
    Write-Log '   PC OPTIMIZER - DRIVER CHECK (BETA)' 'Cyan'
    Write-Log ('   ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')) 'Cyan'
    Write-Log '==================================================================' 'Cyan'
    Write-Log ''
    Write-Log '   Scanning, please wait. No key press is needed...' 'DarkGray'

    $problems = @(Get-ProblemDevices)
    $gpus = @(Get-GpuInfo)
    $vendorGpu = (@($gpus | Where-Object { -not $_.Basic -and $_.Vendor -ne 'unknown' }).Count -gt 0)

    Write-Log ''
    Write-Log '   A. Devices with no working driver' 'White'
    if ($problems.Count -eq 0) { Write-Log '     None. Every device has a working driver.' 'Green' }
    foreach ($p in $problems) { Write-Log ('     - ' + $p.Name + ': ' + (Get-ProblemText $p.Code)) 'Yellow' }

    Write-Log ''
    Write-Log '   B. Graphics card' 'White'
    if ($gpus.Count -eq 0) { Write-Log '     No graphics card was reported.' }
    foreach ($g in $gpus) {
        $age = ''
        if ($null -ne $g.Months) { $age = ', driver ' + $g.Months + ' months old' }
        Write-Log ('     ' + $g.Name + ', version ' + $g.Version + $age)
        if ($g.Basic) { Write-Log '       This is the basic Windows driver. Games will run slowly until you install the maker driver (page below).' 'Yellow' }
        elseif ($null -ne $g.Months -and $g.Months -ge 6) { Write-Log '       This driver is 6 months old or more. A newer one from the maker may help new games.' 'Yellow' }
    }
    $urls = @{ 'NVIDIA' = 'https://www.nvidia.com/Download/index.aspx'; 'AMD' = 'https://www.amd.com/en/support/download/drivers.html'; 'Intel' = 'https://www.intel.com/content/www/us/en/support/detect.html' }
    $gpuVendors = @($gpus | ForEach-Object { $_.Vendor } | Where-Object { $urls.ContainsKey($_) } | Select-Object -Unique)
    foreach ($v in $gpuVendors) { Write-Log ('     Official ' + $v + ' drivers: ' + $urls[$v]) 'Gray' }

    $offers = @()
    $session = $null
    $searchOk = $false
    Write-Log ''
    Write-Log '   C. Driver updates from Windows Update' 'White'
    if ($SkipUpdateSearch) {
        Write-Log '     Skipped (scan only).' 'DarkGray'
    } else {
        Write-Log '     Searching Windows Update, about 15-60 seconds...' 'DarkGray'
        try {
            $r = Get-DriverOffers $vendorGpu
            $offers = @($r.Offers); $session = $r.Session; $searchOk = $true
        } catch {
            Write-Log ('     Could not search Windows Update: ' + $_.Exception.Message) 'Yellow'
            Write-Log '     Check your internet connection. On a fresh Windows with no network driver, get the network driver from your motherboard or laptop maker first (use another PC and a USB drive).' 'Yellow'
        }
    }
    $rec = @($offers | Where-Object { $_.Category -eq 'recommended' })
    $opt = @($offers | Where-Object { $_.Category -eq 'optional' })
    $skip = @($offers | Where-Object { $_.Category -eq 'skip' })
    $optGroups = @($opt | Group-Object { $_.Maker + '|' + $_.Class })
    if ($searchOk) {
        if ($offers.Count -eq 0) { Write-Log '     Windows Update has no driver updates for this PC.' 'Green' }
        if ($rec.Count -gt 0) {
            Write-Log ('     Recommended (' + $rec.Count + '): network, audio, Bluetooth, chipset, USB and similar') 'Yellow'
            $k = 0; foreach ($o in $rec) { $k++; Write-Log ('       ' + $k + '. ' + $o.Title + ' [' + $o.Class + ', ' + $o.SizeMb + ' MB]') }
        }
        if ($opt.Count -gt 0) {
            Write-Log ('     Optional, low impact (' + $opt.Count + '): other hardware such as monitors and processor sub-devices, grouped by maker') 'DarkYellow'
            foreach ($grp in $optGroups) {
                $first = $grp.Group[0]
                $what = $first.Maker + ' / ' + $first.Class
                if ($grp.Count -eq 1) { $what = $first.Title }
                Write-Log ('       ' + $grp.Count + ' x ' + $what) 'Gray'
            }
        }
        if ($skip.Count -gt 0) {
            Write-Log ('     Not offered by this tool (' + $skip.Count + '):') 'DarkGray'
            foreach ($grp in ($skip | Group-Object Reason)) { Write-Log ('       ' + $grp.Count + ' x ' + $grp.Name) 'DarkGray' }
        }
    }

    Write-Log ''
    Write-Log '   D. Other advice' 'White'
    $board = ''
    try { $b = Get-CimInstance Win32_BaseBoard; $board = ([string]$b.Manufacturer + ' ' + [string]$b.Product).Trim() } catch { }
    if ($board -ne '') { Write-Log ('     For chipset, BIOS and Wi-Fi/LAN drivers, the best source is the support page of your board or laptop: ' + $board) }
    Write-Log '     Avoid driver-updater programs. They often install wrong or unsigned drivers.'
    Write-Log '     Settings > Windows Update > Advanced options > Optional updates shows the same Windows Update drivers.'

    # report file
    if ($rootDir -ne '') {
        try {
            $file = Join-Path $rootDir ('DriverReport_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.txt')
            [IO.File]::WriteAllLines($file, $script:Lines)
        } catch { }
    }

    if ($NoPrompt) { return }
    Write-Log ''
    $choices = New-Object System.Collections.Generic.List[string]
    $choices.Add('N')
    if ($gpuVendors.Count -gt 0) { $choices.Add('G') }
    if ($rec.Count -gt 0) { $choices.Add('A') }
    if (($rec.Count + $opt.Count) -gt 0) { $choices.Add('S') }
    if ($opt.Count -gt 0) { $choices.Add('E') }
    if ($choices.Count -eq 1) { Write-Log '   Nothing to do. Your drivers look fine.' 'Green'; return }
    Write-Host '   What would you like to do? Nothing is installed unless you choose.' -ForegroundColor White
    if ($rec.Count -gt 0) { Write-Host ('   A = install the ' + $rec.Count + ' recommended drivers') }
    if ($opt.Count -gt 0) { Write-Host ('   E = install everything listed, recommended and optional (' + ($rec.Count + $opt.Count) + ')') }
    if (($rec.Count + $opt.Count) -gt 0) { Write-Host '   S = let me choose one by one' }
    if ($gpuVendors.Count -gt 0) { Write-Host '   G = open the official graphics driver page in my browser' }
    Write-Host '   N = do nothing (default)'
    $ans = Read-Answer '   Your choice (Enter = N)' @($choices.ToArray())
    if ($ans -eq 'N') { Write-Log '   Nothing was changed.' 'DarkGray'; return }
    if ($ans -eq 'G') {
        foreach ($v in $gpuVendors) { try { Start-Process $urls[$v] } catch { } }
        return
    }
    $chosen = @()
    if ($ans -eq 'A') { $chosen = $rec }
    if ($ans -eq 'E') { $chosen = @($rec) + @($opt) }
    if ($ans -eq 'S') {
        $stop = $false
        foreach ($o in $rec) {
            $yn = Read-Answer ('   Install "' + $o.Title + '"? Y/N, Q = stop asking (Enter = N)') @('N', 'Y', 'Q')
            if ($yn -eq 'Q') { $stop = $true; break }
            if ($yn -eq 'Y') { $chosen += $o }
        }
        if (-not $stop) {
            foreach ($grp in $optGroups) {
                $first = $grp.Group[0]
                $yn = Read-Answer ('   Install the ' + $grp.Count + ' optional driver(s) from ' + $first.Maker + ' (' + $first.Class + ')? Y/N, Q = stop asking (Enter = N)') @('N', 'Y', 'Q')
                if ($yn -eq 'Q') { break }
                if ($yn -eq 'Y') { $chosen += @($grp.Group) }
            }
        }
    }
    Write-Log ('   You selected ' + @($chosen).Count + ' driver(s).') 'White'
    Install-Offers $session $chosen $rootDir
    if ($rootDir -ne '') { try { [IO.File]::WriteAllLines((Join-Path $rootDir ('DriverReport_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '_after.txt')), $script:Lines) } catch { } }
}

if ($MyInvocation.InvocationName -ne '.') {
    Start-DriverCheck
    exit 0
}
