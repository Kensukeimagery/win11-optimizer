# Builds the VM TEST EDITION: a trimmed copy of the tool plus the VM test suite, for use inside a virtual machine only.
#   powershell -File tests\vm\Make_VM_Edition.ps1 [-OutDir E:\win11-optimizer-vm-test]
# It leaves out the manuals, pictures, GPU guide, repair-tools, README files and the repository tests, and adds VM_TEST\ (see tests\vm\guest\VM_README.txt).
# The output folder is rebuilt every time, except _reports (the reports from earlier VM runs are kept).
param(
    [string]$OutDir = 'E:\win11-optimizer-vm-test',
    [string]$Root = ''
)

$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$Root = (Resolve-Path -LiteralPath $Root).Path
if (-not (Test-Path -LiteralPath (Join-Path $Root 'VERSION'))) { throw ('This is not the tool folder (no VERSION file): ' + $Root) }
$version = ([IO.File]::ReadAllText((Join-Path $Root 'VERSION'))).Trim()

# keep the old reports, rebuild the rest. Never wipe a folder that is not an earlier edition (a wrong -OutDir must not delete anything).
if (Test-Path -LiteralPath $OutDir) {
    $existingItems = @(Get-ChildItem -LiteralPath $OutDir -Force | Where-Object { $_.Name -ne '_reports' })
    if ($existingItems.Count -gt 0 -and -not (Test-Path -LiteralPath (Join-Path $OutDir 'VM_TEST_EDITION.txt'))) {
        throw ('The folder ' + $OutDir + ' is not empty and is not an earlier VM test edition (no VM_TEST_EDITION.txt). Pick an empty folder or a new name.')
    }
}
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path
if ($OutDir.Length -le 3) { throw 'The output folder must not be the root of a drive.' }
foreach ($item in @(Get-ChildItem -LiteralPath $OutDir -Force | Where-Object { $_.Name -ne '_reports' })) {
    Remove-Item -LiteralPath $item.FullName -Recurse -Force
}
New-Item -ItemType Directory -Path (Join-Path $OutDir '_reports') -Force | Out-Null

# what the VM needs
$dirs = @('More Tools', 'tools', 'reg', 'reg_undo')
foreach ($d in $dirs) { Copy-Item -LiteralPath (Join-Path $Root $d) -Destination (Join-Path $OutDir $d) -Recurse -Force }
foreach ($f in @(Get-ChildItem -LiteralPath $Root -File -Filter '*.bat')) { Copy-Item -LiteralPath $f.FullName -Destination $OutDir -Force }
foreach ($f in 'VERSION', 'LICENSE') { if (Test-Path -LiteralPath (Join-Path $Root $f)) { Copy-Item -LiteralPath (Join-Path $Root $f) -Destination $OutDir -Force } }

# the two repository tests that make sense in a VM
New-Item -ItemType Directory -Path (Join-Path $OutDir 'tests') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $Root 'tests\Test-RegRoundTrip.ps1') -Destination (Join-Path $OutDir 'tests') -Force
Copy-Item -LiteralPath (Join-Path $Root 'tests\master_input.txt') -Destination (Join-Path $OutDir 'tests') -Force

# the VM test suite
$vmDir = Join-Path $OutDir 'VM_TEST'
New-Item -ItemType Directory -Path $vmDir -Force | Out-Null
$guest = Join-Path $PSScriptRoot 'guest'
foreach ($f in 'vm_tests.ps1', 'status_probe.ps1') { Copy-Item -LiteralPath (Join-Path $guest $f) -Destination $vmDir -Force }
Copy-Item -LiteralPath (Join-Path $guest 'VM_README.txt') -Destination (Join-Path $OutDir 'VM_README.txt') -Force
$runBat = Join-Path $guest 'Run_VM_Tests (Run as Administrator).bat'
$bat = [IO.File]::ReadAllText($runBat) -replace "`r?`n", "`r`n"
[IO.File]::WriteAllText((Join-Path $OutDir 'Run_VM_Tests (Run as Administrator).bat'), $bat, (New-Object System.Text.UTF8Encoding($false)))

# a marker, so nobody mistakes this copy for the real release
$commit = ''
try { $commit = (& git -C $Root rev-parse --short HEAD 2>$null) } catch { }
$marker = 'VM TEST EDITION of Windows 11 Optimizer v' + $version + ' (commit ' + $commit + '), built ' + (Get-Date -Format 'yyyy-MM-dd HH:mm') + ". For virtual machines only.`r`n"
[IO.File]::WriteAllText((Join-Path $OutDir 'VM_TEST_EDITION.txt'), $marker, (New-Object System.Text.UTF8Encoding($false)))

$bytes = (Get-ChildItem -LiteralPath $OutDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
Write-Host ('VM test edition v' + $version + ' written to ' + $OutDir + ' (' + [math]::Round($bytes / 1KB) + ' KB)') -ForegroundColor Green
