# Read-only. Prints the state of every setting for the Windows app (Win11 Optimizer.exe), one line each:  <id>|<status>|<title>
# Status is OK, CHANGED, MISSING, NOT CHOSEN, SKIPPED or UNKNOWN (the same words as Check Status). Nothing is changed.
param([string]$Root = '')

$ErrorActionPreference = 'SilentlyContinue'
if ($Root -eq '') { $Root = Split-Path -Parent $PSScriptRoot }
$Root = (Resolve-Path -LiteralPath $Root).Path
. (Join-Path $PSScriptRoot 'Check_Status.ps1') -Root $Root
Invoke-Checks (Join-Path $Root 'reg') (Join-Path $env:TEMP 'pcopt_gui_unused')
foreach ($i in $script:Items) {
    $title = ([string]$i.Title) -replace '[\r\n|]', ' '
    Write-Output ([string]$i.Id + '|' + [string]$i.Status + '|' + $title)
}
