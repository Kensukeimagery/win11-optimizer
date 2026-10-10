# PC Optimizer v4.18 - Easy Setup (one button)
# For a new Windows install, for people who never used an optimizer, and for people who do not know computers.
# It walks through everything in the best order, in plain words (Thai or English), and asks only what it must:
#   check for a newer version -> restore point -> remember how the PC is now -> internet -> Windows Update (guided)
#   -> drivers -> restart if needed -> safe speed settings -> verify and show a one-page summary.
# Drivers and settings come LAST so that updates and drivers cannot undo the settings. Nothing is deleted.
#   -Preview    show the plan and what would be done, change NOTHING
#   -Yes        do not ask the first confirmation (tests)
#   -NoPrompt   never wait for the keyboard: every question takes its default (tests)
#   -Lang th|en|ask   -Mode safe|games|ask   (safe = recommended settings only; games = also mouse, keyboard, timer and CPU boost)
# The messages are in tools\lang\easy_en.txt and easy_th.txt (UTF-8). This file itself is plain ASCII.
param(
    [string]$Root = '',
    [switch]$Preview,
    [switch]$Yes,
    [switch]$NoPrompt,
    [ValidateSet('ask', 'th', 'en')][string]$Lang = 'ask',
    [ValidateSet('ask', 'safe', 'games')][string]$Mode = 'ask'
)

$ErrorActionPreference = 'Continue'
if ($Root -eq '') { $Root = Split-Path -Parent $PSScriptRoot }
$EasyRoot = (Resolve-Path -LiteralPath $Root).Path
. (Join-Path $PSScriptRoot 'Report_Files.ps1')
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8; $OutputEncoding = [Text.Encoding]::UTF8 } catch { }

$script:EasyLines = New-Object System.Collections.Generic.List[string]
$script:Strings = @{}
$script:StringsEn = @{}
$script:EasyUser = [string]$env:USERNAME
$script:StepOrder = @('update', 'restore', 'before', 'network', 'winupdate', 'drivers', 'restart', 'tweaks', 'dns', 'verify')

# ---------------------------------------------------------------- messages
function Import-Strings([string]$Code) {
    $map = @{}
    $path = Join-Path $PSScriptRoot ('lang\easy_' + $Code + '.txt')
    if (Test-Path -LiteralPath $path) {
        foreach ($line in [IO.File]::ReadAllLines($path, [Text.Encoding]::UTF8)) {
            if ($line -match '^\s*#' -or $line.Trim() -eq '') { continue }
            $i = $line.IndexOf('=')
            if ($i -gt 0) { $map[$line.Substring(0, $i).Trim()] = $line.Substring($i + 1).Replace('\n', "`n") }
        }
    }
    return $map
}

function T([string]$Key, [object[]]$Values = @()) {
    $s = $null
    if ($script:Strings.ContainsKey($Key)) { $s = $script:Strings[$Key] }
    elseif ($script:StringsEn.ContainsKey($Key)) { $s = $script:StringsEn[$Key] }
    else { return $Key }
    if ($Values.Count -gt 0) { try { return [string]::Format($s, $Values) } catch { return $s } }
    return $s
}

function Say([string]$Text, [string]$Color = 'Gray') {
    $safe = $Text
    if ($script:EasyUser -ne '') { $safe = $safe -replace ('(?<![A-Za-z0-9])' + [regex]::Escape($script:EasyUser) + '(?![A-Za-z0-9])'), '<user>' }
    Write-Host $safe -ForegroundColor $Color
    $script:EasyLines.Add($safe)
}
function SayT([string]$Key, [object[]]$Values = @(), [string]$Color = 'Gray') { Say (T $Key $Values) $Color }

function Read-Choice([string]$Prompt, [string[]]$Allowed) {
    # The first allowed answer is the default. With -NoPrompt, closed input or Enter it is taken.
    if ($NoPrompt) { return $Allowed[0] }
    for ($try = 0; $try -lt 20; $try++) {
        $raw = Read-Host $Prompt
        if ($null -eq $raw) { break }
        $a = ([string]$raw).Trim().ToUpper()
        if ($a -eq '') { $a = $Allowed[0] }
        if ($Allowed -contains $a) { return $a }
        Say (T 'type_one_of' @(($Allowed -join ', '))) 'DarkYellow'
    }
    return $Allowed[0]
}

# ---------------------------------------------------------------- rules (pure functions, tested without touching the PC)
function Get-NextStep($Done) {
    $d = @($Done)
    foreach ($s in $script:StepOrder) { if ($d -notcontains $s) { return $s } }
    return ''
}

function Get-TweakProfile([string]$Answer) {
    # "Do you mainly play games on this PC?"  Y = games, anything else = the safe profile
    if ($Answer -eq 'Y') { return 'games' }
    return 'safe'
}

function Test-RestartNeeded([bool]$Pending, $DriverResult) {
    if ($Pending) { return $true }
    if ($null -ne $DriverResult -and [bool]$DriverResult.Reboot) { return $true }
    return $false
}

function Get-SettingsSnapshot($Items) {
    $all = @($Items)
    $ok = @($all | Where-Object { $_.Status -eq 'OK' }).Count
    $bad = @($all | Where-Object { $_.Status -eq 'CHANGED' -or $_.Status -eq 'MISSING' })
    return @{ Ok = $ok; Total = ($ok + $bad.Count); Bad = @($bad | ForEach-Object { [string]$_.Title }) }
}

function Select-AttentionLines($Lines, [int]$Max = 6) {
    # CHECK lines from the health reports, without repeating the same advice twice
    $out = @(); $seen = @{}
    foreach ($l in @($Lines)) {
        $t = ([string]$l).Trim()
        if ($t -notmatch '^\[CHECK\]') { continue }
        $t = ($t -replace '^\[CHECK\]\s*', '')
        $key = $t.Substring(0, [math]::Min(25, $t.Length)).ToLower()   # the same advice from two reports starts the same way
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $out += $t
        if ($out.Count -ge $Max) { break }
    }
    return $out
}

function Get-EasyPlan([bool]$Laptop, [bool]$Online, [string]$ProfileName) {
    # The keys of the plan lines in the order they run. Used for the first screen and tested.
    $plan = @('plan_update', 'plan_restore', 'plan_before')
    if ($Online) { $plan += 'plan_network_ok' } else { $plan += 'plan_network_off' }
    $plan += 'plan_winupdate'
    $plan += 'plan_drivers'
    $plan += 'plan_restart'
    if ($Laptop) { $plan += 'plan_tweaks_laptop' } elseif ($ProfileName -eq 'games') { $plan += 'plan_tweaks_games' } else { $plan += 'plan_tweaks_safe' }
    $plan += 'plan_dns'
    $plan += 'plan_verify'
    return $plan
}

# ---------------------------------------------------------------- state (so the setup can continue after a restart)
$script:StateKey = 'HKCU:\Software\PCOptimizer'
function Get-EasyState {
    $done = @(); $prof = ''; $lang = ''
    try {
        $p = Get-ItemProperty -Path $script:StateKey -ErrorAction Stop
        if ($p.EasyDone) { $done = @(([string]$p.EasyDone) -split ',' | Where-Object { $_ -ne '' }) }
        if ($p.EasyProfile) { $prof = [string]$p.EasyProfile }
        if ($p.EasyLang) { $lang = [string]$p.EasyLang }
    } catch { }
    return @{ Done = $done; Profile = $prof; Lang = $lang }
}
function Set-EasyValue([string]$Name, [string]$Value) {
    if ($Preview) { return }
    try {
        if (-not (Test-Path $script:StateKey)) { New-Item -Path $script:StateKey -Force | Out-Null }
        New-ItemProperty -Path $script:StateKey -Name $Name -Value $Value -PropertyType String -Force | Out-Null
    } catch { }
}
function Complete-Step([string]$Id) {
    $st = Get-EasyState
    $d = @($st.Done) + @($Id) | Select-Object -Unique
    Set-EasyValue 'EasyDone' ($d -join ',')
}
function Clear-EasyState {
    if ($Preview) { return }
    foreach ($n in 'EasyDone', 'EasyProfile', 'EasyLang', 'EasyBefore') { try { Remove-ItemProperty -Path $script:StateKey -Name $n -ErrorAction SilentlyContinue } catch { } }
}

# ---------------------------------------------------------------- facts about this PC (read-only)
function Test-IsAdmin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-PcFacts {
    $build = 0; $laptop = $false
    try {
        $out = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Env_Check.ps1')) -join ' '
        $m = [regex]::Match($out, '(\d+)\s+(\d)')
        if ($m.Success) { $build = [int]$m.Groups[1].Value; $laptop = ($m.Groups[2].Value -eq '1') }
    } catch { }
    $freeGb = 0
    try { $freeGb = [math]::Round((New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($env:SystemDrive + '\'))).AvailableFreeSpace / 1GB) } catch { }
    $installDays = -1
    try { $installDays = [int]((Get-Date) - [datetime](Get-CimInstance Win32_OperatingSystem).InstallDate).TotalDays } catch { }
    return @{ Build = $build; Laptop = $laptop; FreeGb = $freeGb; InstallDays = $installDays }
}

function Test-Online {
    try {
        $r = Invoke-WebRequest -Uri 'http://www.msftconnecttest.com/connecttest.txt' -UseBasicParsing -TimeoutSec 6 -ErrorAction Stop
        if ([string]$r.Content -match 'Microsoft Connect Test') { return $true }
    } catch { }
    try { return [bool](Test-Connection -ComputerName 1.1.1.1 -Count 1 -Quiet -ErrorAction Stop) } catch { return $false }
}

function Test-PendingReboot {
    foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        if (Test-Path $k) { return $true }
    }
    return $false
}

function Get-ProblemDeviceCount {
    $skip = @(0, 22, 24, 45)
    try { return @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop | Where-Object { ($skip -notcontains [int]$_.ConfigManagerErrorCode) -and ([string]$_.PNPDeviceID -notmatch '^(SWD|ROOT)\\') }).Count } catch { return -1 }
}

function Get-SettingsItems {
    try {
        return @(& {
            . (Join-Path $PSScriptRoot 'Check_Status.ps1') -Root $EasyRoot
            Invoke-Checks (Join-Path $EasyRoot 'reg') (Join-Path ([IO.Path]::GetTempPath()) 'pcopt_easy_unused')
            $script:Items
        })
    } catch { return @() }
}

function Set-KeepAwake([bool]$On) {
    try {
        if (-not ('PCOptEasyPower' -as [type])) {
            Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public class PCOptEasyPower { [DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint flags); }'
        }
        if ($On) { [void][PCOptEasyPower]::SetThreadExecutionState([uint32]2147483649) } else { [void][PCOptEasyPower]::SetThreadExecutionState([uint32]2147483648) }
    } catch { }
}

function Invoke-Tool([string]$Script, [string[]]$ToolArgs) {
    # the tool's own output goes to the screen, not into the return value
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $Script) @ToolArgs | Out-Host
    return $LASTEXITCODE
}

function Invoke-ToolQuiet([string]$Script, [string[]]$ToolArgs) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $Script) @ToolArgs | Out-Null
    return $LASTEXITCODE
}

# ---------------------------------------------------------------- the steps
function Step-Update {
    SayT 'step_update_title' @() 'White'
    if ($Preview) { SayT 'preview_update' @() 'Yellow'; return 'preview' }
    if (-not $script:Online) { SayT 'skip_offline' @() 'DarkGray'; return 'skipped' }
    $ans = Read-Choice (T 'ask_update') @('Y', 'N')
    if ($ans -ne 'Y') { SayT 'skipped' @() 'DarkGray'; return 'skipped' }
    $out = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Update.ps1') -Action Check -Root $EasyRoot 2>$null)
    $line = (($out | ForEach-Object { [string]$_ }) -join ' ').Trim()
    if ($line -eq '') { SayT 'update_none' @() 'Green'; return 'done' }
    Say ('   ' + $line) 'Yellow'
    $go = Read-Choice (T 'ask_update_now') @('Y', 'N')
    if ($go -ne 'Y') { SayT 'skipped' @() 'DarkGray'; return 'skipped' }
    [void](Invoke-Tool 'Update.ps1' @('-Action', 'Run', '-Root', $EasyRoot))
    SayT 'update_started' @() 'Yellow'
    return 'stop'
}

function Step-Restore {
    SayT 'step_restore_title' @() 'White'
    if ($Preview) { SayT 'preview_restore' @() 'Yellow'; return 'preview' }
    SayT 'restore_wait' @() 'DarkGray'
    $code = Invoke-Tool 'Create_Restore_Point.ps1' @('-TimeoutSeconds', '600', '-Description', 'Before_PC_Optimizer')
    if ($code -eq 0) { SayT 'restore_ok' @() 'Green'; return 'done' }
    SayT 'restore_fail' @() 'Yellow'
    $go = Read-Choice (T 'ask_continue_no_restore') @('N', 'Y')
    if ($go -eq 'Y') { return 'done' }
    return 'stop'
}

function Step-Before {
    SayT 'step_before_title' @() 'White'
    if ($Preview) { SayT 'preview_before' @() 'Yellow'; return 'preview' }
    $snap = Get-SettingsSnapshot (Get-SettingsItems)
    $script:Before = @{ Ok = $snap.Ok; Total = $snap.Total; Devices = (Get-ProblemDeviceCount) }
    Set-EasyValue 'EasyBefore' ($script:Before.Ok.ToString() + '/' + $script:Before.Total.ToString() + '/' + $script:Before.Devices.ToString())
    SayT 'before_done' @($script:Before.Ok, $script:Before.Total) 'Green'
    [void](Invoke-ToolQuiet 'PC_Specs.ps1' @('-Root', $EasyRoot))
    return 'done'
}

function Step-Network {
    SayT 'step_network_title' @() 'White'
    if ($Preview) { SayT $(if ($script:Online) { 'preview_network_ok' } else { 'preview_network_off' }) @() 'Yellow'; return 'preview' }
    for ($try = 0; $try -lt 5; $try++) {
        $script:Online = Test-Online
        if ($script:Online) { SayT 'network_ok' @() 'Green'; return 'done' }
        SayT 'network_off' @() 'Yellow'
        $ans = Read-Choice (T 'ask_network_retry') @('S', 'R')
        if ($ans -eq 'S') { break }
    }
    SayT 'network_skipped' @() 'Yellow'
    return 'skipped'
}

function Step-WinUpdate {
    SayT 'step_winupdate_title' @() 'White'
    if ($Preview) { SayT 'preview_winupdate' @() 'Yellow'; return 'preview' }
    if (-not $script:Online) { SayT 'skip_offline' @() 'DarkGray'; return 'skipped' }
    SayT 'winupdate_explain' @() 'Gray'
    $ans = Read-Choice (T 'ask_winupdate') @('S', 'O')
    if ($ans -eq 'S') { SayT 'skipped' @() 'DarkGray'; return 'skipped' }
    try { Start-Process 'ms-settings:windowsupdate' } catch { }
    SayT 'winupdate_wait' @() 'Gray'
    if (-not $NoPrompt) { [void](Read-Host (T 'press_enter_done')) }
    return 'done'
}

function Step-Drivers {
    SayT 'step_drivers_title' @() 'White'
    $rf = Join-Path ([IO.Path]::GetTempPath()) ('pcopt_easy_drv_' + [guid]::NewGuid().ToString('N') + '.json')
    if ($Preview) {
        SayT 'preview_drivers' @() 'Yellow'
        [void](Invoke-Tool 'Driver_Check.ps1' @('-NoPrompt', '-ResultFile', $rf))   # no -Root: the preview saves no report
    } else {
        if (-not $script:Online) { SayT 'drivers_offline' @() 'Yellow' }
        $args2 = @('-Root', $EasyRoot, '-Auto', '-NoRestorePoint', '-ResultFile', $rf)
        if (-not $script:Online) { $args2 += '-SkipUpdateSearch' }
        [void](Invoke-Tool 'Driver_Check.ps1' $args2)
    }
    $res = $null
    try { if (Test-Path -LiteralPath $rf) { $res = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($rf)) } } catch { }
    try { if (Test-Path -LiteralPath $rf) { [IO.File]::Delete($rf) } } catch { }
    $script:DriverResult = $res
    if ($null -eq $res) { SayT 'drivers_noresult' @() 'Yellow'; return 'skipped' }
    if ($Preview) { SayT 'drivers_preview_numbers' @($res.Recommended, $res.Problems) 'Yellow'; return 'preview' }
    SayT 'drivers_numbers' @($res.Installed, $res.NotNeeded, $res.Failed, $res.Problems) 'Green'
    if ($res.GpuBasic) {
        SayT 'gpu_basic' @() 'Yellow'
        $go = Read-Choice (T 'ask_open_gpu') @('Y', 'N')
        if ($go -eq 'Y') {
            $urls = @{ 'NVIDIA' = 'https://www.nvidia.com/Download/index.aspx'; 'AMD' = 'https://www.amd.com/en/support/download/drivers.html'; 'Intel' = 'https://www.intel.com/content/www/us/en/support/detect.html' }
            foreach ($v in @($res.GpuVendors)) { if ($urls.ContainsKey([string]$v)) { try { Start-Process $urls[[string]$v] } catch { } } }
        }
    }
    return 'done'
}

function Step-Restart {
    SayT 'step_restart_title' @() 'White'
    $pending = Test-PendingReboot
    $need = Test-RestartNeeded $pending $script:DriverResult
    if ($Preview) { SayT 'preview_restart' @() 'Yellow'; return 'preview' }
    if (-not $need) { SayT 'restart_not_needed' @() 'Green'; return 'done' }
    SayT 'restart_needed' @() 'Yellow'
    $ans = Read-Choice (T 'ask_restart_now') @('R', 'C')
    if ($ans -eq 'C') { SayT 'restart_later' @() 'DarkGray'; return 'done' }
    Complete-Step 'restart'
    SayT 'restarting' @() 'Yellow'
    try { & shutdown.exe /r /t 20 /c 'PC Optimizer Easy Setup: restarting. Run 0_Easy_Setup again afterwards to finish.' } catch { }
    return 'stop'
}

function Step-Tweaks {
    SayT 'step_tweaks_title' @() 'White'
    $prof = $script:ProfileName
    if ($Preview) { SayT $(if ($script:Facts.Laptop) { 'preview_tweaks_laptop' } else { 'preview_tweaks' }) @($prof) 'Yellow'; return 'preview' }
    SayT 'tweaks_running' @() 'DarkGray'
    $master = @(Get-ChildItem -LiteralPath $EasyRoot -File -Filter '1_Start_Here*.bat' -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($master.Count -eq 0) { SayT 'tweaks_missing' @() 'Red'; return 'failed' }
    try {
        $p = Start-Process -FilePath 'cmd.exe' -ArgumentList ('/c ""' + $master[0].FullName + '" /easy ' + $prof + '"') -Wait -PassThru -NoNewWindow
        if ($null -eq $p) { return 'failed' }
    } catch { SayT 'tweaks_missing' @() 'Red'; return 'failed' }
    SayT 'tweaks_done' @() 'Green'
    return 'done'
}

function Step-Dns {
    SayT 'step_dns_title' @() 'White'
    if ($Preview) { SayT 'preview_dns' @() 'Yellow'; return 'preview' }
    if (-not $script:Online) { SayT 'skip_offline' @() 'DarkGray'; return 'skipped' }
    $ans = Read-Choice (T 'ask_dns') @('N', 'Y')
    if ($ans -ne 'Y') { SayT 'skipped' @() 'DarkGray'; return 'skipped' }
    [void](Invoke-Tool 'Network_Test.ps1' @('-Root', $EasyRoot))
    return 'done'
}

function Step-Verify {
    SayT 'step_verify_title' @() 'White'
    if ($Preview) { SayT 'preview_verify' @() 'Yellow'; return 'preview' }
    $snap = Get-SettingsSnapshot (Get-SettingsItems)
    $devices = Get-ProblemDeviceCount
    $b = $script:Before
    Say '' 'Gray'
    SayT 'summary_title' @() 'Cyan'
    if ($null -ne $b) { SayT 'summary_settings_ba' @($b.Ok, $b.Total, $snap.Ok, $snap.Total) 'White' } else { SayT 'summary_settings' @($snap.Ok, $snap.Total) 'White' }
    if ($snap.Bad.Count -gt 0) { SayT 'summary_settings_bad' @(($snap.Bad -join ', ')) 'Yellow' }
    if ($devices -ge 0) {
        if ($null -ne $b -and $b.Devices -ge 0) { SayT 'summary_devices_ba' @($b.Devices, $devices) 'White' } else { SayT 'summary_devices' @($devices) 'White' }
    }
    if ($null -ne $script:DriverResult) { SayT 'summary_drivers' @($script:DriverResult.Installed) 'White' }
    $lines = @()
    $h = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'PC_Health.ps1') -Root $EasyRoot 2>&1 | ForEach-Object { [string]$_ })
    $s = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'PC_Specs.ps1') -Root $EasyRoot 2>&1 | ForEach-Object { [string]$_ })
    $att = @(Select-AttentionLines ($h + $s) 6)
    Say '' 'Gray'
    if ($att.Count -eq 0) { SayT 'summary_attention_none' @() 'Green' }
    else {
        SayT 'summary_attention' @() 'Yellow'
        foreach ($a in $att) { Say ('   - ' + $a) 'Yellow' }
    }
    $script:HadProblems = ($snap.Bad.Count -gt 0) -or ($att.Count -gt 0)
    return 'done'
}

# ---------------------------------------------------------------- main
function Start-EasySetup {
    Set-KeepAwake $true
    try {
        # language
        $st = Get-EasyState
        $code = $Lang
        if ($code -eq 'ask') {
            Write-Host ''
            Write-Host '   PC OPTIMIZER - EASY SETUP' -ForegroundColor Cyan
            Write-Host '   Language / ' -NoNewline
            $thaiName = [string]::Join('', [char[]](0x0E20, 0x0E32, 0x0E29, 0x0E32))
            Write-Host $thaiName -NoNewline
            Write-Host ':   T = ' -NoNewline
            Write-Host ([string]::Join('', [char[]](0x0E44, 0x0E17, 0x0E22))) -NoNewline
            Write-Host '   E = English'
            $def = @('E', 'T')
            if ($env:WT_SESSION) { $def = @('T', 'E') }   # Windows Terminal shows Thai correctly
            if ($st.Lang -eq 'th') { $def = @('T', 'E') } elseif ($st.Lang -eq 'en') { $def = @('E', 'T') }
            $a = Read-Choice '   > ' $def
            $code = $(if ($a -eq 'T') { 'th' } else { 'en' })
        }
        $script:StringsEn = Import-Strings 'en'
        $script:LangCode = $code
        $script:Strings = $(if ($code -eq 'th') { Import-Strings 'th' } else { $script:StringsEn })
        Set-EasyValue 'EasyLang' $code

        Say '' 'Gray'
        Say '==================================================================' 'Cyan'
        SayT 'title' @() 'Cyan'
        Say ('   ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')) 'Cyan'
        Say '==================================================================' 'Cyan'
        if ($Preview) { SayT 'preview_banner' @() 'Yellow' }

        # checks
        $script:Facts = Get-PcFacts
        if (-not $Preview -and -not (Test-IsAdmin)) { SayT 'need_admin' @() 'Red'; return 2 }
        if ($script:Facts.Build -gt 0 -and $script:Facts.Build -lt 22000) {
            SayT 'old_windows' @($script:Facts.Build) 'Yellow'
            if ((Read-Choice (T 'ask_continue') @('N', 'Y')) -ne 'Y') { return 0 }
        }
        if ($script:Facts.FreeGb -gt 0 -and $script:Facts.FreeGb -lt 10) { SayT 'low_space' @($script:Facts.FreeGb) 'Yellow' }
        if ($script:Facts.InstallDays -ge 0 -and $script:Facts.InstallDays -le 30) { SayT 'fresh_windows' @() 'Green' }
        $script:Online = Test-Online
        if ($script:Facts.Laptop) { SayT 'laptop_note' @() 'Gray' }

        # resume?
        $resume = $false
        if (-not $Preview -and @($st.Done).Count -gt 0 -and $st.Profile -ne '') {
            SayT 'resume_found' @() 'Yellow'
            $r = Read-Choice (T 'ask_resume') @('Y', 'N')
            if ($r -eq 'Y') { $resume = $true } else { Clear-EasyState; $st = Get-EasyState }
        }

        # profile
        $script:ProfileName = 'safe'
        if ($resume) { $script:ProfileName = $st.Profile }
        elseif ($Mode -ne 'ask') { $script:ProfileName = $Mode }
        else {
            SayT 'ask_games_intro' @() 'Gray'
            $g = Read-Choice (T 'ask_games') @('N', 'Y')
            $script:ProfileName = Get-TweakProfile $g
        }
        if ($script:Facts.Laptop -and $script:ProfileName -eq 'games') { SayT 'games_laptop_note' @() 'Gray' }
        Set-EasyValue 'EasyProfile' $script:ProfileName
        if ($script:ProfileName -eq 'games') { SayT 'profile_games' @() 'Gray' } else { SayT 'profile_safe' @() 'Gray' }

        # the plan and the one confirmation
        Say '' 'Gray'
        SayT 'plan_title' @() 'White'
        $n = 0
        foreach ($k in (Get-EasyPlan $script:Facts.Laptop $script:Online $script:ProfileName)) { $n++; Say ('   ' + $n + '. ' + (T $k)) 'Gray' }
        SayT 'plan_footer' @() 'Green'
        if (-not $Preview -and -not $Yes -and -not $resume) {
            $go = Read-Choice (T 'ask_start') @('Y', 'Q')
            if ($go -eq 'Q') { SayT 'quit_now' @() 'DarkGray'; return 0 }
        }

        # run the steps in order
        $done = @(); if ($resume) { $done = @($st.Done) }
        $script:Before = $null
        if ($resume -and $st.Done -contains 'before') {
            try {
                $bv = (Get-ItemProperty -Path $script:StateKey -Name EasyBefore -ErrorAction Stop).EasyBefore -split '/'
                $script:Before = @{ Ok = [int]$bv[0]; Total = [int]$bv[1]; Devices = [int]$bv[2] }
            } catch { }
        }
        $failed = @()
        $total = $script:StepOrder.Count
        $idx = 0
        foreach ($id in $script:StepOrder) {
            $idx++
            if ($done -contains $id -and -not $Preview) { continue }
            Say '' 'Gray'
            SayT 'step_header' @($idx, $total) 'Cyan'
            $result = 'done'
            switch ($id) {
                'update' { $result = Step-Update }
                'restore' { $result = Step-Restore }
                'before' { $result = Step-Before }
                'network' { $result = Step-Network }
                'winupdate' { $result = Step-WinUpdate }
                'drivers' { $result = Step-Drivers }
                'restart' { $result = Step-Restart }
                'tweaks' { $result = Step-Tweaks }
                'dns' { $result = Step-Dns }
                'verify' { $result = Step-Verify }
            }
            if ($result -eq 'stop') { SayT 'stopped_here' @() 'Yellow'; return 0 }
            if ($result -eq 'failed') { $failed += $id }
            if ($result -ne 'preview') { Complete-Step $id }
        }

        if ($Preview) { Say '' 'Gray'; SayT 'preview_end' @() 'Yellow'; return 0 }

        # the end
        Say '' 'Gray'
        if ($failed.Count -gt 0) {
            SayT 'some_failed' @(($failed -join ', ')) 'Yellow'
        }
        SayT 'final_undo' @() 'Gray'
        $guide = Join-Path $EasyRoot 'docs\GPU_Driver_Guide_TH.pdf'
        if ($script:LangCode -ne 'th') { $guide = Join-Path $EasyRoot 'docs\GPU_Driver_Guide_EN.pdf' }
        if (Test-Path -LiteralPath $guide) { SayT 'final_gpu_guide' @(('docs\' + (Split-Path -Leaf $guide))) 'Gray' }
        if ($failed.Count -gt 0 -or $script:HadProblems) {
            $b = Read-Choice (T 'ask_bundle') @('N', 'Y')
            if ($b -eq 'Y') { [void](Invoke-Tool 'Support_Bundle.ps1' @('-Root', $EasyRoot)) }
        }
        Clear-EasyState
        SayT 'final_restart' @() 'Yellow'
        $r2 = Read-Choice (T 'ask_restart_final') @('L', 'R')
        if ($r2 -eq 'R') { try { & shutdown.exe /r /t 20 /c 'PC Optimizer Easy Setup: restarting.' } catch { }; SayT 'restarting' @() 'Yellow' }
        else { SayT 'all_done' @() 'Green' }
        return 0
    } finally {
        Set-KeepAwake $false
        try {
            if ($script:EasyLines.Count -gt 0 -and -not $Preview) {
                [IO.File]::WriteAllLines((New-ReportPath $EasyRoot 'EasySetup'), $script:EasyLines)
                Remove-OldReports $EasyRoot | Out-Null
            }
        } catch { }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $code = @(Start-EasySetup) | Select-Object -Last 1
    exit ([int]$code)
}
