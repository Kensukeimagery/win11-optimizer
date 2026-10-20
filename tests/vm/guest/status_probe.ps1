# Prints one line per setting: "<id>|<status>" (OK, CHANGED, MISSING, ...). Read-only. Used by vm_tests.ps1.
param([string]$Root)
. (Join-Path $Root 'tools\Check_Status.ps1') -Root $Root
Invoke-Checks (Join-Path $Root 'reg') (Join-Path $env:TEMP 'pcopt_vmtest_unused')
foreach ($i in $script:Items) { Write-Output ([string]$i.Id + '|' + [string]$i.Status) }
