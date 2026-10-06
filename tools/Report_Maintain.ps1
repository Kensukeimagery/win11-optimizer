# Quiet housekeeping for the Logs folder, started by the main menu: moves reports that older versions saved next to the scripts
# into Logs, then removes the oldest reports so only the newest few of each kind are kept (see Report_Files.ps1).
# It never touches Backup and never deletes anything that is not a report with an exact report name.
param([string]$Root = '')

$ErrorActionPreference = 'SilentlyContinue'
if ($Root -eq '') { $Root = Split-Path -Parent $PSScriptRoot }
$Root = (Resolve-Path -LiteralPath $Root).Path
. (Join-Path $PSScriptRoot 'Report_Files.ps1')
[void](Move-ReportsToLogs $Root)
[void](Remove-OldReports $Root)
exit 0
