# PC Optimizer - driver cleanup (BETA)
# Finds two kinds of leftovers and removes them ONLY if you choose:
#   1. Old versions of a driver that Windows keeps in its driver store (the newest version and any version in use are always kept).
#   2. Entries of devices that are no longer connected (old USB devices, monitors and the like).
# It does not guess which driver "looks unused": a driver package for hardware that is not plugged in right now is only listed in the manual, never removed.
# Before anything is removed: a restore point (Before_Driver_Cleanup) and a copy of each driver package that is about to go.
# Nothing is forced: if Windows says a driver is still in use, it stays.
#   -NoPrompt  print the report and stop
#   -DryRun    show what would be removed and remove nothing
param(
    [string]$Root = '',
    [switch]$NoPrompt,
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'Report_Files.ps1')
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

# ---------------------------------------------------------------- rules (pure functions, tested without touching the PC)
# Device classes whose absent entries are safe to remove. Network adapters, storage and system devices are never in this list:
# removing an absent network adapter forgets its settings, and the others are not worth any risk.
$script:GhostRemovable = @('USB', 'WPD', 'Monitor', 'DiskDrive', 'HIDClass', 'Keyboard', 'Mouse', 'CDROM')

function Test-GhostRemovable([string]$Class) { return ($script:GhostRemovable -contains $Class) }

function ConvertTo-VersionSafe($Text) {
    try { return [version][string]$Text } catch { return [version]'0.0' }
}

# Bluetooth devices are often only switched off, and removing their entry can mean pairing again. They are never offered.
function Test-GhostBluetooth([string]$InstanceId) {
    return ($InstanceId -match '^BTH' -or $InstanceId -match '^HID\\\{0000(1124|1812)-0000-1000-8000-00805F9B34FB\}')
}

function Format-Mb($Mb) {
    if ($null -eq $Mb) { return '?' }
    if ([double]$Mb -lt 0.1) { return '<0.1' }
    return [string]$Mb
}

function Get-StaleCandidates($Packages, $InUseInfs) {
    # Packages: objects with Inf, Original, Provider, Class, Version, Date, Boot.
    # A package is a candidate only when a NEWER package of the same driver (same original file name, maker and class) exists,
    # it is not boot critical and no device uses it right now.
    # Left alone on purpose: packages from Microsoft (Windows manages them), and groups where the highest version number is not
    # also the newest date (the maker changed its numbering, so "newest" is a guess).
    $inUse = @{}
    foreach ($i in @($InUseInfs)) { if ($i) { $inUse[([string]$i).ToLower()] = $true } }
    $out = @()
    $script:SkippedGroups = @()
    $groups = @($Packages | Group-Object { ([string]$_.Original).ToLower() + '|' + [string]$_.Provider + '|' + [string]$_.Class })
    foreach ($g in $groups) {
        if ($g.Count -lt 2) { continue }
        $first = $g.Group[0]
        if ([string]$first.Provider -match '^Microsoft') { $script:SkippedGroups += ($first.Original + ' (Microsoft)'); continue }
        $sorted = @($g.Group | Sort-Object @{ Expression = { ConvertTo-VersionSafe $_.Version }; Descending = $true }, @{ Expression = { $_.Date }; Descending = $true })
        $newest = $sorted[0]
        $latestDate = ($g.Group | ForEach-Object { [datetime]$_.Date } | Measure-Object -Maximum).Maximum
        if ([datetime]$newest.Date -lt $latestDate) { $script:SkippedGroups += ($first.Original + ' (version and date disagree)'); continue }
        foreach ($p in @($sorted | Select-Object -Skip 1)) {
            if ($p.Boot) { continue }
            if ($inUse.ContainsKey(([string]$p.Inf).ToLower())) { continue }
            $out += [pscustomobject]@{ Package = $p; KeepInf = [string]$newest.Inf; KeepVersion = [string]$newest.Version }
        }
    }
    return $out
}

# ---------------------------------------------------------------- packages Windows refused to remove
# Windows sometimes says a package is "still needed" (for example a driver extension). Offering it again every time would make a
# restore point and a copy for nothing, so a refused package is remembered and left out for 30 days, then tried once more.
$script:StateKey = 'HKCU:\Software\PCOptimizer'
$script:KeptValueName = 'CleanKept'
$script:KeptDays = 30

function Get-PackageKey($P) {
    $d = ([datetime]$P.Date).ToString('yyyyMMdd', [Globalization.CultureInfo]::InvariantCulture)
    return (([string]$P.Inf + '|' + [string]$P.Original + '|' + [string]$P.Provider + '|' + [string]$P.Version + '|' + $d).ToLower())
}

function Split-RefusedCandidates($Cands, $Kept, [datetime]$Now) {
    # Kept: hashtable key -> the day Windows refused. Fresh = offer now, Known = refused within the last KeptDays days.
    $fresh = @(); $known = @()
    foreach ($c in @($Cands)) {
        $k = Get-PackageKey $c.Package
        if ($Kept.ContainsKey($k) -and (($Now - [datetime]$Kept[$k]).TotalDays -lt $script:KeptDays)) { $known += $c } else { $fresh += $c }
    }
    return @{ Fresh = $fresh; Known = $known }
}

function Get-RefusedMap {
    $map = @{}
    try {
        $v = (Get-ItemProperty -Path $script:StateKey -Name $script:KeptValueName -ErrorAction Stop).($script:KeptValueName)
        foreach ($line in @($v)) {
            $parts = ([string]$line) -split "`t"
            if ($parts.Count -eq 2) { try { $map[$parts[0]] = [datetime]::ParseExact($parts[1], 'yyyyMMdd', [Globalization.CultureInfo]::InvariantCulture) } catch { } }
        }
    } catch { }
    return $map
}

function Save-RefusedPackages($Refused) {
    if (@($Refused).Count -eq 0) { return }
    $now = Get-Date
    $map = Get-RefusedMap
    foreach ($c in @($Refused)) { $map[(Get-PackageKey $c.Package)] = $now }
    $lines = @()
    foreach ($k in @($map.Keys)) {
        if (($now - [datetime]$map[$k]).TotalDays -lt $script:KeptDays) { $lines += ($k + "`t" + ([datetime]$map[$k]).ToString('yyyyMMdd', [Globalization.CultureInfo]::InvariantCulture)) }
    }
    try {
        if (-not (Test-Path $script:StateKey)) { New-Item -Path $script:StateKey -Force | Out-Null }
        Set-ItemProperty -Path $script:StateKey -Name $script:KeptValueName -Value ([string[]]$lines) -Type MultiString
    } catch { }
}

# ---------------------------------------------------------------- scanning
function Get-DriverPackages {
    $list = @()
    foreach ($d in @(Get-WindowsDriver -Online -All -ErrorAction Stop)) {
        $inf = [string]$d.Driver
        if ($inf -notmatch '^oem\d+\.inf$') { continue }   # only third-party packages; the ones that come with Windows are never touched
        $orig = [string]$d.OriginalFileName
        $dir = ''
        if ($orig -ne '') { try { $dir = Split-Path -Parent $orig } catch { } }
        $list += [pscustomobject]@{
            Inf = $inf; Original = $(if ($orig -ne '') { Split-Path -Leaf $orig } else { $inf }); Provider = [string]$d.ProviderName
            Class = [string]$d.ClassName; Version = [string]$d.Version; Date = $d.Date; Boot = [bool]$d.BootCritical; Dir = $dir
        }
    }
    return $list
}

function Get-InUseInfs {
    $out = @()
    try { foreach ($d in @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop)) { if ($d.InfName) { $out += [string]$d.InfName } } } catch { }
    return $out
}

function Get-FolderMb([string]$Dir) {
    # $null means the size is not known (folder not found), which is shown as "?"
    if ($Dir -eq '' -or -not (Test-Path -LiteralPath $Dir)) { return $null }
    $sum = 0
    try { $sum = (Get-ChildItem -LiteralPath $Dir -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum } catch { }
    if ($null -eq $sum) { return 0 }
    return [math]::Round($sum / 1MB, 1)
}

function Get-GhostDevices {
    $out = @()
    try { foreach ($d in @(Get-PnpDevice -ErrorAction Stop | Where-Object { $_.Status -eq 'Unknown' })) { $out += $d } } catch { }
    return $out
}

# ---------------------------------------------------------------- actions
function New-RestorePoint {
    $rp = Join-Path $PSScriptRoot 'Create_Restore_Point.ps1'
    $ok = $false
    if (Test-Path -LiteralPath $rp) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $rp -TimeoutSeconds 600 -Description 'Before_Driver_Cleanup'
        $ok = ($LASTEXITCODE -eq 0)
    }
    if ($ok) { Write-Log '   [OK] Restore point created (named Before_Driver_Cleanup).' 'Green'; return $true }
    Write-Log '   [WARNING] A restore point could not be created.' 'Yellow'
    $go = Read-Answer '   Continue without a restore point? Y/N (Enter = N)' @('N', 'Y')
    if ($go -ne 'Y') { Write-Log '   Stopped. Nothing was changed.' 'DarkGray'; return $false }
    return $true
}

function Remove-OldPackages($Chosen, [string]$RootDir) {
    if (@($Chosen).Count -eq 0) { Write-Log '   Nothing selected.' 'DarkGray'; return }
    if ($DryRun) {
        Write-Log '   [DRY RUN] These old versions would be removed:' 'Yellow'
        foreach ($c in $Chosen) { Write-Log ('     - ' + $c.Package.Inf + ' ' + $c.Package.Provider + ' ' + $c.Package.Version) }
        return
    }
    if (-not (Test-IsAdmin)) { Write-Log '   [ERROR] Removing drivers needs administrator rights. Nothing was changed.' 'Red'; return }
    Write-Log ''
    Write-Log '   Step 1 of 3: restore point' 'White'
    if (-not (New-RestorePoint)) { return }
    Write-Log ''
    Write-Log '   Step 2 of 3: saving a copy of each package that will be removed' 'White'
    $dest = ''
    if ($RootDir -ne '') { $dest = Join-Path $RootDir ('Backup\drivers_removed_' + (Get-Date -Format 'yyyyMMdd_HHmmss')) }
    $need = 0; foreach ($c in $Chosen) { if ($null -ne $c.SizeMb) { $need += [double]$c.SizeMb } }
    if ($dest -ne '') {
        $freeMb = $null
        try { $freeMb = (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($dest))).AvailableFreeSpace / 1MB } catch { }
        if ($null -ne $freeMb -and $freeMb -lt ($need + 2048)) {
            Write-Log '   [WARNING] Not enough free space for the copies.' 'Yellow'
            $go = Read-Answer '   Remove without saving copies? Y/N (Enter = N)' @('N', 'Y')
            if ($go -ne 'Y') { Write-Log '   Stopped. Nothing was changed.' 'DarkGray'; return }
            $dest = ''
        }
    }
    $toRemove = @()
    if ($dest -ne '') {
        foreach ($c in $Chosen) {
            $p = $c.Package
            $sub = Join-Path $dest ($p.Inf -replace '\.inf$', '')
            New-Item -ItemType Directory -Force -Path $sub | Out-Null
            & pnputil.exe /export-driver $p.Inf $sub | Out-Null
            if ($LASTEXITCODE -eq 0) { $toRemove += $c }
            else {
                Write-Log ('   [SKIPPED] ' + $p.Provider + ' ' + $p.Class + ' ' + $p.Version + ' (' + $p.Inf + '): the copy could not be saved, so it is left alone') 'Yellow'
                try { [IO.Directory]::Delete($sub, $true) } catch { }
            }
        }
        Write-Log ('   [OK] Saved ' + $toRemove.Count + ' of ' + @($Chosen).Count + ' copies to Backup\' + (Split-Path -Leaf $dest)) 'Green'
    } else {
        $toRemove = @($Chosen)
        Write-Log '   No copies were saved (you chose to continue without them).' 'Yellow'
    }
    Write-Log ''
    Write-Log ('   Step 3 of 3: removing ' + $toRemove.Count + ' old package(s)') 'White'
    $ok = 0; $kept = @($Chosen).Count - $toRemove.Count; $freed = 0.0; $refused = @()
    foreach ($c in $toRemove) {
        $p = $c.Package
        $label = $p.Provider + ' ' + $p.Class + ' ' + $p.Version + ' (' + $p.Inf + ')'
        & pnputil.exe /delete-driver $p.Inf | Out-Null
        if ($LASTEXITCODE -eq 0) { $ok++; if ($null -ne $c.SizeMb) { $freed += [double]$c.SizeMb }; Write-Log ('   [OK] removed ' + $label) 'Green' }
        else { $kept++; $refused += $c; Write-Log ('   [KEPT] ' + $label + ': Windows says it is still needed') 'Yellow' }
    }
    Save-RefusedPackages $refused
    Write-Log ''
    Write-Log ('   Done: ' + $ok + ' removed (about ' + [math]::Round($freed / 1024, 2) + ' GB), ' + $kept + ' left in place.') 'White'
    if ($dest -ne '') { Write-Log '   The copies are in Backup\drivers_removed_*. Delete that folder when you are sure everything works. To put a package back: pnputil /add-driver "Backup\drivers_removed_...\*.inf" /subdirs /install' 'DarkGray' }
    Write-Log '   Or use System Restore and pick Before_Driver_Cleanup.' 'DarkGray'
    Write-Log ''
    Write-Log '   Checking again what is left...' 'DarkGray'
    try {
        $left = @(Get-StaleCandidates (Get-DriverPackages) (Get-InUseInfs))
        $leftSplit = Split-RefusedCandidates $left (Get-RefusedMap) (Get-Date)
        $left = @($leftSplit.Fresh)
        if ($left.Count -eq 0 -and @($leftSplit.Known).Count -gt 0) { Write-Log ('   Nothing more can be removed now. ' + @($leftSplit.Known).Count + ' package(s) that Windows refused are not offered again for ' + $script:KeptDays + ' days.') 'Green' }
        elseif ($left.Count -eq 0) { Write-Log '   No old driver versions are left.' 'Green' }
        else { Write-Log ('   ' + $left.Count + ' old package(s) are still there (Windows kept them). Restart and run this again if you like.') 'Yellow' }
    } catch { Write-Log ('   Could not check again: ' + $_.Exception.Message) 'Yellow' }
}

function Remove-GhostDevices($Groups) {
    if (@($Groups).Count -eq 0) { Write-Log '   Nothing selected.' 'DarkGray'; return }
    if ($DryRun) {
        Write-Log '   [DRY RUN] These unused device entries would be removed:' 'Yellow'
        foreach ($g in $Groups) { Write-Log ('     - ' + $g.Count + ' x ' + $g.Name) }
        return
    }
    if (-not (Test-IsAdmin)) { Write-Log '   [ERROR] Removing device entries needs administrator rights. Nothing was changed.' 'Red'; return }
    Write-Log ''
    if (-not (New-RestorePoint)) { return }
    $ok = 0; $fail = 0
    foreach ($g in $Groups) {
        foreach ($d in $g.Group) {
            & pnputil.exe /remove-device $d.InstanceId | Out-Null
            if ($LASTEXITCODE -eq 0) { $ok++ } else { $fail++ }
        }
    }
    Write-Log ('   Done: ' + $ok + ' entries removed, ' + $fail + ' could not be removed (left as they were).') 'White'
    Write-Log '   A device you plug in again is simply set up again by Windows.' 'DarkGray'
}

# ---------------------------------------------------------------- main
function Start-DriverClean {
    $rootDir = ''
    if ($Root -ne '') { try { $rootDir = (Resolve-Path -LiteralPath $Root).Path } catch { } }

    Write-Log '==================================================================' 'Cyan'
    Write-Log '   PC OPTIMIZER - DRIVER CLEANUP (BETA)' 'Cyan'
    Write-Log ('   ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')) 'Cyan'
    Write-Log '==================================================================' 'Cyan'
    Write-Log ''
    if (-not (Test-IsAdmin)) {
        Write-Log '   This needs administrator rights to read the driver store. Run 7_Driver_Check as administrator.' 'Yellow'
        return
    }
    Write-Log '   Scanning, please wait. No key press is needed...' 'DarkGray'

    $pkgs = @()
    $scanOk = $true
    try { $pkgs = @(Get-DriverPackages) } catch { $scanOk = $false; Write-Log ('   Could not read the driver store: ' + $_.Exception.Message) 'Yellow' }
    $cands = @()
    $refusedBefore = @()
    if ($scanOk) {
        $cands = @(Get-StaleCandidates $pkgs (Get-InUseInfs))
        $split = Split-RefusedCandidates $cands (Get-RefusedMap) (Get-Date)
        $cands = @($split.Fresh)
        $refusedBefore = @($split.Known)
        foreach ($c in $cands) { Add-Member -InputObject $c -NotePropertyName SizeMb -NotePropertyValue (Get-FolderMb $c.Package.Dir) -Force }
    }

    Write-Log ''
    Write-Log '   A. Old versions of drivers you still use' 'White'
    $totalMb = 0.0
    foreach ($c in $cands) { if ($null -ne $c.SizeMb) { $totalMb += [double]$c.SizeMb } }
    if ($scanOk -and $cands.Count -eq 0 -and $refusedBefore.Count -eq 0) { Write-Log '     None. Windows keeps only the current versions.' 'Green' }
    elseif ($scanOk -and $cands.Count -eq 0) { Write-Log '     None that can be removed now.' 'Green' }
    foreach ($grp in @($cands | Group-Object { $_.Package.Provider + ' / ' + $_.Package.Class + ' / ' + $_.Package.Original })) {
        $keep = $grp.Group[0]
        Write-Log ('     ' + $grp.Name + '  (newest, kept: ' + $keep.KeepVersion + ')') 'Gray'
        foreach ($c in $grp.Group) { Write-Log ('       old: ' + $c.Package.Version + ' ' + $c.Package.Date.ToString('yyyy-MM-dd') + ' [' + $c.Package.Inf + '] ' + (Format-Mb $c.SizeMb) + ' MB') 'DarkGray' }
    }
    if ($cands.Count -gt 0) { Write-Log ('     Total: ' + $cands.Count + ' old package(s), about ' + [math]::Round($totalMb / 1024, 2) + ' GB.') 'Yellow' }
    if ($refusedBefore.Count -gt 0) { Write-Log ('     Left out (' + $refusedBefore.Count + '): Windows refused to remove ' + (($refusedBefore | ForEach-Object { $_.Package.Provider + ' ' + $_.Package.Class + ' ' + $_.Package.Version }) -join ', ') + ' earlier, so it is not offered again for ' + $script:KeptDays + ' days.') 'DarkGray' }
    if (@($script:SkippedGroups).Count -gt 0) { Write-Log ('     Left alone on purpose (' + @($script:SkippedGroups).Count + '): ' + ($script:SkippedGroups -join ', ')) 'DarkGray' }

    $allGhosts = @(Get-GhostDevices)
    $btGhosts = @($allGhosts | Where-Object { Test-GhostBluetooth ([string]$_.InstanceId) })
    $ghosts = @($allGhosts | Where-Object { -not (Test-GhostBluetooth ([string]$_.InstanceId)) })
    $ghostGroups = @($ghosts | Group-Object { [string]$_.Class })
    $removable = @($ghostGroups | Where-Object { Test-GhostRemovable $_.Name })
    $other = @($ghostGroups | Where-Object { -not (Test-GhostRemovable $_.Name) })
    Write-Log ''
    Write-Log '   B. Devices that are not connected any more' 'White'
    if ($ghosts.Count -eq 0) { Write-Log '     None.' 'Green' }
    foreach ($g in $removable) { Write-Log ('     ' + $g.Count + ' x ' + $(if ($g.Name -ne '') { $g.Name } else { 'unknown class' }) + ' (can be cleaned)') 'Gray' }
    if ($btGhosts.Count -gt 0) { Write-Log ('     ' + $btGhosts.Count + ' Bluetooth entries are kept (the device may only be switched off, removing it can mean pairing again).') 'DarkGray' }
    if ($other.Count -gt 0) {
        $n = 0; foreach ($g in $other) { $n += $g.Count }
        Write-Log ('     ' + $n + ' more entries (network, system and other classes) are only listed, never removed by this tool: ' + (($other | ForEach-Object { $_.Name }) -join ', ')) 'DarkGray'
    }

    Write-Log ''
    Write-Log '   Not done on purpose: driver packages for hardware that is simply not plugged in right now (printers, phones, controllers) are kept, because they may be needed again.' 'DarkGray'
    Write-Log '   Honest expectation: this frees disk space and tidies Device Manager. It does not raise FPS or lower ping.' 'DarkGray'

    if ($rootDir -ne '') { try { [IO.File]::WriteAllLines((New-ReportPath $rootDir 'DriverCleanReport'), $script:Lines); Remove-OldReports $rootDir | Out-Null } catch { } }
    if ($NoPrompt) { return }

    Write-Log ''
    Write-Log '   ---- your choices and what happened ----' 'DarkGray'
    $choices = New-Object System.Collections.Generic.List[string]
    $choices.Add('N')
    if ($cands.Count -gt 0) { $choices.Add('V'); $choices.Add('O') }
    if ($removable.Count -gt 0) { $choices.Add('D') }
    if ($choices.Count -eq 1) { Write-Log '   Nothing to clean up.' 'Green'; return }
    Write-Log ''
    Write-Host '   What would you like to do? Nothing is removed unless you choose.' -ForegroundColor White
    if ($cands.Count -gt 0) {
        Write-Host ('   V = remove all ' + $cands.Count + ' old driver versions listed in A')
        Write-Host '   O = let me choose one by one (A)'
    }
    if ($removable.Count -gt 0) { Write-Host '   D = remove the unused device entries listed in B' }
    Write-Host '   N = do nothing (default)'
    $ans = Read-Answer '   Your choice (Enter = N)' @($choices.ToArray())
    if ($ans -eq 'N') { Write-Log '   Nothing was changed.' 'DarkGray'; return }
    if ($ans -eq 'V') { Remove-OldPackages $cands $rootDir }
    if ($ans -eq 'O') {
        $chosen = @()
        foreach ($c in $cands) {
            $yn = Read-Answer ('   Remove ' + $c.Package.Provider + ' ' + $c.Package.Class + ' ' + $c.Package.Version + ' (' + (Format-Mb $c.SizeMb) + ' MB)? Y/N, Q = stop asking (Enter = N)') @('N', 'Y', 'Q')
            if ($yn -eq 'Q') { break }
            if ($yn -eq 'Y') { $chosen += $c }
        }
        Remove-OldPackages $chosen $rootDir
    }
    if ($ans -eq 'D') {
        $pick = @()
        foreach ($g in $removable) {
            $yn = Read-Answer ('   Remove ' + $g.Count + ' unused ' + $g.Name + ' entries? Y/N, Q = stop asking (Enter = N)') @('N', 'Y', 'Q')
            if ($yn -eq 'Q') { break }
            if ($yn -eq 'Y') { $pick += $g }
        }
        Remove-GhostDevices $pick
    }
    Write-Log ('   Finished ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')) 'DarkGray'
    if ($rootDir -ne '') { try { [IO.File]::WriteAllLines((New-ReportPath $rootDir 'DriverCleanReport' '_after'), $script:Lines); Remove-OldReports $rootDir | Out-Null } catch { } }
}

if ($MyInvocation.InvocationName -ne '.') {
    Start-DriverClean
    exit 0
}
