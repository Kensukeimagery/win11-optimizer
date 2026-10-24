# PC Optimizer v4.33 - free up disk space: shows what each kind of leftover file takes, removes only what you say yes to
# Only these places are ever looked at, and only files that Windows and programs rebuild or no longer need:
#   usertemp  your temporary files (older than one day)
#   wintemp   the Windows temporary files (older than one day, needs administrator rights)
#   wucache   Windows Update download leftovers (needs administrator rights)
#   thumbs    the picture and icon cache of File Explorer (it is rebuilt when you open a folder)
#   dumps     crash dumps and Windows error reports
# NOT touched: the Recycle Bin, your Downloads and Documents, game files and the shader caches of your games, and anything
# else. A file that is in use is skipped, never forced. Nothing is removed before you answer Y for that kind.
#   -Action Ask (default)   show the sizes, ask kind by kind, remove what you accept
#   -Action Scan            only show the sizes
#   -Action Clean -Only usertemp,thumbs    remove those kinds without asking (for scripts and tests)
#   -DryRun                 show what would be removed and remove nothing
param(
    [ValidateSet('Ask', 'Scan', 'Clean')][string]$Action = 'Ask',
    [string[]]$Only = @(),
    [string]$Root = '',
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'
if ($Root -eq '') { $Root = Split-Path -Parent $PSScriptRoot }
$Root = (Resolve-Path -LiteralPath $Root).Path
. (Join-Path $PSScriptRoot 'Report_Files.ps1')

function Test-IsAdmin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-Categories {
    # Id, Title, Admin, Places (each: Path, Filter, Recurse, MinAgeHours)
    $win = [Environment]::GetFolderPath('Windows')
    $local = $env:LOCALAPPDATA
    return @(
        @{ Id = 'usertemp'; Title = 'Your temporary files'; Admin = $false; Places = @(@{ Path = $env:TEMP; Filter = '*'; Recurse = $true; MinAgeHours = 24 }) }
        @{ Id = 'wintemp'; Title = 'Windows temporary files'; Admin = $true; Places = @(@{ Path = (Join-Path $win 'Temp'); Filter = '*'; Recurse = $true; MinAgeHours = 24 }) }
        @{ Id = 'wucache'; Title = 'Windows Update download leftovers'; Admin = $true; Places = @(@{ Path = (Join-Path $win 'SoftwareDistribution\Download'); Filter = '*'; Recurse = $true; MinAgeHours = 24 }) }
        @{ Id = 'thumbs'; Title = 'Picture and icon cache of File Explorer'; Admin = $false; Places = @(
            @{ Path = (Join-Path $local 'Microsoft\Windows\Explorer'); Filter = 'thumbcache_*.db'; Recurse = $false; MinAgeHours = 0 }
            @{ Path = (Join-Path $local 'Microsoft\Windows\Explorer'); Filter = 'iconcache_*.db'; Recurse = $false; MinAgeHours = 0 }) }
        @{ Id = 'dumps'; Title = 'Crash dumps and error reports'; Admin = $true; Places = @(
            @{ Path = (Join-Path $local 'CrashDumps'); Filter = '*.dmp'; Recurse = $false; MinAgeHours = 0 }
            @{ Path = (Join-Path $win 'Minidump'); Filter = '*.dmp'; Recurse = $false; MinAgeHours = 0 }
            @{ Path = $win; Filter = 'MEMORY.DMP'; Recurse = $false; MinAgeHours = 0 }
            @{ Path = (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive'); Filter = '*'; Recurse = $true; MinAgeHours = 0 }
            @{ Path = (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue'); Filter = '*'; Recurse = $true; MinAgeHours = 0 }) }
    )
}

function Get-PlaceFiles($Place) {
    # the files of one place that may be removed; a link (junction, symbolic link) is never followed or removed
    # (walks the folders itself with .NET calls: much faster than Get-ChildItem on a temp folder with hundreds of thousands of files)
    $dir = [string]$Place.Path
    if ($dir -eq '' -or -not [IO.Directory]::Exists($dir)) { return @() }
    $limit = (Get-Date).AddHours(-[double]$Place.MinAgeHours)
    $list = New-Object System.Collections.Generic.List[object]
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($dir)
    while ($stack.Count -gt 0) {
        $cur = $stack.Pop()
        try {
            $di = New-Object IO.DirectoryInfo($cur)
            foreach ($f in $di.EnumerateFiles($Place.Filter)) {
                if (($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }   # a link is never followed or removed
                if ($f.LastWriteTime -gt $limit) { continue }
                $list.Add($f)
            }
            if ($Place.Recurse) {
                foreach ($s in $di.EnumerateDirectories()) {
                    if (($s.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                    $stack.Push($s.FullName)
                }
            }
        } catch { }
    }
    return $list.ToArray()
}

function Get-CategoryFiles($Category) {
    $all = @()
    foreach ($p in $Category.Places) { $all += @(Get-PlaceFiles $p) }
    return $all
}

function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N0} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return ('{0:N0} B' -f $Bytes)
}

function Remove-FileList($Files, [switch]$DryRun) {
    # removes the files one by one, skips what is in use; returns how many were removed and their size
    $n = 0; $bytes = [int64]0; $skipped = 0
    foreach ($f in @($Files)) {
        if ($DryRun) { $n++; $bytes += [int64]$f.Length; continue }
        try { $len = [int64]$f.Length; Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $n++; $bytes += $len } catch { $skipped++ }
    }
    return [pscustomobject]@{ Removed = $n; Bytes = $bytes; Skipped = $skipped }
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

if ($MyInvocation.InvocationName -eq '.') { return }   # loaded by a test: only the functions are wanted

Write-Host '=================================================================='
Write-Host '   PC OPTIMIZER - FREE UP DISK SPACE'
Write-Host '=================================================================='
Write-Host ''
$admin = Test-IsAdmin
$report = New-Object System.Collections.Generic.List[string]
$cats = @(Get-Categories)
if ($Only.Count -gt 0) { $cats = @($cats | Where-Object { $Only -contains $_.Id }) }
$found = @()
Write-Host '   Looking, please wait...' -ForegroundColor DarkGray
foreach ($c in $cats) {
    if ($c.Admin -and -not $admin) { Write-Host ('   ' + $c.Title.PadRight(42) + 'needs administrator rights') -ForegroundColor DarkGray; continue }
    $files = @(Get-CategoryFiles $c)
    $size = [int64](($files | Measure-Object -Property Length -Sum).Sum)
    $line = ('   ' + $c.Title.PadRight(42) + ([string]$files.Count).PadLeft(7) + ' files' + (Format-Size $size).PadLeft(11))
    Write-Host $line
    $report.Add($line.Trim())
    $found += [pscustomobject]@{ Category = $c; Files = $files; Bytes = $size }
}
$total = [int64](($found | Measure-Object -Property Bytes -Sum).Sum)
Write-Host ''
Write-Host ('   Together: ' + (Format-Size $total)) -ForegroundColor White
if ($Action -eq 'Scan') { exit 0 }

$freed = [int64]0
foreach ($f in $found) {
    if ($f.Files.Count -eq 0) { continue }
    $go = $(if ($Action -eq 'Clean') { 'Y' } else { Read-Answer ('   Remove ' + $f.Category.Title.ToLower() + ' (' + (Format-Size $f.Bytes) + ')? Y/N, Enter = no') @('N', 'Y') })
    if ($go -ne 'Y') { Write-Host ('   - kept: ' + $f.Category.Title) -ForegroundColor DarkGray; continue }
    $r = Remove-FileList $f.Files -DryRun:$DryRun
    $freed += $r.Bytes
    $msg = ('   [' + $(if ($DryRun) { 'DRY RUN' } else { 'OK' }) + '] ' + $f.Category.Title + ': ' + $r.Removed + ' files, ' + (Format-Size $r.Bytes) + $(if ($r.Skipped -gt 0) { ', ' + $r.Skipped + ' in use were skipped' } else { '' }))
    Write-Host $msg -ForegroundColor Green
    $report.Add($msg.Trim())
}
Write-Host ''
Write-Host ('   ' + $(if ($DryRun) { 'Would free: ' } else { 'Freed: ' }) + (Format-Size $freed)) -ForegroundColor White
try {
    $path = New-ReportPath $Root 'FreeSpace'
    $report.Add(('Freed: ' + (Format-Size $freed)))
    [IO.File]::WriteAllLines($path, $report)
    Remove-OldReports $Root | Out-Null
} catch { }
exit 0
