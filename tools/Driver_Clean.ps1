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

function Get-StaleCandidates($Packages, $InUseInfs) {
    # Packages: objects with Inf, Original, Provider, Class, Version, Date, Boot.
    # A package is a candidate only when a NEWER package of the same driver (same original file name, maker and class) exists,
    # it is not boot critical and no device uses it right now.
    $inUse = @{}
    foreach ($i in @($InUseInfs)) { if ($i) { $inUse[([string]$i).ToLower()] = $true } }
    $out = @()
    $groups = @($Packages | Group-Object { ([string]$_.Original).ToLower() + '|' + [string]$_.Provider + '|' + [string]$_.Class })
    foreach ($g in $groups) {
        if ($g.Count -lt 2) { continue }
        $sorted = @($g.Group | Sort-Object @{ Expression = { ConvertTo-VersionSafe $_.Version }; Descending = $true }, @{ Expression = { $_.Date }; Descending = $true })
        $newest = $sorted[0]
        foreach ($p in @($sorted | Select-Object -Skip 1)) {
            if ($p.Boot) { continue }
            if ($inUse.ContainsKey(([string]$p.Inf).ToLower())) { continue }
            $out += [pscustomobject]@{ Package = $p; KeepInf = [string]$newest.Inf; KeepVersion = [string]$newest.Version }
        }
    }
    return $out
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
    if ($Dir -eq '' -or -not (Test-Path -LiteralPath $Dir)) { return 0 }
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
    $need = 0; foreach ($c in $Chosen) { $need += [double]$c.SizeMb }
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
    Write-Log ''
    Write-Log ('   Step 3 of 3: removing ' + @($Chosen).Count + ' old package(s)') 'White'
    $ok = 0; $kept = 0; $freed = 0.0
    foreach ($c in $Chosen) {
        $p = $c.Package
        $label = $p.Provider + ' ' + $p.Class + ' ' + $p.Version + ' (' + $p.Inf + ')'
        if ($dest -ne '') {
            $sub = Join-Path $dest ($p.Inf -replace '\.inf$', '')
            New-Item -ItemType Directory -Force -Path $sub | Out-Null
            & pnputil.exe /export-driver $p.Inf $sub | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Log ('   [SKIPPED] ' + $label + ': the copy could not be saved, so it was left alone') 'Yellow'
                $kept++
                continue
            }
        }
        & pnputil.exe /delete-driver $p.Inf | Out-Null
        if ($LASTEXITCODE -eq 0) { $ok++; $freed += [double]$c.SizeMb; Write-Log ('   [OK] removed ' + $label) 'Green' }
        else { $kept++; Write-Log ('   [KEPT] ' + $label + ': Windows says it is still needed') 'Yellow' }
    }
    Write-Log ''
    Write-Log ('   Done: ' + $ok + ' removed (about ' + [math]::Round($freed / 1024, 2) + ' GB), ' + $kept + ' left in place.') 'White'
    if ($dest -ne '') { Write-Log '   The copies are in Backup\drivers_removed_*. Delete that folder when you are sure everything works. To put a package back: pnputil /add-driver "Backup\drivers_removed_...\*.inf" /subdirs /install' 'DarkGray' }
    Write-Log '   Or use System Restore and pick Before_Driver_Cleanup.' 'DarkGray'
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
    if ($scanOk) {
        $cands = @(Get-StaleCandidates $pkgs (Get-InUseInfs))
        foreach ($c in $cands) { Add-Member -InputObject $c -NotePropertyName SizeMb -NotePropertyValue (Get-FolderMb $c.Package.Dir) -Force }
    }

    Write-Log ''
    Write-Log '   A. Old versions of drivers you still use' 'White'
    $totalMb = 0.0
    foreach ($c in $cands) { $totalMb += [double]$c.SizeMb }
    if ($scanOk -and $cands.Count -eq 0) { Write-Log '     None. Windows keeps only the current versions.' 'Green' }
    foreach ($grp in @($cands | Group-Object { $_.Package.Provider + ' / ' + $_.Package.Class + ' / ' + $_.Package.Original })) {
        $keep = $grp.Group[0]
        Write-Log ('     ' + $grp.Name + '  (newest, kept: ' + $keep.KeepVersion + ')') 'Gray'
        foreach ($c in $grp.Group) { Write-Log ('       old: ' + $c.Package.Version + ' ' + $c.Package.Date.ToString('yyyy-MM-dd') + ' [' + $c.Package.Inf + '] ' + $c.SizeMb + ' MB') 'DarkGray' }
    }
    if ($cands.Count -gt 0) { Write-Log ('     Total: ' + $cands.Count + ' old package(s), about ' + [math]::Round($totalMb / 1024, 2) + ' GB.') 'Yellow' }

    $ghosts = @(Get-GhostDevices)
    $ghostGroups = @($ghosts | Group-Object { [string]$_.Class })
    $removable = @($ghostGroups | Where-Object { Test-GhostRemovable $_.Name })
    $other = @($ghostGroups | Where-Object { -not (Test-GhostRemovable $_.Name) })
    Write-Log ''
    Write-Log '   B. Devices that are not connected any more' 'White'
    if ($ghosts.Count -eq 0) { Write-Log '     None.' 'Green' }
    foreach ($g in $removable) { Write-Log ('     ' + $g.Count + ' x ' + $(if ($g.Name -ne '') { $g.Name } else { 'unknown class' }) + ' (can be cleaned)') 'Gray' }
    if ($other.Count -gt 0) {
        $n = 0; foreach ($g in $other) { $n += $g.Count }
        Write-Log ('     ' + $n + ' more entries (network, system and other classes) are only listed, never removed by this tool: ' + (($other | ForEach-Object { $_.Name }) -join ', ')) 'DarkGray'
    }

    Write-Log ''
    Write-Log '   Not done on purpose: driver packages for hardware that is simply not plugged in right now (printers, phones, controllers) are kept, because they may be needed again.' 'DarkGray'
    Write-Log '   Honest expectation: this frees disk space and tidies Device Manager. It does not raise FPS or lower ping.' 'DarkGray'

    if ($rootDir -ne '') { try { [IO.File]::WriteAllLines((Join-Path $rootDir ('DriverCleanReport_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.txt')), $script:Lines) } catch { } }
    if ($NoPrompt) { return }

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
            $yn = Read-Answer ('   Remove ' + $c.Package.Provider + ' ' + $c.Package.Class + ' ' + $c.Package.Version + ' (' + $c.SizeMb + ' MB)? Y/N, Q = stop asking (Enter = N)') @('N', 'Y', 'Q')
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
    if ($rootDir -ne '') { try { [IO.File]::WriteAllLines((Join-Path $rootDir ('DriverCleanReport_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '_after.txt')), $script:Lines) } catch { } }
}

if ($MyInvocation.InvocationName -ne '.') {
    Start-DriverClean
    exit 0
}
