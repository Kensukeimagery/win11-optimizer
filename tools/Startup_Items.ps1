# PC Optimizer v4.33 - programs that start with Windows: list them, switch one off or on
# It uses the same switch as the Startup tab of Task Manager (the "StartupApproved" registry keys): a program that is switched
# off stays installed and stays in its list, it only does not start at sign-in. Nothing is deleted, so switching it on again
# puts it back exactly as it was. Windows and security items (everything in the Windows folder, Windows Security) are shown
# but cannot be switched off here.
#   -Action List                  one line per item:  id|on or off|name|command|where|protected or free
#   -Action Disable -Id <id>      switch one off
#   -Action Enable  -Id <id>      switch one on
#   -TestRoot <registry key> [-TestFolder <folder>]   used by the tests: reads and writes below that key (and that folder) instead of the real ones
# Exit codes: 0 = done, 1 = not found or failed, 3 = a protected item, 2 = not administrator (for the all-users items).
param(
    [ValidateSet('List', 'Disable', 'Enable', 'Menu')][string]$Action = 'List',
    [string]$Id = '',
    [string]$TestRoot = '',
    [string]$TestFolder = ''
)

$ErrorActionPreference = 'Continue'

function Get-StartupSources([string]$TestRoot, [string]$TestFolder = '') {
    # Kind: Run = values of a Run key, Folder = files of a Startup folder
    $approved = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    if ($TestRoot -ne '') {
        $list = @(@{ Id = 'user-run'; Where = 'your account'; Kind = 'Run'; Key = ($TestRoot + '\user\Run'); Approved = ($TestRoot + '\user\Approved\Run'); Admin = $false })
        if ($TestFolder -ne '') { $list += @{ Id = 'user-folder'; Where = 'your Startup folder'; Kind = 'Folder'; Folder = $TestFolder; Approved = ($TestRoot + '\user\Approved\Folder'); Admin = $false } }
        return $list
    }
    return @(
        @{ Id = 'user-run'; Where = 'your account'; Kind = 'Run'; Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Approved = ('HKCU:\' + $approved + '\Run'); Admin = $false }
        @{ Id = 'all-run'; Where = 'all users'; Kind = 'Run'; Key = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'; Approved = ('HKLM:\' + $approved + '\Run'); Admin = $true }
        @{ Id = 'all-run32'; Where = 'all users (32-bit)'; Kind = 'Run'; Key = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = ('HKLM:\' + $approved + '\Run32'); Admin = $true }
        @{ Id = 'user-folder'; Where = 'your Startup folder'; Kind = 'Folder'; Folder = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'); Approved = ('HKCU:\' + $approved + '\StartupFolder'); Admin = $false }
        @{ Id = 'all-folder'; Where = 'all users, Startup folder'; Kind = 'Folder'; Folder = (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup'); Approved = ('HKLM:\' + $approved + '\StartupFolder'); Admin = $true }
    )
}

function ConvertTo-ApprovedState($Bytes) {
    # Task Manager writes 12 bytes. First byte 2 or 6 = on, 3 (or any odd number) = off. Nothing written = on.
    if ($null -eq $Bytes -or @($Bytes).Count -eq 0) { return 'on' }
    if ((([int]@($Bytes)[0]) -band 1) -eq 1) { return 'off' }
    return 'on'
}

function New-ApprovedBytes([bool]$Enabled) {
    $b = New-Object byte[] 12
    if ($Enabled) { $b[0] = 2; return ,$b }
    $b[0] = 3
    $ft = [BitConverter]::GetBytes([int64](Get-Date).ToFileTimeUtc())
    for ($i = 0; $i -lt 8; $i++) { $b[4 + $i] = $ft[$i] }
    return ,$b
}

function Test-ProtectedEntry([string]$Name, [string]$Command) {
    $cmd = [Environment]::ExpandEnvironmentVariables(([string]$Command).Trim())
    $win = [Environment]::GetFolderPath('Windows')
    if ($win -ne '' -and $cmd.TrimStart('"').StartsWith($win + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ($Name -match 'SecurityHealth|Windows ?Defender|Windows Security|SecurityCenter') { return $true }
    return $false
}

function Get-ApprovedValue([string]$Key, [string]$Name) {
    try { return (Get-ItemProperty -LiteralPath $Key -Name $Name -ErrorAction Stop).$Name } catch { return $null }
}

function Get-StartupEntries($Sources) {
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($s in $Sources) {
        if ($s.Kind -eq 'Run') {
            if (-not (Test-Path -LiteralPath $s.Key)) { continue }
            $item = Get-Item -LiteralPath $s.Key
            foreach ($n in @($item.GetValueNames() | Where-Object { $_ -ne '' })) {
                $cmd = [string]$item.GetValue($n, '', 'DoNotExpandEnvironmentNames')
                $out.Add([pscustomobject]@{ Id = ($s.Id + '/' + $n); Name = $n; Command = $cmd; Where = $s.Where; State = (ConvertTo-ApprovedState (Get-ApprovedValue $s.Approved $n)); Protected = (Test-ProtectedEntry $n $cmd); Source = $s })
            }
        } else {
            if (-not (Test-Path -LiteralPath $s.Folder)) { continue }
            foreach ($f in @(Get-ChildItem -LiteralPath $s.Folder -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' })) {
                $out.Add([pscustomobject]@{ Id = ($s.Id + '/' + $f.Name); Name = $f.Name; Command = $f.FullName; Where = $s.Where; State = (ConvertTo-ApprovedState (Get-ApprovedValue $s.Approved $f.Name)); Protected = (Test-ProtectedEntry $f.Name $f.FullName); Source = $s })
            }
        }
    }
    return @($out.ToArray() | Sort-Object Name)
}

function Set-StartupEntry($Sources, [string]$Id, [bool]$Enabled) {
    # returns 'done', 'missing', 'protected' or 'failed'
    $e = @(Get-StartupEntries $Sources | Where-Object { $_.Id -eq $Id }) | Select-Object -First 1
    if ($null -eq $e) { return 'missing' }
    if ($e.Protected -and -not $Enabled) { return 'protected' }
    try {
        if (-not (Test-Path -LiteralPath $e.Source.Approved)) { New-Item -Path $e.Source.Approved -Force | Out-Null }
        New-ItemProperty -LiteralPath $e.Source.Approved -Name $e.Name -PropertyType Binary -Value (New-ApprovedBytes $Enabled) -Force | Out-Null
    } catch { return 'failed' }
    $now = @(Get-StartupEntries $Sources | Where-Object { $_.Id -eq $Id }) | Select-Object -First 1
    if ($null -ne $now -and $now.State -eq $(if ($Enabled) { 'on' } else { 'off' })) { return 'done' }
    return 'failed'
}

if ($MyInvocation.InvocationName -eq '.') { return }   # loaded by a test

$sources = Get-StartupSources $TestRoot $TestFolder

if ($Action -eq 'Menu') {
    $isAdmin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    while ($true) {
        $entries = @(Get-StartupEntries $sources)
        Write-Host ''
        Write-Host '   PROGRAMS THAT START WITH WINDOWS (a switched-off program stays installed, nothing is deleted)'
        Write-Host ''
        if ($entries.Count -eq 0) { Write-Host '   There are none.'; break }
        for ($n = 0; $n -lt $entries.Count; $n++) {
            $e = $entries[$n]
            $mark = $(if ($e.State -eq 'on') { '[on ]' } else { '[off]' })
            $note = $(if ($e.Protected) { '   (Windows item, cannot be switched off here)' } else { '' })
            Write-Host ('   ' + ([string]($n + 1)).PadLeft(2) + '  ' + $mark + ' ' + $e.Name + '   (' + $e.Where + ')' + $note)
        }
        Write-Host ''
        $c = ''
        try { $c = [string](Read-Host '   Number to switch on or off, Enter = leave') } catch { }
        $num = 0
        if (-not [int]::TryParse($c.Trim(), [ref]$num) -or $num -lt 1 -or $num -gt $entries.Count) { break }
        $e = $entries[$num - 1]
        if ($e.Protected) { Write-Host '   That is a Windows or security item. It is not switched off here.' -ForegroundColor Yellow; continue }
        if ($e.Source.Admin -and -not $isAdmin) { Write-Host '   This one is for all users: open the program as administrator to change it.' -ForegroundColor Yellow; continue }
        $r = Set-StartupEntry $sources $e.Id ($e.State -ne 'on')
        if ($r -eq 'done') { Write-Host ('   [OK] ' + $e.Name + ' is now switched ' + $(if ($e.State -eq 'on') { 'off' } else { 'on' }) + '. It takes effect at the next sign-in.') -ForegroundColor Green }
        else { Write-Host ('   [FAILED] ' + $e.Name + ' could not be changed (' + $r + ').') -ForegroundColor Red }
    }
    exit 0
}

if ($Action -eq 'List') {
    foreach ($e in (Get-StartupEntries $sources)) {
        $clean = { param($t) (([string]$t) -replace '[\r\n|]', ' ').Trim() }
        Write-Output ((& $clean $e.Id) + '|' + $e.State + '|' + (& $clean $e.Name) + '|' + (& $clean $e.Command) + '|' + (& $clean $e.Where) + '|' + $(if ($e.Protected) { 'protected' } else { 'free' }))
    }
    exit 0
}

if ($Id -eq '') { Write-Host '   [ERROR] Give the item with -Id (take it from -Action List).'; exit 1 }
if ($TestRoot -eq '' -and $Id -match '^all-') {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Write-Host '   [ERROR] Items for all users need administrator rights.'; exit 2 }
}
$result = Set-StartupEntry $sources $Id ($Action -eq 'Enable')
switch ($result) {
    'done' { Write-Host ('   [OK] ' + $Id + ' is switched ' + $(if ($Action -eq 'Enable') { 'on' } else { 'off' }) + '. It takes effect at the next sign-in.'); exit 0 }
    'protected' { Write-Host '   [SKIPPED] That is a Windows or security item. It is not switched off here.'; exit 3 }
    'missing' { Write-Host ('   [ERROR] No startup item with the id ' + $Id + '.'); exit 1 }
    default { Write-Host '   [FAILED] The switch could not be written.'; exit 1 }
}
