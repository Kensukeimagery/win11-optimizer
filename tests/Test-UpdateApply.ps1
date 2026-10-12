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
foreach ($n in 'reg', 'reg_undo', 'tools', 'docs', 'repair-tools', 'More Tools') { Copy-Item -LiteralPath (Join-Path $repo $n) -Destination (Join-Path $inst $n) -Recurse }
foreach ($f in @(Get-ChildItem -LiteralPath $repo -File | Where-Object { $_.Name -in 'README.md', 'CHANGELOG.md', 'LICENSE', 'VERSION' -or $_.Extension -eq '.bat' })) { Copy-Item -LiteralPath $f.FullName -Destination $inst }
Set-Content -LiteralPath (Join-Path $inst 'VERSION') -Value '1.0'
New-Item -ItemType Directory -Force -Path (Join-Path $inst 'Backup\old') | Out-Null
Set-Content -LiteralPath (Join-Path $inst 'Backup\old\keep.txt') -Value 'x'
Set-Content -LiteralPath (Join-Path $inst 'OptimizerLog_test.txt') -Value 'log'
New-Item -ItemType Directory -Force -Path (Join-Path $inst 'Logs') | Out-Null
Set-Content -LiteralPath (Join-Path $inst 'Logs\CheckReport_20260101_000000.txt') -Value 'user report'
Set-Content -LiteralPath (Join-Path $inst 'NEWFILE.md') -Value 'precious'   # a file the new version also ships
Set-Content -LiteralPath (Join-Path $inst 'More Tools\old_tool_removed_later.bat') -Value 'rem old'

# the "new version": same files, VERSION 2.0, README removed, a changed NEWFILE.md and one extra file
foreach ($c in @(Get-ChildItem -LiteralPath $inst -Force | Where-Object { $_.Name -notin 'Backup', 'Logs', 'OptimizerLog_test.txt' })) { Copy-Item -LiteralPath $c.FullName -Destination $stg -Recurse }
Set-Content -LiteralPath (Join-Path $stg 'VERSION') -Value '2.0'
Set-Content -LiteralPath (Join-Path $stg 'NEWFILE.md') -Value 'replaced'
Set-Content -LiteralPath (Join-Path $stg 'ONLYNEW.md') -Value 'n'
[IO.File]::Delete((Join-Path $stg 'README.md'))
[IO.File]::Delete((Join-Path $stg 'More Tools\old_tool_removed_later.bat'))

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
Check (@(Get-ChildItem -LiteralPath (Join-Path $inst 'Logs') -Filter 'UpdateLog_*' -ErrorAction SilentlyContinue).Count -ge 1) 'an update log was written into Logs'
Check (Test-Path -LiteralPath (Join-Path $inst 'Logs\CheckReport_20260101_000000.txt')) 'the user Logs folder is untouched'
Check ((-not (Test-Path -LiteralPath (Join-Path $inst 'More Tools\old_tool_removed_later.bat'))) -and (Test-Path -LiteralPath (Join-Path $bk2 'More Tools\old_tool_removed_later.bat'))) 'a tool removed from More Tools by the new version is gone and kept in the backup'
Check (@(Get-ChildItem -LiteralPath (Join-Path $inst 'More Tools') -File -Filter '*.bat').Count -ge 9) 'the More Tools folder is installed with its tools'

Write-Host '== update from the OLD layout (v4.20: every launcher in the main folder) with the OLD updater'
$tagOk = $false
try { & git -C $repo rev-parse -q --verify 'refs/tags/v4.20' *> $null; $tagOk = ($LASTEXITCODE -eq 0) } catch { }
if (-not $tagOk) {
    Write-Host '  (skipped: the v4.20 tag is not in this checkout)' -ForegroundColor DarkGray
} else {
    $oldZip = Join-Path $tmp 'old419.zip'
    $oldInst = Join-Path $tmp 'Old Layout (test)'
    & git -C $repo archive --format=zip -o $oldZip v4.20
    Expand-Archive -LiteralPath $oldZip -DestinationPath $oldInst -Force
    $oldUpd = Join-Path $tmp 'old_updater.ps1'
    (& git -C $repo show 'v4.20:tools/Update.ps1') | Set-Content -LiteralPath $oldUpd -Encoding UTF8
    New-Item -ItemType Directory -Force -Path (Join-Path $oldInst 'Logs') | Out-Null
    Set-Content -LiteralPath (Join-Path $oldInst 'Logs\CheckReport_20260101_000000.txt') -Value 'user report'
    $stg2 = Join-Path $tmp 'staged_new'
    New-Item -ItemType Directory -Force -Path $stg2 | Out-Null
    foreach ($n in 'reg', 'reg_undo', 'tools', 'docs', 'repair-tools', 'More Tools') { Copy-Item -LiteralPath (Join-Path $repo $n) -Destination (Join-Path $stg2 $n) -Recurse }
    foreach ($f in @(Get-ChildItem -LiteralPath $repo -File | Where-Object { $_.Name -in 'README.md', 'CHANGELOG.md', 'LICENSE', 'VERSION' -or $_.Extension -eq '.bat' })) { Copy-Item -LiteralPath $f.FullName -Destination $stg2 }
    Set-Content -LiteralPath (Join-Path $stg2 'VERSION') -Value '9.9'
    $bk3 = Join-Path $oldInst 'Backup\update_old_layout'
    '' | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $oldUpd -Action Apply -Root $oldInst -Staged $stg2 -BackupDir $bk3 -NewVersion 9.9 -WorkDir (Join-Path $tmp 'w3') | Out-Null
    $rootAfter = @(Get-ChildItem -LiteralPath $oldInst -File -Filter '*.bat' | ForEach-Object { $_.Name })
    Check ((Get-Content -LiteralPath (Join-Path $oldInst 'VERSION')).Trim() -eq '9.9') 'the old updater installs the new layout'
    Check ($rootAfter.Count -eq 3) ('only the three main files are left in the main folder ' + ($rootAfter -join ' | '))
    Check (@(Get-ChildItem -LiteralPath (Join-Path $oldInst 'More Tools') -File -Filter '*.bat' -ErrorAction SilentlyContinue).Count -eq 9) 'the nine extra tools are in More Tools'
    Check (Test-Path -LiteralPath (Join-Path $bk3 '3_Check_Status (Run as Administrator).bat')) 'the old launchers from the main folder are saved in the backup'
    Check (Test-Path -LiteralPath (Join-Path $oldInst 'Logs\CheckReport_20260101_000000.txt')) 'the user reports are untouched'
}

try { [IO.Directory]::Delete($tmp, $true) } catch { }
Write-Host ''
if ($fail.Count -eq 0) { Write-Host 'Update install tests passed.' -ForegroundColor Green; exit 0 }
Write-Host ([string]$fail.Count + ' problem(s).') -ForegroundColor Red
exit 1
