# PC Optimizer v4.14 - support bundle
# Collects what is needed to find a problem into ONE text file: version, Windows build, Check Status, system report, PC health,
# a driver scan, the latest logs and the saved choices. Read-only: nothing on the PC is changed and nothing is sent anywhere.
# Private details are replaced: your user name, the computer name, home network addresses, hardware (MAC) addresses and e-mail addresses.
# Read the file before you share it. It still lists program names and your PC model.
#   -Root <folder>  where the Backup, logs and the output file are (default: the folder above tools)
param([string]$Root = '')

$ErrorActionPreference = 'Continue'
$user = [string]$env:USERNAME
$pcName = [string]$env:COMPUTERNAME

# ---------------------------------------------------------------- scrubbing (pure function, tested)
function ConvertTo-Scrubbed([string]$Text, [string]$UserName, [string]$ComputerName) {
    if ($null -eq $Text) { return '' }
    # whole names only, so a user called "admin" does not break the word "administrator"
    if ($UserName -ne '' -and $UserName.Length -ge 2) { $Text = $Text -replace ('(?<![A-Za-z0-9])' + [regex]::Escape($UserName) + '(?![A-Za-z0-9])'), '<user>' }
    if ($ComputerName -ne '' -and $ComputerName.Length -ge 2) { $Text = $Text -replace ('(?<![A-Za-z0-9])' + [regex]::Escape($ComputerName) + '(?![A-Za-z0-9])'), '<pc>' }
    $Text = $Text -replace '\b[0-9A-Fa-f]{2}([-:])[0-9A-Fa-f]{2}(\1[0-9A-Fa-f]{2}){4}\b', '<mac>'
    # home network addresses only; other dotted numbers are driver versions and must stay readable
    $Text = $Text -replace '(?<![\d.])(192\.168|169\.254|172\.(1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}(?![\d.]*\d)', '<ip>'
    $Text = $Text -replace '\b[0-9A-Fa-f]{1,4}(:[0-9A-Fa-f]{0,4}){3,7}\b', '<ipv6>'
    $Text = $Text -replace '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '<email>'
    return $Text
}

function Get-SectionText([scriptblock]$Block) {
    # Runs one collector; a failure in one section never stops the others.
    try { return ((@(& $Block) | ForEach-Object { [string]$_ }) -join "`r`n") }
    catch { return ('(this part could not be collected: ' + $_.Exception.Message + ')') }
}

function Invoke-Tool([string]$Script, [string[]]$ToolArgs) {
    $path = Join-Path $script:ToolDir $Script
    if (-not (Test-Path -LiteralPath $path)) { return ('(' + $Script + ' was not found)') }
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $path @ToolArgs 2>&1
    return (@($out) | ForEach-Object { [string]$_ }) -join "`r`n"
}

function Get-TailText([string]$Pattern, [int]$Lines) {
    $f = Get-ChildItem -LiteralPath $script:RootDir -File -Filter $Pattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($null -eq $f) { return '(none found)' }
    $all = @(Get-Content -LiteralPath $f.FullName -ErrorAction SilentlyContinue)
    $take = @($all | Select-Object -Last $Lines)
    return ($f.Name + ' (last ' + $take.Count + ' of ' + $all.Count + ' lines)' + "`r`n" + ($take -join "`r`n"))
}

function Get-CheckStatusText {
    $items = & {
        . (Join-Path $script:ToolDir 'Check_Status.ps1') -Root $script:RootDir
        Invoke-Checks (Join-Path $script:RootDir 'reg') (Join-Path ([IO.Path]::GetTempPath()) 'pcopt_bundle_unused')
        $script:Items
    }
    $rows = foreach ($it in @($items)) {
        $line = ('[' + $it.Status + ']').PadRight(13) + ' ' + ([string]$it.Id).PadRight(5) + ' ' + $it.Title
        if ($it.Detail) { $line += ' - ' + $it.Detail }
        $line
    }
    return @($rows)
}

function Get-StateText {
    $k = 'HKCU:\Software\PCOptimizer'
    if (-not (Test-Path $k)) { return '(no saved choices)' }
    $p = Get-ItemProperty -Path $k
    $rows = foreach ($n in @($p.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' -and $_.Name -ne 'DnsBackup' } | Sort-Object Name)) { ($n.Name + ' = ' + $n.Value) }
    return @($rows)
}

# ---------------------------------------------------------------- main
function Start-SupportBundle {
    $script:RootDir = $Root
    if ($script:RootDir -eq '') { $script:RootDir = Split-Path -Parent $PSScriptRoot }
    $script:RootDir = (Resolve-Path -LiteralPath $script:RootDir).Path
    $script:ToolDir = Join-Path $script:RootDir 'tools'
    $version = ''
    try { $version = ([IO.File]::ReadAllText((Join-Path $script:RootDir 'VERSION'))).Trim() } catch { }

    Write-Host '==================================================================' -ForegroundColor Cyan
    Write-Host '   PC OPTIMIZER v4.14 - SUPPORT BUNDLE (nothing is changed or sent)' -ForegroundColor Cyan
    Write-Host '==================================================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '   Collecting everything into one file, about 30-60 seconds. No key press is needed...' -ForegroundColor DarkGray

    $sections = @(
        @{ Title = 'Environment'; Block = { Invoke-Tool 'Env_Check.ps1' @('-Human') } },
        @{ Title = 'Check Status (settings still in place)'; Block = { Get-CheckStatusText } },
        @{ Title = 'PC specs'; Block = { Invoke-Tool 'PC_Specs.ps1' @() } },
        @{ Title = 'PC health'; Block = { Invoke-Tool 'PC_Health.ps1' @() } },
        @{ Title = 'System report'; Block = { Invoke-Tool 'System_Report.ps1' @() } },
        @{ Title = 'Driver scan (this PC only, nothing installed)'; Block = { Invoke-Tool 'Driver_Check.ps1' @('-SkipUpdateSearch', '-NoPrompt') } },
        @{ Title = 'Saved choices'; Block = { Get-StateText } },
        @{ Title = 'Latest optimizer log'; Block = { Get-TailText 'OptimizerLog_*.txt' 150 } },
        @{ Title = 'Latest update log'; Block = { Get-TailText 'UpdateLog_*.txt' 60 } }
    )

    $admin = $false
    try { $admin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('PC OPTIMIZER SUPPORT BUNDLE')
    [void]$sb.AppendLine('Created:      ' + (Get-Date -Format 'yyyy-MM-dd HH:mm'))
    [void]$sb.AppendLine('Version:      v' + $version)
    [void]$sb.AppendLine('Windows:      ' + [Environment]::OSVersion.VersionString + ', display language ' + (Get-Culture).Name)
    [void]$sb.AppendLine('Administrator: ' + $(if ($admin) { 'yes' } else { 'no' }))
    [void]$sb.AppendLine('Private details (user name, computer name, home network addresses, MAC addresses, e-mail addresses) are replaced. Read this file before you share it.')

    foreach ($s in $sections) {
        Write-Host ('   - ' + $s.Title) -ForegroundColor Gray
        $text = Get-SectionText $s.Block
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('==================================================================')
        [void]$sb.AppendLine('## ' + $s.Title)
        [void]$sb.AppendLine('==================================================================')
        [void]$sb.AppendLine($text)
    }

    $final = ConvertTo-Scrubbed $sb.ToString() $user $pcName
    $file = Join-Path $script:RootDir ('SupportBundle_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.txt')
    try {
        [IO.File]::WriteAllText($file, $final, (New-Object Text.UTF8Encoding($false)))
    } catch {
        # the folder may be read-only (for example Program Files): use the temp folder instead
        $file = Join-Path ([IO.Path]::GetTempPath()) (Split-Path -Leaf $file)
        try { [IO.File]::WriteAllText($file, $final, (New-Object Text.UTF8Encoding($false))) }
        catch { Write-Host ('   [ERROR] The file could not be saved: ' + $_.Exception.Message) -ForegroundColor Red; return }
        Write-Host ('   The tool folder is not writable, so the file was saved in: ' + [IO.Path]::GetTempPath()) -ForegroundColor Yellow
    }

    Write-Host ''
    Write-Host ('   [OK] Saved: ' + (Split-Path -Leaf $file) + '  (' + [math]::Round((Get-Item -LiteralPath $file).Length / 1KB) + ' KB)') -ForegroundColor Green
    Write-Host '   Open it and read it first. Remove anything you do not want to share.' -ForegroundColor White
    Write-Host '   To report a problem: https://github.com/Kensukeimagery/win11-optimizer/issues/new/choose and attach the file.' -ForegroundColor White
    Write-Host '   The file stays on your PC. Nothing was sent.' -ForegroundColor DarkGray
}

if ($MyInvocation.InvocationName -ne '.') {
    Start-SupportBundle
    exit 0
}
