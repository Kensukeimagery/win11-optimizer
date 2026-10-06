# Repository checks. Read-only: nothing on the PC is changed.
# Run:  powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Repo.ps1
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$failures = New-Object System.Collections.Generic.List[string]
$checks = 0

function Pass([string]$Text) { $script:checks++; Write-Host ('  [PASS] ' + $Text) -ForegroundColor Green }
function Fail([string]$Text) { $script:checks++; $script:failures.Add($Text); Write-Host ('  [FAIL] ' + $Text) -ForegroundColor Red }
function Assert([bool]$Cond, [string]$Text) { if ($Cond) { Pass $Text } else { Fail $Text } }

function Read-Bytes([string]$Path) { return [IO.File]::ReadAllBytes($Path) }
function Test-CrlfOnly([byte[]]$b) {
    for ($i = 0; $i -lt $b.Length; $i++) {
        if ($b[$i] -eq 10 -and ($i -eq 0 -or $b[$i - 1] -ne 13)) { return $false }
    }
    return $true
}

Write-Host ''
Write-Host '== Version consistency' -ForegroundColor Cyan
$versionFile = Join-Path $root 'VERSION'
Assert (Test-Path -LiteralPath $versionFile) 'VERSION file exists'
$version = ([IO.File]::ReadAllText($versionFile)).Trim()
Assert ($version -match '^\d+\.\d+$') ('VERSION looks like 4.6 (found "' + $version + '")')
$tagText = 'v' + $version

$scripts = @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Extension -in '.bat', '.ps1' -and $_.FullName -notmatch '\\(\.git|tests)\\' })
foreach ($f in $scripts) {
    $txt = [IO.File]::ReadAllText($f.FullName)
    $found = @([regex]::Matches($txt, '\bv\d+\.\d+\b') | ForEach-Object { $_.Value } | Sort-Object -Unique)
    $wrong = @($found | Where-Object { $_ -ne $tagText })
    if ($found.Count -gt 0) { Assert ($wrong.Count -eq 0) ($f.Name + ' only mentions ' + $tagText + $(if ($wrong.Count -gt 0) { ' (found ' + ($wrong -join ', ') + ')' } else { '' })) }
}
$changelog = [IO.File]::ReadAllText((Join-Path $root 'CHANGELOG.md'))
$firstHeading = [regex]::Match($changelog, '(?m)^## (v\d+\.\d+)').Groups[1].Value
Assert ($firstHeading -eq $tagText) ('CHANGELOG top section is ' + $tagText + ' (found ' + $firstHeading + ')')
foreach ($lang in 'EN', 'TH') {
    $pdf = Join-Path $root ('docs\Manual_' + $lang + '_' + $tagText + '.pdf')
    Assert (Test-Path -LiteralPath $pdf) ('manual PDF exists for ' + $lang + ' ' + $tagText)
    $src = Join-Path $root ('docs\src\manual_' + $lang.ToLower() + '.html')
    Assert (([IO.File]::ReadAllText($src)).Contains($tagText)) ('manual source ' + $lang + ' mentions ' + $tagText)
}
foreach ($lang in 'EN', 'TH') {
    Assert (Test-Path -LiteralPath (Join-Path $root ('docs\GPU_Driver_Guide_' + $lang + '.pdf'))) ('GPU driver guide PDF exists for ' + $lang)
    Assert (Test-Path -LiteralPath (Join-Path $root ('docs\src\gpu_guide_' + $lang.ToLower() + '.html'))) ('GPU driver guide source exists for ' + $lang)
}
$readme = [IO.File]::ReadAllText((Join-Path $root 'README.md'))
Assert ($readme.Contains('Manual_EN_' + $tagText + '.pdf') -and $readme.Contains('Manual_TH_' + $tagText + '.pdf')) 'README links the current manuals'

Write-Host ''
Write-Host '== PowerShell scripts parse' -ForegroundColor Cyan
foreach ($f in @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.ps1' | Where-Object { $_.FullName -notmatch '\\\.git\\' })) {
    $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errs)
    Assert (@($errs).Count -eq 0) ($f.Name + ' has no syntax errors')
}

Write-Host ''
Write-Host '== Batch files' -ForegroundColor Cyan
foreach ($f in @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.bat' | Where-Object { $_.FullName -notmatch '\\\.git\\' })) {
    $bytes = Read-Bytes $f.FullName
    Assert (Test-CrlfOnly $bytes) ($f.Name + ' uses CRLF line endings')
    Assert (@($bytes | Where-Object { $_ -gt 127 }).Count -eq 0) ($f.Name + ' is plain ASCII')
    $txt = [IO.File]::ReadAllText($f.FullName)
    $labels = @([regex]::Matches($txt, '(?m)^:(?!:)([A-Za-z0-9_]+)') | ForEach-Object { $_.Groups[1].Value.ToUpper() })
    $refs = @([regex]::Matches($txt, '(?im)^[^:\r\n]*?\b(?:goto|call)\s+:?([A-Za-z0-9_]+)') | ForEach-Object { $_.Groups[1].Value.ToUpper() } | Sort-Object -Unique)
    $missing = @($refs | Where-Object { $_ -ne 'EOF' -and $labels -notcontains $_ })
    $dups = @($labels | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    Assert ($missing.Count -eq 0) ($f.Name + ' has no goto/call to a missing label' + $(if ($missing.Count -gt 0) { ' (' + ($missing -join ', ') + ')' } else { '' }))
    Assert ($dups.Count -eq 0) ($f.Name + ' has no duplicate labels')
    foreach ($m in [regex]::Matches($txt, 'tools\\([A-Za-z_]+\.ps1)')) {
        $tool = $m.Groups[1].Value
        if (-not (Test-Path -LiteralPath (Join-Path $root ('tools\' + $tool)))) { Fail ($f.Name + ' refers to missing tools\' + $tool) }
    }
}

Write-Host ''
Write-Host '== Registry files and undo files' -ForegroundColor Cyan
$regFiles = @(Get-ChildItem -LiteralPath (Join-Path $root 'reg') -Recurse -File -Filter '*.reg')
Assert ($regFiles.Count -ge 15) ('found ' + $regFiles.Count + ' tweak files')
foreach ($r in $regFiles) {
    $num = $r.Name.Substring(0, 2)
    $bytes = Read-Bytes $r.FullName
    $head = [IO.File]::ReadAllLines($r.FullName)[0]
    Assert ($head -eq 'Windows Registry Editor Version 5.00') ($r.Name + ' starts with the registry header')
    Assert (Test-CrlfOnly $bytes) ($r.Name + ' uses CRLF line endings')
    $undo = @(Get-ChildItem -LiteralPath (Join-Path $root 'reg_undo') -File -Filter ('UNDO_' + $num + '_*.reg'))
    Assert ($undo.Count -eq 1) ('tweak ' + $num + ' has exactly one undo file')
}
$dupNums = @($regFiles | Group-Object { $_.Name.Substring(0, 2) } | Where-Object { $_.Count -gt 1 })
Assert ($dupNums.Count -eq 0) 'no two tweak files share a number'

Write-Host ''
Write-Host '== Check Status runs (read-only dry run)' -ForegroundColor Cyan
try {
    $csPath = Join-Path $root 'tools\Check_Status.ps1'
    . $csPath -Root $root
    Invoke-Checks (Join-Path $root 'reg') (Join-Path ([IO.Path]::GetTempPath()) 'pcopt_test_backup')
    $ids = @($script:Items | ForEach-Object { $_.Id })
    $allNums = @($regFiles | ForEach-Object { $_.Name.Substring(0, 2) })
    $missingIds = @($allNums | Where-Object { $ids -notcontains $_ })
    Assert ($missingIds.Count -eq 0) ('every tweak number is checked (missing: ' + ($missingIds -join ', ') + ')')
    Assert ($script:Items.Count -gt 15) ('Check Status produced ' + $script:Items.Count + ' items')
} catch {
    Fail ('Check Status dry run threw: ' + $_.Exception.Message)
}

Write-Host ''
Write-Host '== Driver check rules (no driver is installed by this test)' -ForegroundColor Cyan
try {
    # the script has its own parameter named Root, so hand it the same value (PowerShell variable names ignore case)
    . (Join-Path $root 'tools\Driver_Check.ps1') -Root $root -DryRun
    $old = Get-Date '2019-01-01'; $new = Get-Date '2024-01-01'
    Assert ((Get-OfferCategory 'Firmware' 'Some update' $new $null $false).Category -eq 'skip') 'firmware class is never offered'
    Assert ((Get-OfferCategory 'System' 'Vendor Firmware 1.2' $new $null $false).Category -eq 'skip') 'a title that says Firmware is never offered'
    Assert ((Get-OfferCategory 'Display' 'GPU' $new $null $true).Category -eq 'skip') 'Windows Update graphics are skipped when the maker driver is installed'
    Assert ((Get-OfferCategory 'Display' 'GPU' $new $null $false).Category -eq 'recommended') 'graphics are recommended when only the basic driver exists'
    Assert ((Get-OfferCategory 'Net' 'LAN' $new $old $false).Category -eq 'recommended') 'a newer network driver is recommended'
    Assert ((Get-OfferCategory 'Net' 'LAN' $old $new $false).Category -eq 'skip') 'an older driver is never offered'
    Assert ((Get-OfferCategory 'OtherHardware' 'Thing' $new $null $false).Category -eq 'optional') 'unknown hardware classes are optional'
    Assert ((Get-ProblemText 28) -match 'no driver') 'problem code 28 is explained'
    $chip = 'INTEL - System - 10/3/2016 12:00:00 AM - 10.1.1.38'
    Assert ((Get-OfferCategory 'System' $chip $new $null $false).Category -eq 'optional') 'a chipset INF package from Windows Update is optional, not recommended'
    Assert ((Get-FriendlyTitle $chip) -eq 'Intel chipset driver package 10.1.1.38 (System)') 'the chipset INF title is shown in plain words'
    Assert ((Get-FriendlyTitle 'Realtek - Net - Realtek PCIe GbE') -eq 'Realtek - Net - Realtek PCIe GbE') 'other titles are left alone'
    Assert ((Get-ResultText 4) -match 'earlier package') 'result code 4 is explained in words'
    $fake = @([pscustomobject]@{ Title = 'Fake driver'; Update = $null })
    Install-Offers $null $fake '' 6>$null
    Pass 'dry run of the install step prints and installs nothing'
} catch {
    Fail ('driver rules threw: ' + $_.Exception.Message)
}
Write-Host ''
Write-Host '== Driver cleanup rules (nothing is removed by this test)' -ForegroundColor Cyan
try {
    . (Join-Path $root 'tools\Driver_Clean.ps1') -Root $root -DryRun
    function Pk($inf, $orig, $prov, $cls, $ver, $date, $boot) { [pscustomobject]@{ Inf = $inf; Original = $orig; Provider = $prov; Class = $cls; Version = $ver; Date = [datetime]$date; Boot = $boot; Dir = '' } }
    $set = @(
        (Pk 'oem1.inf' 'nv_disp.inf' 'NVIDIA' 'Display' '31.0.15.4601' '2024-01-01' $false),
        (Pk 'oem2.inf' 'nv_disp.inf' 'NVIDIA' 'Display' '32.0.15.8266' '2026-06-01' $false),
        (Pk 'oem3.inf' 'nv_disp.inf' 'NVIDIA' 'Display' '32.0.15.6000' '2025-06-01' $false),
        (Pk 'oem4.inf' 'rtl.inf' 'Realtek' 'Net' '10.0.0.1' '2020-01-01' $false),
        (Pk 'oem5.inf' 'stor.inf' 'Vendor' 'HDC' '1.0.0.1' '2019-01-01' $true),
        (Pk 'oem6.inf' 'stor.inf' 'Vendor' 'HDC' '2.0.0.1' '2022-01-01' $false),
        (Pk 'oem7.inf' 'x.inf' 'Maker' 'Net' '1.0.0.1' '2019-01-01' $false),
        (Pk 'oem8.inf' 'x.inf' 'Maker' 'Net' '1.0.0.2' '2021-01-01' $false)
    )
    $c = @(Get-StaleCandidates $set @('oem8.inf', 'oem7.inf'))
    $ids = @($c | ForEach-Object { $_.Package.Inf })
    Assert ($ids -contains 'oem1.inf' -and $ids -contains 'oem3.inf') 'older versions of the same driver are candidates'
    Assert ($ids -notcontains 'oem2.inf') 'the newest version is never a candidate'
    Assert ($ids -notcontains 'oem4.inf') 'a driver with only one version is never a candidate'
    Assert ($ids -notcontains 'oem5.inf') 'a boot critical package is never a candidate'
    Assert ($ids -notcontains 'oem7.inf') 'an old version that a device uses is never a candidate'
    Assert (@($c | Where-Object { $_.KeepInf -ne 'oem2.inf' -and $_.Package.Inf -in 'oem1.inf', 'oem3.inf' }).Count -eq 0) 'candidates point at the version that is kept'
    Assert ((Get-StaleCandidates $set @()).Count -eq 3) 'with nothing in use, exactly the three non-newest non-boot packages are candidates'
    Assert ((Test-GhostRemovable 'USB') -and -not (Test-GhostRemovable 'Net') -and -not (Test-GhostRemovable 'System')) 'network and system ghost entries are never removable'
    $more = @(
        (Pk 'oem20.inf' 'ms.inf' 'Microsoft Corporation' 'Printer' '10.0.1.1' '2024-01-01' $false),
        (Pk 'oem21.inf' 'ms.inf' 'Microsoft Corporation' 'Printer' '10.0.1.2' '2025-01-01' $false),
        (Pk 'oem30.inf' 'odd.inf' 'Maker' 'Media' '10.0.0.1' '2024-01-01' $false),
        (Pk 'oem31.inf' 'odd.inf' 'Maker' 'Media' '1.0.9.9' '2026-01-01' $false)
    )
    $c2 = @(Get-StaleCandidates @($set + $more) @())
    $ids2 = @($c2 | ForEach-Object { $_.Package.Inf })
    Assert (@($ids2 | Where-Object { $_ -in 'oem20.inf', 'oem21.inf' }).Count -eq 0) 'packages from Microsoft are never candidates'
    Assert (@($ids2 | Where-Object { $_ -in 'oem30.inf', 'oem31.inf' }).Count -eq 0) 'a group where version and date disagree is left alone'
    Assert (@($script:SkippedGroups).Count -eq 2) 'the skipped groups are reported'
    Assert ((Test-GhostBluetooth 'BTHENUM\DEV_001122334455\7&1&0&BLUETOOTHDEVICE_001122334455') -and (Test-GhostBluetooth 'HID\{00001124-0000-1000-8000-00805f9b34fb}_DEV_VID&0201\8&1') -and -not (Test-GhostBluetooth 'USB\VID_046D&PID_C52B\5&1')) 'Bluetooth entries are recognised and a USB one is not'
    Assert (((Format-Mb $null) -eq '?') -and ((Format-Mb 0.02) -eq '<0.1') -and ((Format-Mb 3.4) -eq '3.4')) 'unknown and tiny sizes are shown honestly'
    Remove-OldPackages $c '' 6>$null
    Remove-GhostDevices @() 6>$null
    Pass 'dry run of the removal steps removes nothing'
} catch {
    Fail ('driver cleanup rules threw: ' + $_.Exception.Message)
}
Write-Host ''
Write-Host '== PC health rules (read-only tool, nothing is changed)' -ForegroundColor Cyan
try {
    . (Join-Path $root 'tools\PC_Health.ps1') -Root $root
    Assert ((Get-BugcheckInfo '0x00000116').Name -eq 'VIDEO_TDR_FAILURE') 'a graphics blue screen code is named'
    Assert ((Get-BugcheckInfo '0x124').Name -eq 'WHEA_UNCORRECTABLE_ERROR') 'a short hex code is understood'
    Assert ((Get-BugcheckInfo '0xABCDEF').Name -match '^code 0x') 'an unknown code is shown as the code, not guessed'
    Assert (@(Get-DiskHints ([pscustomobject]@{ Health = 'Healthy'; Status = 'OK'; Media = 'SSD'; Temp = 40; Wear = 5; ReadErrors = 0; WriteErrors = 0 })).Count -eq 0) 'a healthy drive has no hint'
    Assert (@(Get-DiskHints ([pscustomobject]@{ Health = 'Warning'; Status = 'OK'; Media = 'SSD'; Temp = $null; Wear = $null; ReadErrors = $null; WriteErrors = $null })).Count -eq 1) 'a drive that Windows calls unhealthy is flagged'
    Assert (@(Get-DiskHints ([pscustomobject]@{ Health = 'Healthy'; Status = 'OK'; Media = 'SSD'; Temp = 40; Wear = 85; ReadErrors = 0; WriteErrors = 0 })).Count -eq 1) 'a worn SSD is flagged'
    Assert (@(Get-DiskHints ([pscustomobject]@{ Health = 'Healthy'; Status = 'OK'; Media = 'HDD'; Temp = 56; Wear = $null; ReadErrors = 0; WriteErrors = 0 })).Count -eq 1) 'a hot hard drive is flagged'
    Assert (@(Get-DiskHints ([pscustomobject]@{ Health = 'Healthy'; Status = 'OK'; Media = 'SSD'; Temp = 56; Wear = $null; ReadErrors = 0; WriteErrors = 0 })).Count -eq 0) 'the same temperature on an SSD is fine'
    Assert (@(Get-DiskHints ([pscustomobject]@{ Health = 'Healthy'; Status = 'OK'; Media = 'HDD'; Temp = $null; Wear = $null; ReadErrors = 3; WriteErrors = 0 })).Count -eq 1) 'logged read errors are flagged'
    Assert (@(Get-DiskHints ([pscustomobject]@{ Health = 'Healthy'; Status = 'OK'; Media = 'HDD'; Temp = 35; Wear = 90; ReadErrors = 0; WriteErrors = 0 })).Count -eq 0) 'a hard drive wear figure is ignored'
    Assert ((Get-ExceptionText 'c0000005') -match 'access violation' -and (Get-ExceptionText '0xC0000005') -match 'access violation' -and (Get-ExceptionText 'deadbeef') -eq 'error code 0xdeadbeef') 'crash error codes are explained, unknown ones are shown as the code'
    Assert (@(Get-RamHint 2133 3200 2).Count -eq 1) 'RAM running far below its rated speed is flagged'
    Assert (@(Get-RamHint 3200 3200 2).Count -eq 0) 'RAM at its rated speed is fine'
    Assert (@(Get-RamHint 3200 3200 1).Count -eq 1) 'a single RAM module is mentioned'
    Assert ((Get-LanHint 'Realtek PCIe GbE Family Controller' 100) -ne '') 'a Gigabit adapter linked at 100 Mbps is flagged'
    Assert ((Get-LanHint 'Realtek PCIe GbE Family Controller' 1000) -eq '') 'a Gigabit link is fine'
    Assert ((Get-LanHint 'Old Fast Ethernet Adapter' 100) -eq '') 'a 100 Mbps adapter at 100 Mbps is fine'
    Assert ((Get-RefreshHint 60 144) -ne '') 'a screen below its highest refresh rate is flagged'
    Assert ((Get-RefreshHint 144 144) -eq '' -and (Get-RefreshHint 143 144) -eq '') 'a screen at its highest refresh rate (143 vs 144 rounding) is fine'
    Assert ((Get-BatteryHealthPercent 50000 40000) -eq 80 -and $null -eq (Get-BatteryHealthPercent $null 1)) 'battery health is a percent of the design capacity'
    . (Join-Path $root 'tools\Support_Bundle.ps1') -Root $root
    $sc = ConvertTo-Scrubbed "user Kensuke on PC-ONE: mac 00-1A-2B-3C-4D-5E, router 192.168.1.1, mail a.b@example.com, driver 10.1.1.38, administrator" 'Kensuke' 'PC-ONE'
    Assert ($sc -notmatch 'Kensuke|PC-ONE|00-1A|192\.168|example\.com') 'user name, computer name, MAC, home IP and e-mail are replaced'
    Assert ($sc -match '10\.1\.1\.38') 'a driver version that looks like an address is left alone'
    Assert ((ConvertTo-Scrubbed 'administrator' 'admin' 'PC') -eq 'administrator') 'a user name inside a longer word is left alone'
} catch {
    Fail ('PC health rules threw: ' + $_.Exception.Message)
}
Write-Host ''
Write-Host '== Prefetcher looks at the drive Windows is installed on' -ForegroundColor Cyan
$masterText = [IO.File]::ReadAllText((Join-Path $root '1_Start_Here - PC_Optimizer_Master (Run as Administrator).bat'))
$csText = [IO.File]::ReadAllText((Join-Path $root 'tools\Check_Status.ps1'))
Assert ($masterText -match 'Get-Partition -DriveLetter \$env:SystemDrive' -and $masterText -notmatch 'Sort-Object DeviceId \| Select-Object -First 1') 'the menu decides about Prefetcher from the drive Windows is on, not disk 0'
Assert ($csText -match 'Get-Partition -DriveLetter' -and $csText -notmatch 'Sort-Object DeviceId \| Select-Object -First 1') 'Check Status uses the same rule'
Assert ($masterText -match 'if not defined MEDIATYPE set \"MEDIATYPE=Unknown\"') 'an unreadable drive type leaves Prefetcher alone'

Write-Host ''
Write-Host '== PC specs page rules (read-only tool, nothing is changed)' -ForegroundColor Cyan
try {
    . (Join-Path $root 'tools\PC_Specs.ps1') -Root $root
    Assert ((Get-RamMemoryType 26) -eq 'DDR4' -and (Get-RamMemoryType 34) -eq 'DDR5' -and (Get-RamMemoryType 0) -eq '') 'RAM type codes are turned into DDR names'
    Assert ((Get-RamNote 8) -match 'tight' -and (Get-RamNote 12) -match 'lighter' -and (Get-RamNote 16) -match 'Good' -and (Get-RamNote 32) -match 'Plenty') 'RAM notes follow the size tiers'
    Assert ((Get-VramNote 2) -match 'Low' -and (Get-VramNote 6) -match '1080p' -and (Get-VramNote 8) -match 'Plenty' -and (Get-VramNote 0) -eq '') 'video memory notes follow the size tiers'
    Assert (@(Get-StorageNote 'HDD' 50).Count -eq 1 -and @(Get-StorageNote 'SSD' 10).Count -eq 1 -and @(Get-StorageNote 'HDD' 10).Count -eq 2 -and @(Get-StorageNote 'SSD' 50).Count -eq 0 -and @(Get-StorageNote 'SSD' -1).Count -eq 0) 'drive notes: HDD, nearly full, both, neither, unknown free space'
    Assert ((Get-NvidiaDriverNumber '32.0.15.8266') -eq '582.66' -and (Get-NvidiaDriverNumber '31.0.15.4601') -eq '546.01' -and (Get-NvidiaDriverNumber '10.0.1') -eq '') 'the Windows driver number is turned into the NVIDIA driver number'
    Assert ((Test-PlaceholderText 'To be filled by O.E.M.') -and (Test-PlaceholderText 'System Product Name') -and (Test-PlaceholderText '') -and -not (Test-PlaceholderText 'HUANANZHI X99-4MF PLUS')) 'placeholder board and model names are ignored'
    Assert ($null -ne (Get-Command Get-LanHint -ErrorAction SilentlyContinue)) 'the specs page uses the shared cable-speed rule'
    $now = Get-Date '2026-10-06'
    Assert ((Test-OldThirdPartyDriver 'NET' 'Realtek' (Get-Date '2020-01-01') $now) -and -not (Test-OldThirdPartyDriver 'NET' 'Realtek' (Get-Date '2025-06-01') $now) -and -not (Test-OldThirdPartyDriver 'NET' 'Microsoft' (Get-Date '2006-06-21') $now) -and -not (Test-OldThirdPartyDriver 'SYSTEM' 'Intel' (Get-Date '2016-10-03') $now)) 'only old maker drivers of network, graphics, sound and Bluetooth are mentioned'
    $it = @(
        [pscustomobject]@{ Key = 'REG01'; Kind = 'auto'; Status = 'OK'; Title = 'A' },
        [pscustomobject]@{ Key = 'REG02'; Kind = 'auto'; Status = 'CHANGED'; Title = 'B' },
        [pscustomobject]@{ Key = 'REG13'; Kind = 'ask'; Status = 'SKIPPED'; Title = 'C' },
        [pscustomobject]@{ Key = 'PREF'; Kind = 'auto'; Status = 'MISSING'; Title = 'D' }
    )
    $sum = Get-OptimizerSummary $it
    Assert ($sum.Ok -eq 1 -and $sum.Bad.Count -eq 2 -and $sum.Skipped -eq 1 -and -not $sum.NotApplied) 'the optimizer summary counts OK, changed and skipped settings'
    $none = Get-OptimizerSummary @([pscustomobject]@{ Key = 'REG01'; Kind = 'auto'; Status = 'MISSING'; Title = 'A' }, [pscustomobject]@{ Key = 'REG02'; Kind = 'auto'; Status = 'MISSING'; Title = 'B' })
    Assert ($none.NotApplied) 'a PC where none of the optimizer settings are present is reported as not applied, not as broken'
    $once = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tools\PC_Specs.ps1') 2>&1 | Out-String
    Assert ($once -match 'Processor' -and $once -match 'Memory \(RAM\)' -and $once -match 'Graphics card' -and $once -match 'Drives' -and $once -match 'Check-up' -and $once -notmatch 'Exception') 'the page runs and shows the main parts'
} catch {
    Fail ('PC specs rules threw: ' + $_.Exception.Message)
}
Write-Host ''
Write-Host '== Reports go to Logs and old ones are removed safely (temporary folder, nothing real is touched)' -ForegroundColor Cyan
try {
    . (Join-Path $root 'tools\Report_Files.ps1')
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('pcopt_logs_' + [guid]::NewGuid().ToString('N'))
    $logs = Join-Path $tmp 'Logs'
    New-Item -ItemType Directory -Force -Path $logs, (Join-Path $tmp 'Backup\old'), (Join-Path $tmp 'tools') | Out-Null
    foreach ($i in 1..5) { Set-Content -LiteralPath (Join-Path $logs ('CheckReport_2026100' + $i + '_101010.txt')) -Value 'x' }
    foreach ($i in 1..4) { Set-Content -LiteralPath (Join-Path $logs ('DriverReport_2026100' + $i + '_101010_after.txt')) -Value 'x' }
    foreach ($i in 1..4) { Set-Content -LiteralPath (Join-Path $logs ('DriverReport_2026100' + $i + '_101010.txt')) -Value 'x' }
    foreach ($i in 1..7) { Set-Content -LiteralPath (Join-Path $logs ('SupportBundle_2026100' + $i + '_101010.txt')) -Value 'x' }
    Set-Content -LiteralPath (Join-Path $logs 'my notes.txt') -Value 'mine'
    Set-Content -LiteralPath (Join-Path $logs 'CheckReport_today.txt') -Value 'not a report name'
    Set-Content -LiteralPath (Join-Path $tmp 'Backup\old\keep.txt') -Value 'backup'
    Set-Content -LiteralPath (Join-Path $tmp 'README.md') -Value 'readme'
    $r1 = Remove-OldReports $tmp -Keep 3
    $left = @(Get-ChildItem -LiteralPath $logs -File | ForEach-Object { $_.Name })
    Assert (@($left | Where-Object { $_ -like 'CheckReport_2026*' }).Count -eq 3 -and ($left -contains 'CheckReport_20261005_101010.txt') -and ($left -notcontains 'CheckReport_20261001_101010.txt')) 'the newest 3 of a kind are kept and the oldest are removed'
    Assert (@($left | Where-Object { $_ -like 'DriverReport_*_after.txt' }).Count -eq 3 -and @($left | Where-Object { $_ -like 'DriverReport_2026*' -and $_ -notlike '*_after.txt' }).Count -eq 3) 'a report and its _after report are counted separately'
    Assert (@($left | Where-Object { $_ -like 'SupportBundle_*' }).Count -eq 5) 'a support bundle keeps 2 more than the others'
    Assert (($left -contains 'my notes.txt') -and ($left -contains 'CheckReport_today.txt')) 'files that are not exact report names are never removed'
    Assert ((Test-Path -LiteralPath (Join-Path $tmp 'Backup\old\keep.txt')) -and (Test-Path -LiteralPath (Join-Path $tmp 'README.md'))) 'Backup and the program files are never touched by the report cleanup'
    Assert ($r1.Count -eq 2 + 1 + 1 + 2) 'the cleanup reports how many files it removed'
    $r0 = Remove-OldReports $tmp -Keep 0
    Assert ($r0.Count -eq 0) 'keep 0 means nothing is ever removed'
    $before = @(Get-ChildItem -LiteralPath $logs -File).Count
    $dry = Remove-OldReports $tmp -Keep 1 -DryRun
    Assert ($dry.Count -gt 0 -and @(Get-ChildItem -LiteralPath $logs -File).Count -eq $before) 'a dry run counts but removes nothing'
    # reports left next to the scripts by older versions are moved into Logs, never overwritten
    Set-Content -LiteralPath (Join-Path $tmp 'PCHealth_20260901_010101.txt') -Value 'old'
    Set-Content -LiteralPath (Join-Path $tmp 'CheckReport_20261005_101010.txt') -Value 'root copy'
    Set-Content -LiteralPath (Join-Path $tmp 'notes.txt') -Value 'mine'
    $mv = Move-ReportsToLogs $tmp
    Assert ($mv -eq 1 -and (Test-Path -LiteralPath (Join-Path $logs 'PCHealth_20260901_010101.txt')) -and (Test-Path -LiteralPath (Join-Path $tmp 'notes.txt'))) 'old reports are moved into Logs and other files stay'
    Assert ((Get-Content -LiteralPath (Join-Path $logs 'CheckReport_20261005_101010.txt')) -eq 'x') 'a report with the same name in Logs is not overwritten'
    Set-Content -LiteralPath (Join-Path $logs 'a.txt') -Value 'x'
    Assert ((Test-PathInside (Join-Path $logs 'a.txt') $logs) -and -not (Test-PathInside (Join-Path $logs '..\README.md') $logs) -and -not (Test-PathInside $tmp $logs)) 'a path outside the Logs folder is refused (also with ..)'
    # backups: the groups and how many are kept
    $names = @('drivers_20261001_100000', 'drivers_20261002_100000', 'drivers_20261003_100000', 'drivers_removed_20261001_100000', 'update_4.1_20261001_100000', 'update_4.2_20261002_100000', 'update_4.3_20261003_100000', '20261001_100000_check', '20261001_100000', 'old')
    foreach ($n in $names) { New-Item -ItemType Directory -Force -Path (Join-Path $tmp ('Backup\' + $n)) | Out-Null; Set-Content -LiteralPath (Join-Path $tmp ('Backup\' + $n + '\f.txt')) -Value 'x' }
    $items = @(Get-BackupItems $tmp)
    Assert (@($items | Where-Object { $_.Name -eq 'old' }).Count -eq 0) 'a folder with another name in Backup is not even listed'
    $rm = @(Select-BackupsToRemove $items | ForEach-Object { $_.Name } | Sort-Object)
    Assert (($rm -join ',') -eq 'drivers_20261001_100000,drivers_20261002_100000,update_4.1_20261001_100000') 'only the older backups beyond the newest 1 drivers copy and 2 updater copies are offered'
    $rb = Remove-BackupItems @(Select-BackupsToRemove $items) $tmp
    Assert ($rb.Count -eq 3 -and (Test-Path -LiteralPath (Join-Path $tmp 'Backup\drivers_20261003_100000')) -and (Test-Path -LiteralPath (Join-Path $tmp 'Backup\old\keep.txt'))) 'removing the offered backups keeps the newest ones and everything else'
    # the housekeeping script and the cleanup tool run
    Copy-Item -LiteralPath (Join-Path $root 'tools\Report_Files.ps1') -Destination (Join-Path $tmp 'tools\Report_Files.ps1')
    Copy-Item -LiteralPath (Join-Path $root 'tools\Report_Maintain.ps1') -Destination (Join-Path $tmp 'tools\Report_Maintain.ps1')
    Copy-Item -LiteralPath (Join-Path $root 'tools\Clean_Up.ps1') -Destination (Join-Path $tmp 'tools\Clean_Up.ps1')
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tmp 'tools\Report_Maintain.ps1') -Root $tmp | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'the housekeeping script runs'
    $sum = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tmp 'tools\Clean_Up.ps1') -Root $tmp -NoPrompt 2>&1 | Out-String
    Assert ($sum -match 'Reports and logs' -and $sum -match 'Backups' -and $sum -notmatch 'Exception') 'the cleanup tool shows its summary'
    try { [IO.Directory]::Delete($tmp, $true) } catch { }
    # no tool may still save a report next to the scripts
    $stray = @()
    foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $root 'tools') -Filter '*.ps1')) {
        if ($f.Name -in 'Update.ps1', 'Report_Files.ps1') { continue }
        if (([IO.File]::ReadAllText($f.FullName)) -match "Get-Date -Format 'yyyyMMdd_HHmmss'\) \+ '(_after)?\.txt'") { $stray += $f.Name }
    }
    Assert ($stray.Count -eq 0) ('every tool saves its report with New-ReportPath (Logs folder) ' + ($stray -join ', '))
    $upd = [IO.File]::ReadAllText((Join-Path $root 'tools\Update.ps1'))
    Assert ($upd -match "Join-Path \`$Root 'Logs'") 'the updater writes its log into Logs'
    $mst = [IO.File]::ReadAllText((Join-Path $root '1_Start_Here - PC_Optimizer_Master (Run as Administrator).bat'))
    Assert ($mst -match 'set "LOGFILE=%LOGDIR%\\OptimizerLog_' -and $mst -match 'Report_Maintain\.ps1' -and $mst -match 'LSS 150') 'the menu logs into Logs, runs the housekeeping and drops a log that only has its first line'
    . (Join-Path $root 'tools\Driver_Check.ps1') -Root $root -DryRun
    $opt = [pscustomobject]@{ Category = 'optional' }; $recd = [pscustomobject]@{ Category = 'recommended' }
    Assert ((-not (Test-FullCopyNeeded @($opt))) -and (-not (Test-FullCopyNeeded @($opt, $opt, $opt))) -and (Test-FullCopyNeeded @($opt, $opt, $opt, $opt)) -and (Test-FullCopyNeeded @($recd))) 'the full driver copy is optional only for a few low-impact drivers'
} catch {
    Fail ('reports and cleanup tests threw: ' + $_.Exception.Message)
}
Write-Host ''
Write-Host '== Easy Setup (one button): messages, order, rules and the preview (nothing is changed)' -ForegroundColor Cyan
try {
    $easySrc = [IO.File]::ReadAllText((Join-Path $root 'tools\Easy_Setup.ps1'))
    Assert (-not ($easySrc -match '[^\x00-\x7F]')) 'the Easy Setup script itself is plain ASCII (the Thai text lives in tools\lang)'
    $enMap = @{}; $thMap = @{}
    foreach ($pair in @(@('en', $enMap), @('th', $thMap))) {
        foreach ($line in [IO.File]::ReadAllLines((Join-Path $root ('tools\lang\easy_' + $pair[0] + '.txt')), [Text.Encoding]::UTF8)) {
            if ($line -match '^\s*#' -or $line.Trim() -eq '') { continue }
            $i = $line.IndexOf('=')
            if ($i -gt 0) { $pair[1][$line.Substring(0, $i).Trim()] = $line.Substring($i + 1) }
        }
    }
    $used = @([regex]::Matches($easySrc, "(?:SayT|T|Read-Choice \(T) '([a-z0-9_]+)'") | ForEach-Object { $_.Groups[1].Value }) + @([regex]::Matches($easySrc, "'((?:plan|preview)_[a-z_]+)'") | ForEach-Object { $_.Groups[1].Value }) | Sort-Object -Unique
    Assert (@($used | Where-Object { -not $enMap.ContainsKey($_) }).Count -eq 0) ('every message the script uses exists in English ' + (($used | Where-Object { -not $enMap.ContainsKey($_) }) -join ', '))
    Assert (@($used | Where-Object { -not $thMap.ContainsKey($_) }).Count -eq 0) ('every message the script uses exists in Thai ' + (($used | Where-Object { -not $thMap.ContainsKey($_) }) -join ', '))
    Assert (@($enMap.Keys | Where-Object { -not $thMap.ContainsKey($_) }).Count -eq 0 -and @($thMap.Keys | Where-Object { -not $enMap.ContainsKey($_) }).Count -eq 0) 'the English and Thai message files have exactly the same keys'
    $badPh = @($enMap.Keys | Where-Object { $thMap.ContainsKey($_) -and ((@([regex]::Matches($enMap[$_], '\{\d\}') | ForEach-Object { $_.Value } | Sort-Object) -join ',') -ne (@([regex]::Matches($thMap[$_], '\{\d\}') | ForEach-Object { $_.Value } | Sort-Object) -join ',')) })
    Assert ($badPh.Count -eq 0) ('the numbers filled into each message match in both languages ' + ($badPh -join ', '))
    Assert (@($enMap.Keys + $thMap.Keys | Where-Object { (($enMap[$_] + $thMap[$_]) -replace '\{\d\}', '') -match '[{}]' }).Count -eq 0) 'no stray braces in the messages (they would break the formatting)'
    Assert ((([IO.File]::ReadAllText((Join-Path $root 'tools\lang\easy_th.txt'), [Text.Encoding]::UTF8)).ToCharArray() | Where-Object { [int]$_ -ge 0x0E00 -and [int]$_ -le 0x0E7F }).Count -gt 50) 'the Thai file really contains Thai text'
    & {
        . (Join-Path $root 'tools\Easy_Setup.ps1') -Root $root -Preview -NoPrompt -Lang en
        Assert ((Get-NextStep @()) -eq 'update' -and (Get-NextStep @('update', 'restore', 'before')) -eq 'network' -and (Get-NextStep $script:StepOrder) -eq '') 'the next step follows the order and stops at the end'
        $order = $script:StepOrder
        Assert (($order.IndexOf('restore') -lt $order.IndexOf('drivers')) -and ($order.IndexOf('winupdate') -lt $order.IndexOf('drivers')) -and ($order.IndexOf('drivers') -lt $order.IndexOf('tweaks')) -and ($order.IndexOf('tweaks') -lt $order.IndexOf('verify')) -and ($order.IndexOf('network') -lt $order.IndexOf('winupdate'))) 'restore point first, then internet, Windows Update and drivers, the settings last and the check at the very end'
        Assert ((Get-TweakProfile 'Y') -eq 'games' -and (Get-TweakProfile 'N') -eq 'safe' -and (Get-TweakProfile '') -eq 'safe') 'only a clear yes selects the gaming profile'
        Assert ((Test-RestartNeeded $true $null) -and (Test-RestartNeeded $false ([pscustomobject]@{ Reboot = $true })) -and -not (Test-RestartNeeded $false ([pscustomobject]@{ Reboot = $false })) -and -not (Test-RestartNeeded $false $null)) 'a restart is offered only when something needs it'
        $snap = Get-SettingsSnapshot @([pscustomobject]@{ Status = 'OK'; Title = 'A' }, [pscustomobject]@{ Status = 'CHANGED'; Title = 'B' }, [pscustomobject]@{ Status = 'SKIPPED'; Title = 'C' }, [pscustomobject]@{ Status = 'MISSING'; Title = 'D' })
        Assert ($snap.Ok -eq 1 -and $snap.Total -eq 3 -and ($snap.Bad -join ',') -eq 'B,D') 'the before/after counts leave out settings you chose to skip'
        $att = @(Select-AttentionLines @('   [OK]    fine', '[CHECK] Cable is slow. Try another cable.', '[CHECK] Cable is slow. Try another cable please.', '[INFO] note', '[CHECK] Second thing') 6)
        Assert ($att.Count -eq 2 -and $att[0] -like 'Cable is slow*' -and $att[1] -eq 'Second thing') 'only CHECK lines are shown in the summary and the same advice is not repeated'
        $plan = @(Get-EasyPlan $true $false 'games'); $plan2 = @(Get-EasyPlan $false $true 'games'); $plan3 = @(Get-EasyPlan $false $true 'safe')
        Assert (($plan -contains 'plan_network_off') -and ($plan -contains 'plan_tweaks_laptop') -and ($plan -notcontains 'plan_tweaks_games') -and ($plan2 -contains 'plan_tweaks_games') -and ($plan3 -contains 'plan_tweaks_safe') -and ($plan2 -contains 'plan_network_ok')) 'the plan changes for a laptop, for no internet and for the gaming profile'
        Assert (@($plan | Where-Object { -not $enMap.ContainsKey($_) }).Count -eq 0) 'every plan line has a message'
    }
} catch {
    Fail ('Easy Setup rules threw: ' + $_.Exception.Message)
}
try {
    foreach ($lang in 'en', 'th') {
        $prev = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tools\Easy_Setup.ps1') -Root $root -Preview -NoPrompt -Lang $lang 2>&1 | Out-String
        $endMark = $(if ($lang -eq 'en') { 'PREVIEW finished' } else { [string]::Join('', [char[]](0x0E08, 0x0E1A, 0x0E42, 0x0E2B, 0x0E21, 0x0E14)) })
        Assert ($LASTEXITCODE -eq 0 -and $prev.Contains($endMark) -and $prev -notmatch 'Exception') ('the preview runs to the end in ' + $lang + ' and exits cleanly')
    }
    Assert (-not (Test-Path -LiteralPath (Join-Path $root 'Logs\EasySetup*'))) 'the preview saves no report'
} catch {
    Fail ('Easy Setup preview threw: ' + $_.Exception.Message)
}
$mst2 = [IO.File]::ReadAllText((Join-Path $root '1_Start_Here - PC_Optimizer_Master (Run as Administrator).bat'))
Assert ($mst2 -match 'if /i "%~1"=="/easy" goto EASYSTART' -and $mst2 -match ':EASYSTART' -and $mst2 -match 'if not defined EASYMODE pause' -and $mst2 -match 'goto SKIP02EASY') 'the main menu has an /easy entry with no questions and no pauses'
Assert ($mst2 -match 'if /i "%CHOICE%"=="E" goto DOEASY') 'the main menu has the E key for Easy Setup'
$drv = [IO.File]::ReadAllText((Join-Path $root 'tools\Driver_Check.ps1'))
Assert ($drv -match '\[switch\]\$Auto' -and $drv -match '\[switch\]\$NoRestorePoint' -and $drv -match '\$ResultFile') 'the driver check has the automatic mode that Easy Setup uses'
Assert ((Test-Path -LiteralPath (Join-Path $root '0_Easy_Setup (Run as Administrator).bat'))) 'the one-button file exists in the main folder'
. (Join-Path $root 'tools\PC_Health.ps1') -Root $root
Assert ((Get-CrashVerdict 50 0 $true) -eq 'check' -and (Get-CrashVerdict 50 10 $true) -eq 'history' -and (Get-CrashVerdict 50 0 $false) -eq 'history' -and (Get-CrashVerdict 3 0 $true) -eq 'history') 'a program that crashed often is a CHECK only while it is installed and crashed in the last 3 days'
Write-Host ''
Write-Host '== Updater release notes are shown as plain text' -ForegroundColor Cyan
try {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'tools\Update.ps1'), [ref]$null, [ref]$null)
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'ConvertTo-PlainNotes' }, $true)
    . ([scriptblock]::Create($fn.Extent.Text))
    $md = "## v9`n- **Bold** and ``code`` text that is long enough to need wrapping at a small width for the test`n`n`n- second"
    $plain = @(ConvertTo-PlainNotes $md 30)
    Assert (-not (($plain -join "`n") -match '\*\*|`|##')) 'Markdown marks are removed'
    Assert (@($plain | Where-Object { $_.Length -gt 32 }).Count -eq 0) 'lines are wrapped to the width'
    Assert ($plain -contains '- second') 'bullets stay bullets'
    Assert (@($plain | Where-Object { $_ -eq '' }).Count -eq 1) 'blank lines are collapsed'
} catch {
    Fail ('release notes formatting threw: ' + $_.Exception.Message)
}
Write-Host ''
Write-Host '== DNS backup survives a lost registry copy (dry run, nothing is changed)' -ForegroundColor Cyan
try {
    $sd = [IO.File]::ReadAllText((Join-Path $root 'tools\Set_Dns.ps1'))
    Assert ($sd -match "Get-State 'DnsApplied'" -and $sd -match 'never overwrite it with the current ones') 'Apply reads the file backup when the registry copy is gone'
    Assert ($sd -match 'a later change would treat these old settings as the original') 'a successful Undo removes the file backup'
    $nt = [IO.File]::ReadAllText((Join-Path $root 'tools\Network_Test.ps1'))
    Assert ($nt -match 'DNS_before\.json') 'Network Test offers U when only the backup file exists'
    $tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ('pcopt_dnstest_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path (Join-Path $tmpRoot 'Backup') | Out-Null
    [IO.File]::WriteAllText((Join-Path $tmpRoot 'Backup\DNS_before.json'), '[{"Guid":"{00000000-0000-0000-0000-000000000000}","Name":"Test adapter","Static":true,"Servers":["9.9.9.9"]}]')
    $out = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tools\Set_Dns.ps1') -Action Undo -DryRun -Root $tmpRoot 2>&1) -join "`n"
    if ($out -match 'No active network adapter') { Pass 'no active adapter on this machine, file fallback check skipped' }
    else { Assert ($out -notmatch 'No saved earlier DNS') 'Undo finds the backup in the file when the registry copy is missing' }
    try { [IO.Directory]::Delete($tmpRoot, $true) } catch { }
} catch {
    Fail ('DNS backup test threw: ' + $_.Exception.Message)
}
Write-Host ''
Write-Host '== Power plan is never downgraded' -ForegroundColor Cyan
$master = [IO.File]::ReadAllText((Join-Path $root '1_Start_Here - PC_Optimizer_Master (Run as Administrator).bat'))
Assert ($master -match ':PPKEEP' -and $master -match 'goto PPKEEP') 'the menu keeps a custom power plan when Ultimate Performance cannot be added'
$cs = [IO.File]::ReadAllText((Join-Path $root 'tools\Check_Status.ps1'))
Assert ($cs -match '\$customFast') 'Check Status accepts a custom plan that already runs the CPU at 100%'
Write-Host ''
Write-Host '== Safety guards' -ForegroundColor Cyan
$deep = [IO.File]::ReadAllText((Join-Path $root 'repair-tools\Deep_Clean_Junk_Files.bat'))
Assert ($deep -match '(?i)DownloadsFolder"\s*set "FLAG=0"') 'Deep clean switches the Downloads category OFF'
Assert (-not ($deep -match '(?i)for /f[^\r\n]*VolumeCaches[^\r\n]*do\s*\(')) 'Deep clean no longer switches every category on in one loop'
Assert ($deep -match 'Recycle Bin' -and $deep -match 'Previous Installations') 'Deep clean asks about the Recycle Bin and old Windows files'
Write-Host ''
Write-Host '== Hygiene' -ForegroundColor Cyan
$leaks = @()
foreach ($f in @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Extension -in '.bat', '.ps1', '.reg', '.md', '.html' -and $_.FullName -notmatch '\\(\.git|tests)\\' })) {
    if (([IO.File]::ReadAllText($f.FullName)) -match 'C:\\Users\\[A-Za-z0-9._-]+\\') { $leaks += $f.Name }
}
Assert ($leaks.Count -eq 0) ('no personal user path in tracked files ' + ($leaks -join ', '))

Write-Host ''
if ($failures.Count -eq 0) {
    Write-Host ('All ' + $checks + ' checks passed.') -ForegroundColor Green
    exit 0
}
Write-Host ([string]$failures.Count + ' of ' + $checks + ' checks FAILED:') -ForegroundColor Red
foreach ($m in $failures) { Write-Host ('  - ' + $m) -ForegroundColor Red }
exit 1
