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
