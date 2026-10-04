# Tests the install step of the updater on a throwaway copy: success, overwrite, and automatic roll back.
# Never touches your real install, the registry or the network.
$ErrorActionPreference = 'Continue'
$repo = Split-Path -Parent $PSScriptRoot
$fail = New-Object System.Collections.Generic.List[string]
function Check([bool]$Cond, [string]$Text) {
    if ($Cond) { Write-Host ('  [PASS] ' + $Text) -ForegroundColor Green } else { $script:fail.Add($Text); Write-Host ('  [FAIL] ' + $Text) -ForegroundColor Red }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('pcopt_updtest_' + [guid]::NewGuid().ToString('N'))
$inst = Join-Path $tmp 'My Install (test)'    # spaces and brackets on purpose
$stg = Join-Path $tmp 'staged'
New-Item -ItemType Directory -Force -Path $inst, $stg | Out-Null
foreach ($n in 'reg', 'reg_undo', 'tools', 'docs', 'repair-tools') { Copy-Item -LiteralPath (Join-Path $repo $n) -Destination (Join-Path $inst $n) -Recurse }
foreach ($f in @(Get-ChildItem -LiteralPath $repo -File | Where-Object { $_.Name -in 'README.md', 'CHANGELOG.md', 'LICENSE', 'VERSION' -or $_.Extension -eq '.bat' })) { Copy-Item -LiteralPath $f.FullName -Destination $inst }
Set-Content -LiteralPath (Join-Path $inst 'VERSION') -Value '1.0'
New-Item -ItemType Directory -Force -Path (Join-Path $inst 'Backup\old') | Out-Null
Set-Content -LiteralPath (Join-Path $inst 'Backup\old\keep.txt') -Value 'x'
Set-Content -LiteralPath (Join-Path $inst 'OptimizerLog_test.txt') -Value 'log'
Set-Content -LiteralPath (Join-Path $inst 'NEWFILE.md') -Value 'precious'   # a file the new version also ships

# the "new version": same files, VERSION 2.0, README removed, a changed NEWFILE.md and one extra file
foreach ($c in @(Get-ChildItem -LiteralPath $inst -Force | Where-Object { $_.Name -notin 'Backup', 'OptimizerLog_test.txt' })) { Copy-Item -LiteralPath $c.FullName -Destination $stg -Recurse }
Set-Content -LiteralPath (Join-Path $stg 'VERSION') -Value '2.0'
Set-Content -LiteralPath (Join-Path $stg 'NEWFILE.md') -Value 'replaced'
Set-Content -LiteralPath (Join-Path $stg 'ONLYNEW.md') -Value 'n'
[IO.File]::Delete((Join-Path $stg 'README.md'))

$upd = Join-Path $inst 'tools\Update.ps1'

Write-Host '== roll back when the final check fails (wrong expected version)'
$bk1 = Join-Path $inst 'Backup\update_1.0_a'
'' | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $upd -Action Apply -Root $inst -Staged $stg -BackupDir $bk1 -NewVersion 3.0 -WorkDir (Join-Path $tmp 'w1') | Out-Null
Check ((Get-Content -LiteralPath (Join-Path $inst 'VERSION')).Trim() -eq '1.0') 'old VERSION is back after the failed update'
Check (-not (Test-Path -LiteralPath (Join-Path $inst 'ONLYNEW.md'))) 'a file only the new version has is removed again'
Check ((Get-Content -LiteralPath (Join-Path $inst 'NEWFILE.md')).Trim() -eq 'precious') 'a file the new version would overwrite is restored'
Check (Test-Path -LiteralPath (Join-Path $inst 'README.md')) 'README is back'
Check (Test-Path -LiteralPath (Join-Path $inst 'Backup\old\keep.txt')) 'the user Backup folder is untouched'

Write-Host '== successful update'
$bk2 = Join-Path $inst 'Backup\update_1.0_b'
'' | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $upd -Action Apply -Root $inst -Staged $stg -BackupDir $bk2 -NewVersion 2.0 -WorkDir (Join-Path $tmp 'w2') | Out-Null
Check ((Get-Content -LiteralPath (Join-Path $inst 'VERSION')).Trim() -eq '2.0') 'VERSION is the new one'
Check (Test-Path -LiteralPath (Join-Path $inst 'ONLYNEW.md')) 'the new file is installed'
Check ((Get-Content -LiteralPath (Join-Path $inst 'NEWFILE.md')).Trim() -eq 'replaced') 'a shipped file is overwritten'
Check ((Get-Content -LiteralPath (Join-Path $bk2 'NEWFILE.md')).Trim() -eq 'precious') 'the old copy of an overwritten file is in the backup'
Check (Test-Path -LiteralPath (Join-Path $bk2 'README.md')) 'a file removed by the new version is kept in the backup'
Check (-not (Test-Path -LiteralPath (Join-Path $inst 'README.md'))) 'a file removed by the new version is gone from the install'
Check ((Test-Path -LiteralPath (Join-Path $inst 'Backup\old\keep.txt')) -and (Test-Path -LiteralPath (Join-Path $inst 'OptimizerLog_test.txt'))) 'user Backup and logs are untouched'
Check (@(Get-ChildItem -LiteralPath $inst -Filter 'UpdateLog_*').Count -ge 1) 'an update log was written'

try { [IO.Directory]::Delete($tmp, $true) } catch { }
Write-Host ''
if ($fail.Count -eq 0) { Write-Host 'Update install tests passed.' -ForegroundColor Green; exit 0 }
Write-Host ([string]$fail.Count + ' problem(s).') -ForegroundColor Red
exit 1
