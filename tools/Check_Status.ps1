# PC Optimizer v4.7 - Check Status
# Compares the current PC settings with what the optimizer applies,
# then offers to re-apply only the items that are missing or changed.
param([string]$Root = '')

$ErrorActionPreference = 'Continue'
$StateKey = 'HKCU:\Software\PCOptimizer'

# ---------------------------------------------------------------- helpers
function Read-RegFile([string]$Path) {
    # Returns every value a .reg file sets: Key, Name, Type (DWord or String), Value
    $entries = New-Object System.Collections.Generic.List[object]
    $key = $null
    foreach ($raw in [IO.File]::ReadAllLines($Path)) {
        $line = $raw.Trim()
        if ($line -eq '' -or $line.StartsWith(';') -or $line.StartsWith('Windows Registry Editor')) { continue }
        if ($line.StartsWith('[') -and $line.EndsWith(']')) {
            $key = $line.Substring(1, $line.Length - 2)
            if ($key.StartsWith('-')) { $key = $null }
            continue
        }
        if ($null -eq $key) { continue }
        $name = $null
        $data = $null
        if ($line.StartsWith('@=')) {
            $name = ''
            $data = $line.Substring(2)
        } elseif ($line -match '^"(?<n>[^"]*)"=(?<v>.*)$') {
            $name = $Matches['n']
            $data = $Matches['v']
        } else {
            continue
        }
        if ($data -eq '-') { continue }
        if ($data -match '^dword:(?<h>[0-9a-fA-F]{8})$') {
            $entries.Add([pscustomobject]@{ Key = $key; Name = $name; Type = 'DWord'; Value = [int64][Convert]::ToUInt32($Matches['h'], 16) })
        } elseif ($data -match '^"(?<s>.*)"$') {
            $entries.Add([pscustomobject]@{ Key = $key; Name = $name; Type = 'String'; Value = ($Matches['s'] -replace '\\\\', '\') })
        }
    }
    return ,$entries
}

function Get-RegValue([string]$Key, [string]$Name) {
    try { $k = Get-Item -LiteralPath ('Registry::' + $Key) -ErrorAction Stop } catch { return $null }
    return $k.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
}

function ConvertTo-UInt32Value($v) {
    # Registry DWORDs come back as signed Int32 - turn them into the unsigned number the .reg file shows
    return [int64][BitConverter]::ToUInt32([BitConverter]::GetBytes([int32]$v), 0)
}

function Test-RegEntry($Entry) {
    # Returns 'ok', 'missing' or 'different'
    $v = Get-RegValue $Entry.Key $Entry.Name
    if ($null -eq $v) { return 'missing' }
    if ($Entry.Type -eq 'DWord') {
        if ($v -isnot [int]) { return 'different' }
        if ((ConvertTo-UInt32Value $v) -eq $Entry.Value) { return 'ok' }
        return 'different'
    }
    if ([string]$v -ceq [string]$Entry.Value) { return 'ok' }
    return 'different'
}

function Format-Actual($Entry) {
    $v = Get-RegValue $Entry.Key $Entry.Name
    if ($null -eq $v) { return 'not set' }
    if ($Entry.Type -eq 'DWord' -and $v -is [int]) { return ('0x{0:x8}' -f (ConvertTo-UInt32Value $v)) }
    return [string]$v
}

function Format-Expected($Entry) {
    if ($Entry.Type -eq 'DWord') { return ('0x{0:x8}' -f $Entry.Value) }
    return [string]$Entry.Value
}

function Get-Choice([string]$Name) {
    try { return [string](Get-ItemProperty -Path $StateKey -Name ('Choice_' + $Name) -ErrorAction Stop).('Choice_' + $Name) } catch { return '' }
}

function Set-Choice([string]$Name, [string]$Value) {
    if (-not (Test-Path $StateKey)) { New-Item -Path $StateKey -Force | Out-Null }
    New-ItemProperty -Path $StateKey -Name ('Choice_' + $Name) -Value $Value -PropertyType String -Force | Out-Null
}

function Get-PowerIndex([string[]]$QueryArgs) {
    # Reads the plugged-in (AC) value of one power setting, whatever the Windows display language.
    $out = & powercfg.exe /query SCHEME_CURRENT @QueryArgs 2>$null
    if ($LASTEXITCODE -ne 0 -or $null -eq $out) { return $null }
    $hex = @([regex]::Matches(($out -join "`n"), '0x[0-9a-fA-F]{8}') | ForEach-Object { $_.Value })
    if ($hex.Count -lt 2) { return $null }
    return [Convert]::ToInt64($hex[$hex.Count - 2], 16)   # the last two are AC then DC
}

function Get-ActiveSchemeGuid {
    $out = (& powercfg.exe /getactivescheme 2>$null) -join ' '
    $m = [regex]::Match($out, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
    if ($m.Success) { return $m.Value.ToLower() }
    return ''
}

function Test-SchemeExists([string]$Guid) {
    if ($Guid -eq '') { return $false }
    & powercfg.exe /query $Guid *> $null
    return ($LASTEXITCODE -eq 0)
}

# ---------------------------------------------------------------- report items
$script:Items = New-Object System.Collections.Generic.List[object]

function Add-Item($Key, $Id, $Title, $Status, $Detail, $Kind, $FixType, $FixData) {
    # Kind: 'auto' = fix together with the others, 'ask' = always ask one by one
    # FixType: reg, plan, pwr, pref, tcp, svc - or $null when nothing can be fixed
    $script:Items.Add([pscustomobject]@{ Key = $Key; Id = $Id; Title = $Title; Status = $Status; Detail = $Detail; Kind = $Kind; FixType = $FixType; FixData = $FixData })
}

function Get-RegTweakStatus($File) {
    $entries = Read-RegFile $File.FullName
    $bad = New-Object System.Collections.Generic.List[string]
    $missing = 0
    foreach ($e in $entries) {
        $r = Test-RegEntry $e
        if ($r -ne 'ok') {
            if ($r -eq 'missing') { $missing++ }
            $shortKey = ($e.Key -split '\\')[-1]
            $valueName = $e.Name
            if ($valueName -eq '') { $valueName = '(default)' }
            $bad.Add(($shortKey + '\' + $valueName + ' = ' + (Format-Actual $e) + ', expected ' + (Format-Expected $e)))
        }
    }
    if ($entries.Count -eq 0) { return @{ Status = 'UNKNOWN'; Detail = 'no values found in the file' } }
    if ($bad.Count -eq 0) { return @{ Status = 'OK'; Detail = '' } }
    $status = 'CHANGED'
    if ($missing -eq $entries.Count) { $status = 'MISSING' }
    $detail = $bad[0]
    if ($bad.Count -gt 1) { $detail += ('  (+' + ($bad.Count - 1) + ' more)') }
    return @{ Status = $status; Detail = $detail }
}

function Invoke-RegFix($File, [string]$BackupDir) {
    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
    $i = 0
    $ents = Read-RegFile $File.FullName
    foreach ($k in @($ents | ForEach-Object { $_.Key } | Select-Object -Unique)) {
        $i++
        & reg.exe export $k (Join-Path $BackupDir ($File.BaseName + '_key' + $i + '.reg')) /y *> $null
    }
    & reg.exe import $File.FullName *> $null
    return ($LASTEXITCODE -eq 0)
}

function Invoke-Checks([string]$RegRoot, [string]$BackupDir) {
    $script:Items.Clear()

    # --- every numbered .reg file
    $files = @(Get-ChildItem -Path $RegRoot -Recurse -Filter '*.reg' | Where-Object { $_.Name -match '^\d{2}_' } | Sort-Object Name)
    foreach ($f in $files) {
        $num = $f.Name.Substring(0, 2)
        $title = ($f.BaseName.Substring(3)) -replace '_', ' '
        $optional = ($f.Directory.Name -match 'Optional')
        $r = Get-RegTweakStatus $f
        $status = $r.Status
        $choice = Get-Choice $num
        if ($status -ne 'OK' -and $status -ne 'UNKNOWN') {
            if ($choice -eq 'N') { $status = 'SKIPPED'; $r.Detail = 'you chose not to use this' }
            elseif ($optional -and $choice -eq '') { $status = 'NOT CHOSEN'; $r.Detail = 'optional - never applied or answered' }
        }
        $kind = 'auto'
        if ($optional) { $kind = 'ask' }
        Add-Item ('REG' + $num) $num $title $status $r.Detail $kind 'reg' $f
    }

    # --- power plan + power settings
    $powerChoice = Get-Choice 'POWER'
    $ultimate = ''
    try { $ultimate = ([string](Get-ItemProperty -Path $StateKey -Name 'UltimateGUID' -ErrorAction Stop).UltimateGUID).ToLower() } catch { }
    $high = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    $active = Get-ActiveSchemeGuid
    $target = $high
    if (Test-SchemeExists $ultimate) { $target = $ultimate }
    if ($powerChoice -eq 'N') {
        Add-Item 'PLAN' 'PLAN' 'Power plan' 'SKIPPED' 'you reset the power plans' 'auto' $null $null
    } elseif ($active -eq '') {
        Add-Item 'PLAN' 'PLAN' 'Power plan' 'UNKNOWN' 'could not read the active plan' 'auto' $null $null
    } elseif ($active -eq $target -or ($ultimate -ne '' -and $active -eq $ultimate)) {
        Add-Item 'PLAN' 'PLAN' 'Power plan' 'OK' '' 'auto' $null $null
    } else {
        Add-Item 'PLAN' 'PLAN' 'Power plan' 'CHANGED' ('active plan is ' + $active) 'auto' 'plan' $target
    }

    $powerSettings = @(
        @{ Title = 'Minimum CPU state 100';      Args = @('SUB_PROCESSOR', 'PROCTHROTTLEMIN'); Want = 100 },
        @{ Title = 'Core parking off';           Args = @('SUB_PROCESSOR', 'CPMINCORES');      Want = 100 },
        @{ Title = 'USB selective suspend off';  Args = @('2a737441-1930-4402-8d77-b2bebba308a3', '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'); Want = 0 },
        @{ Title = 'PCIe link power saving off'; Args = @('SUB_PCIEXPRESS', 'ASPM');           Want = 0 }
    )
    foreach ($p in $powerSettings) {
        $k = 'PWR:' + $p.Title
        if ($powerChoice -eq 'N') { Add-Item $k 'PWR' $p.Title 'SKIPPED' 'you reset the power plans' 'auto' $null $null; continue }
        $v = Get-PowerIndex $p.Args
        if ($null -eq $v) { Add-Item $k 'PWR' $p.Title 'UNKNOWN' 'not available on this PC' 'auto' $null $null; continue }
        if ($v -eq $p.Want) { Add-Item $k 'PWR' $p.Title 'OK' '' 'auto' $null $null; continue }
        Add-Item $k 'PWR' $p.Title 'CHANGED' ('now ' + $v + ', expected ' + $p.Want) 'auto' 'pwr' $p
    }

    # --- optional 16: CPU boost aggressive + energy preference 0 (plugged in)
    $boostChoice = Get-Choice '16'
    $eppNow = Get-PowerIndex @('SUB_PROCESSOR', 'PERFEPP')
    $boostNow = Get-PowerIndex @('SUB_PROCESSOR', 'PERFBOOSTMODE')
    if ($null -eq $eppNow -or $null -eq $boostNow) {
        Add-Item 'BOOST' '16' 'CPU boost aggressive' 'UNKNOWN' 'not available on this PC' 'ask' $null $null
    } elseif ($eppNow -eq 0 -and $boostNow -eq 2) {
        Add-Item 'BOOST' '16' 'CPU boost aggressive' 'OK' '' 'ask' $null $null
    } else {
        $bstatus = 'CHANGED'
        $bdetail = 'boost mode ' + $boostNow + ' and preference ' + $eppNow + ', expected 2 and 0'
        if ($boostChoice -eq 'N') { $bstatus = 'SKIPPED'; $bdetail = 'you chose not to use this' }
        elseif ($boostChoice -eq '') { $bstatus = 'NOT CHOSEN'; $bdetail = 'optional - never applied or answered' }
        Add-Item 'BOOST' '16' 'CPU boost aggressive' $bstatus $bdetail 'ask' 'boost' $null
    }

    # --- optional 17: DNS servers (only listed once you have used it)
    $dnsChoice = Get-Choice '17'
    if ($dnsChoice -eq 'N') {
        Add-Item 'DNS' '17' 'DNS servers' 'SKIPPED' 'you put your old DNS back' 'ask' $null $null
    } elseif ($dnsChoice -eq 'Y') {
        $applied = ''
        try { $applied = [string](Get-ItemProperty -Path $StateKey -Name 'DnsApplied' -ErrorAction Stop).DnsApplied } catch { }
        $wantServers = @($applied -split ',' | Where-Object { $_ -ne '' })
        $badNames = New-Object System.Collections.Generic.List[string]
        try {
            foreach ($ad in @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' })) {
                $now = @((Get-DnsClientServerAddress -InterfaceIndex $ad.ifIndex -AddressFamily IPv4 -ErrorAction Stop).ServerAddresses)
                if (($now -join ',') -ne ($wantServers -join ',')) { $badNames.Add($ad.Name + ' uses ' + ($now -join ', ')) }
            }
        } catch { $badNames.Clear(); $wantServers = @() }
        if ($wantServers.Count -eq 0) {
            Add-Item 'DNS' '17' 'DNS servers' 'UNKNOWN' 'could not read the DNS settings' 'ask' $null $null
        } elseif ($badNames.Count -eq 0) {
            Add-Item 'DNS' '17' ('DNS servers ' + ($wantServers -join ', ')) 'OK' '' 'ask' $null $null
        } else {
            Add-Item 'DNS' '17' ('DNS servers ' + ($wantServers -join ', ')) 'CHANGED' ($badNames[0]) 'ask' 'dns' $wantServers
        }
    }

    # --- prefetcher, by disk type
    $media = ''
    try { $media = [string](Get-PhysicalDisk -ErrorAction Stop | Sort-Object DeviceId | Select-Object -First 1).MediaType } catch { }
    $pfKey = 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters'
    $want = $null
    if ($media -eq 'SSD') { $want = 0 } elseif ($media -eq 'HDD') { $want = 3 }
    if ($null -eq $want) {
        Add-Item 'PREF' 'PREF' 'Prefetcher' 'UNKNOWN' 'disk type could not be detected' 'auto' $null $null
    } else {
        $cur = Get-RegValue $pfKey 'EnablePrefetcher'
        if ($cur -is [int] -and $cur -eq $want) {
            Add-Item 'PREF' 'PREF' ('Prefetcher for ' + $media) 'OK' '' 'auto' $null $null
        } else {
            $shown = 'not set'
            if ($null -ne $cur) { $shown = [string]$cur }
            Add-Item 'PREF' 'PREF' ('Prefetcher for ' + $media) 'CHANGED' ('now ' + $shown + ', expected ' + $want) 'auto' 'pref' @{ Key = $pfKey; Want = $want }
        }
    }

    # --- TCP settings on every network adapter
    $ifRoot = 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
    if ((Get-Choice 'TCP') -eq 'N') {
        Add-Item 'TCP' 'TCP' 'Network per adapter' 'SKIPPED' 'you removed this tweak' 'auto' $null $null
    } else {
        $ifs = @(Get-ChildItem -LiteralPath ('Registry::' + $ifRoot) -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like '{*' })
        $bad = @($ifs | Where-Object { ($_.GetValue('TcpAckFrequency') -ne 1) -or ($_.GetValue('TCPNoDelay') -ne 1) })
        if ($ifs.Count -eq 0) {
            Add-Item 'TCP' 'TCP' 'Network per adapter' 'UNKNOWN' 'no network adapters found' 'auto' $null $null
        } elseif ($bad.Count -eq 0) {
            Add-Item 'TCP' 'TCP' ('Network per adapter - ' + $ifs.Count + ' adapters') 'OK' '' 'auto' $null $null
        } else {
            $paths = @($bad | ForEach-Object { $ifRoot + '\' + $_.PSChildName })
            Add-Item 'TCP' 'TCP' ('Network per adapter - ' + $ifs.Count + ' adapters') 'CHANGED' ($bad.Count.ToString() + ' adapter(s) not set - often a new VPN or Wi-Fi adapter') 'auto' 'tcp' $paths
        }
    }

    # --- telemetry services
    foreach ($svc in @('DiagTrack', 'dmwappushservice')) {
        $start = Get-RegValue ('HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\' + $svc) 'Start'
        if ($null -eq $start) { continue }
        if ($start -eq 4) { Add-Item ('SVC:' + $svc) 'SVC' ('Service ' + $svc + ' disabled') 'OK' '' 'auto' $null $null; continue }
        Add-Item ('SVC:' + $svc) 'SVC' ('Service ' + $svc + ' disabled') 'CHANGED' ('start type is ' + $start + ', expected 4') 'auto' 'svc' $svc
    }
}

function Get-StatusColor([string]$Status) {
    switch ($Status) {
        'OK'         { return 'Green' }
        'SKIPPED'    { return 'DarkGray' }
        'UNKNOWN'    { return 'DarkYellow' }
        'NOT CHOSEN' { return 'Cyan' }
        default      { return 'Yellow' }
    }
}

function Show-Items {
    foreach ($it in $script:Items) {
        $label = ('[' + $it.Status + ']').PadRight(13)
        $line = '  ' + $label + ' ' + $it.Id.PadRight(5) + ' ' + $it.Title
        Write-Log $line (Get-StatusColor $it.Status)
        if ($it.Detail -ne '' -and $it.Status -ne 'OK') { Write-Log ('                      ' + $it.Detail) 'DarkGray' }
    }
}

$script:Report = New-Object System.Collections.Generic.List[string]
function Write-Log([string]$Text, [string]$Color = 'Gray') {
    Write-Host $Text -ForegroundColor $Color
    $script:Report.Add($Text)
}

function Read-Answer([string]$Prompt, [string[]]$Allowed) {
    # If the input is closed or keeps being wrong, fall back to the safe answer N instead of looping forever.
    for ($try = 0; $try -lt 20; $try++) {
        $raw = Read-Host $Prompt
        if ($null -eq $raw) { break }
        $a = ([string]$raw).Trim().ToUpper()
        if ($Allowed -contains $a) { return $a }
        Write-Host ('   Please type one of: ' + ($Allowed -join ', ')) -ForegroundColor DarkYellow
    }
    return 'N'
}

function Invoke-Fix($Item, [string]$BackupDir) {
    $ok = $false
    try {
        switch ($Item.FixType) {
            'reg'  { $ok = [bool](Invoke-RegFix $Item.FixData $BackupDir) }
            'plan' { & powercfg.exe /setactive $Item.FixData *> $null; $ok = ($LASTEXITCODE -eq 0) }
            'pwr'  {
                & powercfg.exe /setacvalueindex SCHEME_CURRENT $Item.FixData.Args[0] $Item.FixData.Args[1] $Item.FixData.Want *> $null
                $ok = ($LASTEXITCODE -eq 0)
                & powercfg.exe /setactive SCHEME_CURRENT *> $null
            }
            'pref' { & reg.exe add $Item.FixData.Key /v EnablePrefetcher /t REG_DWORD /d $Item.FixData.Want /f *> $null; $ok = ($LASTEXITCODE -eq 0) }
            'tcp'  {
                $ok = $true
                foreach ($pth in $Item.FixData) {
                    & reg.exe add $pth /v TcpAckFrequency /t REG_DWORD /d 1 /f *> $null
                    if ($LASTEXITCODE -ne 0) { $ok = $false }
                    & reg.exe add $pth /v TCPNoDelay /t REG_DWORD /d 1 /f *> $null
                    if ($LASTEXITCODE -ne 0) { $ok = $false }
                }
            }
            'boost' {
                $helper = Join-Path $PSScriptRoot 'Power_Boost.ps1'
                if (Test-Path -LiteralPath $helper) {
                    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $helper -Action Apply *> $null
                    $ok = ($LASTEXITCODE -eq 0)
                }
            }
            'dns' {
                $helper = Join-Path $PSScriptRoot 'Set_Dns.ps1'
                if (Test-Path -LiteralPath $helper) {
                    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $helper -Action Apply -Servers ($Item.FixData -join ',') -Root $script:RootDir *> $null
                    $ok = ($LASTEXITCODE -eq 0)
                }
            }
            'svc'  { & sc.exe config $Item.FixData start= disabled *> $null; $ok = ($LASTEXITCODE -eq 0) }
        }
    } catch { $ok = $false }
    if ($ok) {
        if ($Item.Id -match '^\d{2}$') { Set-Choice $Item.Id 'Y' }
        if ($Item.Id -eq 'PLAN' -or $Item.Id -eq 'PWR') { Set-Choice 'POWER' 'Y' }
        if ($Item.Id -eq 'TCP') { Set-Choice 'TCP' 'Y' }
        Write-Log ('   [FIXED] ' + $Item.Id + ' ' + $Item.Title) 'Green'
    } else {
        Write-Log ('   [FAILED] ' + $Item.Id + ' ' + $Item.Title + ' - see the notes in the manual') 'Red'
    }
    return $ok
}

# ---------------------------------------------------------------- main
function Start-CheckStatus {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host '[ERROR] Please run this as administrator.' -ForegroundColor Red
        return 1
    }
    if ($Root -eq '') { $script:RootDir = Split-Path -Parent $PSScriptRoot } else { $script:RootDir = (Resolve-Path -LiteralPath $Root).Path }
    $regRoot = Join-Path $script:RootDir 'reg'
    if (-not (Test-Path -LiteralPath $regRoot)) {
        Write-Host ('[ERROR] The reg folder was not found in ' + $script:RootDir) -ForegroundColor Red
        return 1
    }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupDir = Join-Path $script:RootDir ('Backup\' + $stamp + '_check')
    $reportFile = Join-Path $script:RootDir ('CheckReport_' + $stamp + '.txt')

    Write-Log '==================================================================' 'Cyan'
    Write-Log '   PC OPTIMIZER v4.7 - CHECK STATUS' 'Cyan'
    Write-Log ('   ' + (Get-Date -Format 'yyyy-MM-dd HH:mm') + '   Windows build ' + [Environment]::OSVersion.Version.ToString()) 'Cyan'
    Write-Log '==================================================================' 'Cyan'
    Write-Log ''
    Write-Log '   Checking your PC, please wait a few seconds. No key press is needed...' 'DarkGray'
    Write-Log ''
    Invoke-Checks $regRoot $backupDir
    Show-Items

    $autoFix = @($script:Items | Where-Object { $_.Kind -eq 'auto' -and ($_.Status -eq 'CHANGED' -or $_.Status -eq 'MISSING') -and $null -ne $_.FixType })
    $askFix = @($script:Items | Where-Object { $_.Kind -eq 'ask' -and ($_.Status -eq 'CHANGED' -or $_.Status -eq 'MISSING' -or $_.Status -eq 'NOT CHOSEN') -and $null -ne $_.FixType })
    $okCount = @($script:Items | Where-Object { $_.Status -eq 'OK' }).Count
    Write-Log ''
    Write-Log ('   Summary: ' + $okCount + ' OK, ' + ($autoFix.Count + $askFix.Count) + ' need attention, ' + $script:Items.Count + ' checked') 'White'

    $fixed = New-Object System.Collections.Generic.List[object]
    if ($autoFix.Count -gt 0) {
        Write-Log ''
        $a = Read-Answer ('   Re-apply the ' + $autoFix.Count + ' changed recommended items? Y = all, S = choose one by one, N = no') @('Y', 'S', 'N')
        foreach ($it in $autoFix) {
            $go = ($a -eq 'Y')
            if ($a -eq 'S') { $go = ((Read-Answer ('     Fix ' + $it.Id + ' ' + $it.Title + '? Y/N') @('Y', 'N')) -eq 'Y') }
            if ($go -and (Invoke-Fix $it $backupDir)) { $fixed.Add($it) }
        }
    }
    foreach ($it in $askFix) {
        Write-Log ''
        if ($it.Id -eq '13') {
            Write-Log '   13 turns OFF Memory Integrity: can help FPS on some PCs, but lowers protection' 'Yellow'
            Write-Log '   against kernel-level malware. Needs a restart.' 'Yellow'
            $a = Read-Answer '   Apply 13? YES = apply, N = not now, X = do not ask again' @('YES', 'N', 'X')
        } else {
            $a = Read-Answer ('   Optional ' + $it.Id + ' ' + $it.Title + ' is ' + $it.Status + '. Y = apply, N = not now, X = do not ask again') @('Y', 'N', 'X')
        }
        if ($a -eq 'Y' -or $a -eq 'YES') { if (Invoke-Fix $it $backupDir) { $fixed.Add($it) } }
        if ($a -eq 'X') { Set-Choice $it.Id 'N'; Write-Log ('   ' + $it.Id + ' will be shown as SKIPPED from now on.') 'DarkGray' }
    }

    if ($fixed.Count -gt 0) {
        Write-Log ''
        Write-Log '   Verifying the fixed items...' 'Cyan'
        $ids = @($fixed | ForEach-Object { $_.Key })
        Invoke-Checks $regRoot $backupDir
        foreach ($it in @($script:Items | Where-Object { $ids -contains $_.Key })) {
            $label = ('[' + $it.Status + ']').PadRight(13)
            Write-Log ('  ' + $label + ' ' + $it.Id.PadRight(5) + ' ' + $it.Title) (Get-StatusColor $it.Status)
        }
        Write-Log ''
        Write-Log '   Restart the PC so every change takes full effect.' 'White'
        Write-Log ('   Previous values were saved in Backup\' + $stamp + '_check') 'DarkGray'
    } elseif ($autoFix.Count -eq 0 -and $askFix.Count -eq 0) {
        Write-Log ''
        Write-Log '   Everything is still in place. Nothing to do.' 'Green'
    }

    try { [IO.File]::WriteAllLines($reportFile, $script:Report) ; Write-Host ''; Write-Host ('   Report saved: ' + (Split-Path -Leaf $reportFile)) -ForegroundColor DarkGray } catch { }
    return 0
}

if ($MyInvocation.InvocationName -ne '.') {
    $code = @(Start-CheckStatus) | Select-Object -Last 1
    exit ([int]$code)
}
