# Windows 11 Optimizer - VM test suite.
# Runs ONLY inside a virtual machine, as administrator. It changes the registry, makes restore points and runs Easy Setup for real,
# then writes one report. It refuses to run on a physical PC. Take a snapshot of the VM first.
#   -DryRun         list the phases and stop (changes nothing, works anywhere)
#   -SkipEasyFull   skip the real Easy Setup run (restore point, drivers, Windows Update)
#   -ReportDir      where the report goes (default: the VirtualBox shared folder "reports", else the Desktop)
#   -EasyTimeoutMin minutes the real Easy Setup run may take (default 45)
param(
    [switch]$DryRun,
    [switch]$SkipEasyFull,
    [string]$ReportDir = '',
    [int]$EasyTimeoutMin = 45
)

$ErrorActionPreference = 'Continue'
$script:Root = Split-Path -Parent $PSScriptRoot
$script:Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:Work = Join-Path $env:TEMP ('vmtest_' + $script:Stamp)
$script:Lines = New-Object System.Collections.Generic.List[string]
$script:Results = New-Object System.Collections.Generic.List[object]

function Say([string]$Text, [string]$Color = 'Gray') {
    Write-Host $Text -ForegroundColor $Color
    $script:Lines.Add($Text)
}

function Test-Admin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-VmFacts {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $text = (@($cs.Manufacturer, $cs.Model, $bios.Version, $bios.SMBIOSBIOSVersion, $bios.Manufacturer) -join ' ')
    return [pscustomobject]@{
        IsVm = ($text -match 'VirtualBox|innotek|VMware|Virtual Machine|QEMU|KVM|Xen|Parallels|Bochs')
        Vendor = [string]$cs.Manufacturer
        Model = [string]$cs.Model
        Os = [string]$os.Caption
        Build = [string]$os.BuildNumber
        Ram = [math]::Round(([double]$cs.TotalPhysicalMemory) / 1GB, 1)
    }
}

# Runs a program, collects its output, never waits longer than the timeout.
function Invoke-Child([string]$Exe, [string]$ArgLine, [int]$TimeoutMin = 10, [hashtable]$EnvVars = @{}) {
    $t0 = Get-Date
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = $ArgLine
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.WorkingDirectory = $script:Root
    foreach ($k in $EnvVars.Keys) { $psi.EnvironmentVariables[$k] = [string]$EnvVars[$k] }
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    $timedOut = $false
    if (-not $p.WaitForExit($TimeoutMin * 60000)) {
        $timedOut = $true
        try { $p.Kill() } catch { }
    }
    $p.WaitForExit()
    return [pscustomobject]@{
        Exit = $(if ($timedOut) { -1 } else { $p.ExitCode })
        Out = ($outTask.Result + "`r`n" + $errTask.Result)
        TimedOut = $timedOut
        Seconds = [int]((Get-Date) - $t0).TotalSeconds
    }
}

function Invoke-PsFile([string]$Relative, [string]$ExtraArgs = '', [int]$TimeoutMin = 10, [hashtable]$EnvVars = @{}) {
    $file = Join-Path $script:Root $Relative
    return Invoke-Child 'powershell.exe' ('-NoProfile -ExecutionPolicy Bypass -File "' + $file + '" ' + $ExtraArgs) $TimeoutMin $EnvVars
}

function Invoke-Bat([string]$Bat, [string]$ExtraArgs, [string]$StdinFile, [int]$TimeoutMin = 10) {
    $redir = $(if ($StdinFile -ne '') { '< "' + $StdinFile + '"' } else { '< nul' })
    return Invoke-Child 'cmd.exe' ('/d /s /c ""' + $Bat + '" ' + $ExtraArgs + ' ' + $redir + '"') $TimeoutMin
}

function Save-Output([string]$Id, [object]$Run) {
    if (-not (Test-Path -LiteralPath $script:Work)) { New-Item -ItemType Directory -Path $script:Work -Force | Out-Null }
    $f = Join-Path $script:Work (($Id -replace '[^A-Za-z0-9._-]', '_') + '.txt')
    [IO.File]::WriteAllText($f, [string]$Run.Out, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-Tail([object]$Run, [int]$Count = 6) {
    $l = @(([string]$Run.Out) -split "`r?`n" | Where-Object { $_.Trim() -ne '' })
    return (($l | Select-Object -Last $Count) -join ' | ')
}

# Reads the settings state with the same code the Check Status tool uses.
# Map: the numbered tweaks ('01'..'20') -> status. OkTotal: every item that reads OK (tweaks, power plan, power settings, services ...), the
# number that Easy Setup shows as "speed settings in place".
function Get-SettingsState {
    $r = Invoke-PsFile 'VM_TEST\status_probe.ps1' ('-Root "' + $script:Root + '"') 3
    $map = @{}
    $okTotal = 0
    foreach ($l in ([string]$r.Out -split "`r?`n")) {
        if ($l -match '^(\w+)\|(\w+)\s*$') {
            $itemId = $Matches[1]; $itemStatus = $Matches[2]      # copy first: the next -match replaces $Matches
            if ($itemStatus -eq 'OK') { $okTotal++ }
            if ($itemId -match '^\d\d$') { $map[$itemId] = $itemStatus }
        }
    }
    return [pscustomobject]@{ Map = $map; OkTotal = $okTotal }
}

# What each Easy Setup profile must leave behind: tweaks that must read OK and tweaks that must not be applied. Returns the problems.
function Test-Profile([object]$State, [string]$Profile) {
    $must = @('01', '02', '03', '04', '05', '06', '07', '08', '14')
    $not = @('09', '10', '11', '12', '13', '15', '18', '19', '20')
    $extra = @{ safe = @(); games = @('10', '11', '15'); max = @('09', '10', '11', '12', '15', '18', '19', '20'); max13 = @('09', '10', '11', '12', '13', '15', '18', '19', '20') }[$Profile]
    $must += $extra
    $not = @($not | Where-Object { $extra -notcontains $_ })
    $bad = @()
    foreach ($id in $must) { if ($State.Map[$id] -ne 'OK') { $bad += ('tweak ' + $id + ' is ' + $State.Map[$id] + ', must be OK') } }
    foreach ($id in $not) { if ($State.Map[$id] -eq 'OK') { $bad += ('tweak ' + $id + ' is applied, but this profile must not apply it') } }
    return $bad
}

function Result([bool]$Ok, [string]$Detail) { return [pscustomobject]@{ Ok = $Ok; Detail = $Detail } }

# --------------------------------------------------------------------------- the phases
$bat1 = Join-Path $script:Root '1_Start_Here - PC_Optimizer_Master (Run as Administrator).bat'
$phases = New-Object System.Collections.Generic.List[object]
function Add-Phase([string]$Id, [string]$Name, [scriptblock]$Body, [object[]]$PhaseArgs = @()) { $phases.Add([pscustomobject]@{ Id = $Id; Name = $Name; Body = $Body; PhaseArgs = $PhaseArgs }) }

Add-Phase 'P0.1' 'Environment: administrator, free space, version' {
    $free = [math]::Round((Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':'))).Free / 1GB, 1)
    $v = ([IO.File]::ReadAllText((Join-Path $script:Root 'VERSION'))).Trim()
    Say ('    tool version ' + $v + ', free space on ' + $env:SystemDrive + ' ' + $free + ' GB, PowerShell ' + $PSVersionTable.PSVersion) 'DarkGray'
    return (Result (($free -ge 3) -and (Test-Admin)) ('free ' + $free + ' GB, admin ' + (Test-Admin)))
}
Add-Phase 'P0.2' 'Internet reachable (some phases need it)' {
    $ok = $false
    try { $ok = [bool](Test-Connection -ComputerName 1.1.1.1 -Count 1 -Quiet -ErrorAction Stop) } catch { }
    if (-not $ok) { Say '    no internet: the update check, driver search and Windows Update steps cannot be tested' 'Yellow' }
    return (Result $true $(if ($ok) { 'online' } else { 'offline (warning only)' }))
}
Add-Phase 'P0.3' 'System Protection on, more than one restore point per day allowed' {
    $note = ''
    try { Enable-ComputerRestore -Drive ($env:SystemDrive + '\') -ErrorAction Stop; $note = 'System Protection enabled' } catch { $note = 'could not enable System Protection: ' + $_.Exception.Message }
    try {
        $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        New-ItemProperty -Path $k -Name 'SystemRestorePointCreationFrequency' -Value 0 -PropertyType DWord -Force | Out-Null
    } catch { $note += '; frequency not set' }
    $has = $true
    try { [void](Get-ComputerRestorePoint -ErrorAction Stop) } catch { $has = $false }
    return (Result $has $note)
}
foreach ($t in @(
        @('P1.1', 'Env_Check', 'tools\Env_Check.ps1', '-Human'),
        @('P1.2', 'System_Report', 'tools\System_Report.ps1', ''),
        @('P1.3', 'Driver_Check (scan only)', 'tools\Driver_Check.ps1', '-SkipUpdateSearch -NoPrompt'),
        @('P1.4', 'Driver_Clean (list only)', 'tools\Driver_Clean.ps1', '-NoPrompt'),
        @('P1.5', 'PC_Specs', 'tools\PC_Specs.ps1', ('-Root "' + $script:Root + '"')),
        @('P1.6', 'PC_Health', 'tools\PC_Health.ps1', ('-Root "' + $script:Root + '"')),
        @('P1.7', 'Clean_Up (list only)', 'tools\Clean_Up.ps1', '-NoPrompt'))) {
    $tid = $t[0]; $tname = $t[1]; $trel = $t[2]; $targs = $t[3]
    Add-Phase $tid ('Read-only tool: ' + $tname) {
        param($tid, $trel, $targs)
        $r = Invoke-PsFile $trel $targs 10
        Save-Output $tid $r
        return (Result (($r.Exit -eq 0) -and -not $r.TimedOut) ('exit ' + $r.Exit + ', ' + $r.Seconds + ' s. ' + $(if ($r.Exit -ne 0) { Get-Tail $r } else { '' })))
    } @($tid, $trel, $targs)
}
Add-Phase 'P1.8' 'Support bundle: sections present, no user or computer name inside' {
    $r = Invoke-PsFile 'tools\Support_Bundle.ps1' ('-Root "' + $script:Root + '"') 10
    Save-Output 'P1.8' $r
    $b = @(Get-ChildItem -Path (Join-Path $script:Root 'Logs') -Filter 'SupportBundle_*.txt' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending) | Select-Object -First 1
    if ($r.Exit -ne 0 -or $null -eq $b) { return (Result $false ('exit ' + $r.Exit + ', no bundle file')) }
    $t = [IO.File]::ReadAllText($b.FullName)
    $missing = @('## Environment', '## Check Status', '## PC specs', '## PC health', '## System report', '## Driver scan' | Where-Object { -not $t.Contains($_) })
    $leak = ($t -match [regex]::Escape($env:USERNAME + '\')) -or $t.Contains($env:COMPUTERNAME)
    return (Result (($missing.Count -eq 0) -and -not $leak) ('missing sections: ' + ($missing -join ', ') + '; name leak: ' + $leak))
}
Add-Phase 'P2' 'Registry round trip: every tweak applied, detected, undone, detected (tests\Test-RegRoundTrip.ps1)' {
    $r = Invoke-PsFile 'tests\Test-RegRoundTrip.ps1' '' 15 @{ CI = 'true' }
    Save-Output 'P2' $r
    return (Result (($r.Exit -eq 0) -and -not $r.TimedOut) ('exit ' + $r.Exit + ', ' + $r.Seconds + ' s. ' + $(if ($r.Exit -ne 0) { Get-Tail $r 10 } else { '' })))
}
Add-Phase 'P3' 'Main menu: starts, reverts one tweak, health, bundle, specs, exits' {
    $r = Invoke-Bat $bat1 '' (Join-Path $script:Root 'tests\master_input.txt') 10
    Save-Output 'P3' $r
    $need = @('MASTER CONTROL v', 'Reverting with UNDO_15', 'PC HEALTH', 'SUPPORT BUNDLE', 'YOUR PC ON ONE PAGE')
    $miss = @($need | Where-Object { -not ([string]$r.Out).Contains($_) })
    return (Result (($miss.Count -eq 0) -and -not $r.TimedOut) ('missing in the output: ' + ($miss -join ', ')))
}
foreach ($m in @(@('P4.1', 'games'), @('P4.2', 'max'), @('P4.3', 'max13'))) {
    $pid2 = $m[0]; $mode = $m[1]
    Add-Phase $pid2 ('Easy Setup settings step, profile ' + $mode + ', then the settings must read as that profile') {
            param($pid2, $mode)
            $r = Invoke-Bat $bat1 ('/easy ' + $mode) '' 12
            Save-Output $pid2 $r
            if (-not ([string]$r.Out).Contains('The settings step is finished')) { return (Result $false ('the step did not finish. ' + (Get-Tail $r))) }
            $s = Get-SettingsState
            $bad = @(Test-Profile $s $mode)
            return (Result ($bad.Count -eq 0) ([string]$s.OkTotal + ' items read OK. ' + ($bad -join '; ')))
    } @($pid2, $mode)
}
Add-Phase 'P5' 'Undo everything with the undo files: no numbered tweak may still read OK' {
    $fails = 0
    foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $script:Root 'reg_undo') -File -Filter 'UNDO_*.reg' | Sort-Object Name)) {
        & reg.exe import $f.FullName *> $null
        if ($LASTEXITCODE -ne 0) { $fails++ }
    }
    $s = Get-SettingsState
    $still = @(@($s.Map.Keys) | Where-Object { $_ -ne '16' -and $s.Map[$_] -eq 'OK' } | Sort-Object)   # 16 (CPU boost) is a power setting, not a .reg file
    return (Result (($fails -eq 0) -and ($still.Count -eq 0)) ('import failures ' + $fails + ', still OK after undo: ' + ($still -join ', ')))
}
if (-not $SkipEasyFull) {
    Add-Phase 'P6' 'Easy Setup, the whole flow for real (restore point, drivers, Windows Update, settings, summary)' {
        $r = Invoke-PsFile 'tools\Easy_Setup.ps1' ('-Yes -NoPrompt -SkipUpdate -Mode safe') $EasyTimeoutMin
        Save-Output 'P6' $r
        $out = [string]$r.Out
        if ($r.TimedOut) { return (Result $false ('timed out after ' + $EasyTimeoutMin + ' minutes. ' + (Get-Tail $r))) }
        if ($out -match 'earlier Easy Setup' -or $out -match 'profile_') { return (Result $false 'it asked about an earlier run or printed a raw message key') }
        if ($out -notmatch 'SUMMARY') { return (Result $false ('no summary. ' + (Get-Tail $r 8))) }
        $s = Get-SettingsState
        $rp = $false
        try { $rp = @(Get-ComputerRestorePoint -ErrorAction Stop | Where-Object { $_.Description -eq 'Before_PC_Optimizer' }).Count -gt 0 } catch { }
        $bad = @(Test-Profile $s 'safe')
        if (-not $rp) { $bad += 'the restore point Before_PC_Optimizer is missing' }
        if ($s.OkTotal -lt 18) { $bad += ('only ' + $s.OkTotal + ' items read OK, expected 18 or more') }
        return (Result ($bad.Count -eq 0) ([string]$s.OkTotal + ' items read OK, restore point present: ' + $rp + ', ' + $r.Seconds + ' s. ' + ($bad -join '; ')))
    }
}

Add-Phase 'P7' 'The Windows app: self-test (status script, apply and revert of one tweak, run without a window)' {
    $exe = Join-Path $script:Root 'Win11 Optimizer.exe'
    if (-not (Test-Path -LiteralPath $exe)) { return (Result $false 'Win11 Optimizer.exe is not in the edition') }
    $out = Join-Path $env:TEMP 'app_selftest.txt'
    Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
    $r = Invoke-Child $exe ('--selftest --out "' + $out + '"') 12
    $text = ''
    if (Test-Path -LiteralPath $out) { $text = [IO.File]::ReadAllText($out) }
    Save-Output 'P7' ([pscustomobject]@{ Out = $text })
    $failed = @(($text -split "`r?`n") | Where-Object { $_ -like 'FAIL*' })
    return (Result (($r.Exit -eq 0) -and -not $r.TimedOut -and $text.Contains('ALL PASSED')) ('exit ' + $r.Exit + ', ' + $r.Seconds + ' s. ' + ($failed -join ' | ')))
}

# --------------------------------------------------------------------------- run
$facts = Get-VmFacts
Say '==================================================================' 'Cyan'
Say ('   Windows 11 Optimizer - VM test suite   ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')) 'Cyan'
Say '==================================================================' 'Cyan'
Say ('   Machine: ' + $facts.Vendor + ' ' + $facts.Model + ' | ' + $facts.Os + ' build ' + $facts.Build + ' | RAM ' + $facts.Ram + ' GB | virtual machine: ' + $facts.IsVm) 'Gray'
Say ('   Tool folder: ' + $script:Root) 'Gray'

if ($DryRun) {
    Say '' 'Gray'
    Say '   Dry run: these phases would run (nothing is changed):' 'Yellow'
    foreach ($p in $phases) { Say ('   ' + $p.Id.PadRight(6) + $p.Name) 'Gray' }
    exit 0
}
if (-not $facts.IsVm) {
    Say '' 'Gray'
    Say '   REFUSED: this is not a virtual machine. The suite changes the registry and makes restore points; run it only in a VM.' 'Red'
    exit 2
}
if (-not (Test-Admin)) {
    Say '   REFUSED: run it as administrator (right-click, Run as administrator).' 'Red'
    exit 2
}

Say '' 'Gray'
foreach ($p in $phases) {
    $t0 = Get-Date
    Say ('>> ' + $p.Id + '  ' + $p.Name) 'White'
    $res = $null
    try { $pa = @($p.PhaseArgs); $res = & $p.Body @pa } catch { $res = Result $false ('exception: ' + $_.Exception.Message) }
    if ($null -eq $res -or $res.PSObject.Properties.Name -notcontains 'Ok') { $res = Result $false 'the phase returned nothing' }
    $sec = [int]((Get-Date) - $t0).TotalSeconds
    $st = $(if ($res.Ok) { 'PASS' } else { 'FAIL' })
    $script:Results.Add([pscustomobject]@{ Id = $p.Id; Name = $p.Name; Status = $st; Seconds = $sec; Detail = [string]$res.Detail })
    Say ('   [' + $st + '] ' + $res.Detail + ' (' + $sec + ' s)') $(if ($res.Ok) { 'Green' } else { 'Red' })
}

$pass = @($script:Results | Where-Object { $_.Status -eq 'PASS' }).Count
$fail = @($script:Results | Where-Object { $_.Status -eq 'FAIL' }).Count
Say '' 'Gray'
Say '==================== SUMMARY ====================' 'Cyan'
foreach ($r in $script:Results) { Say ('   ' + $r.Status + '  ' + $r.Id.PadRight(6) + $r.Name) $(if ($r.Status -eq 'PASS') { 'Green' } else { 'Red' }) }
Say ('   ' + $pass + ' passed, ' + $fail + ' failed') $(if ($fail -eq 0) { 'Green' } else { 'Red' })

# report: the VirtualBox shared folder "reports" if it is there, else the Desktop
if ($ReportDir -eq '') {
    if (Test-Path -LiteralPath '\\VBoxSvr\reports') { $ReportDir = '\\VBoxSvr\reports' }
    else { $ReportDir = Join-Path ([Environment]::GetFolderPath('Desktop')) 'VMTEST_Reports' }
}
try {
    if (-not (Test-Path -LiteralPath $ReportDir)) { New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null }
    $dest = Join-Path $ReportDir ('VMTEST_' + $script:Stamp)
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $dest 'VMTEST_summary.txt'), (($script:Lines -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $script:Work) { Copy-Item -Path (Join-Path $script:Work '*') -Destination $dest -Force -ErrorAction SilentlyContinue }
    $logs = Join-Path $script:Root 'Logs'
    if (Test-Path -LiteralPath $logs) { Copy-Item -Path (Join-Path $logs '*') -Destination $dest -Force -ErrorAction SilentlyContinue }
    Say ('   Report saved in ' + $dest) 'Gray'
} catch {
    Say ('   Could not save the report: ' + $_.Exception.Message) 'Yellow'
}
if ($fail -gt 0) { exit 1 }
exit 0
