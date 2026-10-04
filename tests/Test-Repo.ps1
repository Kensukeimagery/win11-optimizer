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
    $fake = @([pscustomobject]@{ Title = 'Fake driver'; Update = $null })
    Install-Offers $null $fake '' 6>$null
    Pass 'dry run of the install step prints and installs nothing'
} catch {
    Fail ('driver rules threw: ' + $_.Exception.Message)
}
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
