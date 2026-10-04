# Sandbox test: applies every tweak file, checks it, then undoes it and checks again.
# THIS CHANGES THE REGISTRY. It refuses to run anywhere except a disposable CI machine (CI=true).
$ErrorActionPreference = 'Continue'
if ($env:CI -ne 'true') {
    Write-Host 'Refusing to run: this test changes the registry and is only for the disposable GitHub Actions machine (CI=true).' -ForegroundColor Red
    exit 2
}
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'tools\Check_Status.ps1') -Root $root

$fail = New-Object System.Collections.Generic.List[string]
function Note([string]$t, [string]$c = 'Gray') { Write-Host $t -ForegroundColor $c }

$files = @(Get-ChildItem -LiteralPath (Join-Path $root 'reg') -Recurse -File -Filter '*.reg' | Sort-Object Name)
foreach ($f in $files) {
    $num = $f.Name.Substring(0, 2)
    & reg.exe import $f.FullName *> $null
    if ($LASTEXITCODE -ne 0) { $fail.Add($f.Name + ': reg import failed'); Note ('  [FAIL] import ' + $f.Name) 'Red'; continue }
    $r = Get-RegTweakStatus $f
    if ($r.Status -ne 'OK') { $fail.Add($f.Name + ': not OK after import (' + $r.Status + ' ' + $r.Detail + ')'); Note ('  [FAIL] ' + $f.Name + ' after import: ' + $r.Status + ' ' + $r.Detail) 'Red' }
    else { Note ('  [PASS] ' + $f.Name + ' applied and detected as OK') 'Green' }

    $undo = @(Get-ChildItem -LiteralPath (Join-Path $root 'reg_undo') -File -Filter ('UNDO_' + $num + '_*.reg'))[0]
    & reg.exe import $undo.FullName *> $null
    if ($LASTEXITCODE -ne 0) { $fail.Add($undo.Name + ': reg import failed'); Note ('  [FAIL] import ' + $undo.Name) 'Red'; continue }
    $r2 = Get-RegTweakStatus $f
    if ($r2.Status -eq 'OK') { $fail.Add($undo.Name + ': tweak still reads OK after the undo file'); Note ('  [FAIL] ' + $undo.Name + ' did not change anything') 'Red' }
    else { Note ('  [PASS] ' + $undo.Name + ' undone, detected as ' + $r2.Status) 'Green' }
}

# CPU boost helper (settings may not exist on a virtual machine: exit 3 is fine)
$pb = Join-Path $root 'tools\Power_Boost.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $pb -Action Apply *> $null
$a = $LASTEXITCODE
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $pb -Action Undo *> $null
$u = $LASTEXITCODE
if (($a -eq 0 -or $a -eq 3) -and ($u -eq 0 -or $u -eq 3)) { Note ('  [PASS] Power_Boost apply=' + $a + ' undo=' + $u) 'Green' } else { $fail.Add('Power_Boost apply=' + $a + ' undo=' + $u); Note ('  [FAIL] Power_Boost apply=' + $a + ' undo=' + $u) 'Red' }

# DNS helper dry run (never touches the adapters)
$dns = Join-Path $root 'tools\Set_Dns.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dns -Action Apply -Servers 1.1.1.1,1.0.0.1 -DryRun *> $null
$d1 = $LASTEXITCODE
if ($d1 -eq 0 -or $d1 -eq 1) { Note ('  [PASS] Set_Dns dry run exit ' + $d1) 'Green' } else { $fail.Add('Set_Dns dry run exit ' + $d1); Note ('  [FAIL] Set_Dns dry run exit ' + $d1) 'Red' }

Write-Host ''
if ($fail.Count -eq 0) { Write-Host 'Round trip passed.' -ForegroundColor Green; exit 0 }
Write-Host ([string]$fail.Count + ' problem(s):') -ForegroundColor Red
foreach ($m in $fail) { Write-Host ('  - ' + $m) -ForegroundColor Red }
exit 1
