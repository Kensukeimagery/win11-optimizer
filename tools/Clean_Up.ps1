# PC Optimizer v4.17 - clean up old reports and backups
# Shows what is in the Logs and Backup folders and removes old files ONLY when you choose.
#   Reports in Logs: the newest few of each kind are kept automatically (default 3). You can change that number here.
#   Backups: listed with their size. Older ones are removed only after you say yes (default is no). The newest ones are always kept.
# Nothing else is ever touched: only files and folders with exactly the names this program creates.
#   -NoPrompt  print the summary and stop
#   -DryRun    show what would be removed and remove nothing
param(
    [string]$Root = '',
    [switch]$NoPrompt,
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'
if ($Root -eq '') { $Root = Split-Path -Parent $PSScriptRoot }
$Root = (Resolve-Path -LiteralPath $Root).Path
. (Join-Path $PSScriptRoot 'Report_Files.ps1')

function Read-Answer([string]$Prompt, [string[]]$Allowed) {
    # Enter or closed input means the first (safe) answer.
    for ($try = 0; $try -lt 20; $try++) {
        $raw = Read-Host $Prompt
        if ($null -eq $raw) { break }
        $a = ([string]$raw).Trim().ToUpper()
        if ($a -eq '') { $a = $Allowed[0] }
        if ($Allowed -contains $a) { return $a }
        Write-Host ('   Please type one of: ' + ($Allowed -join ', ')) -ForegroundColor DarkYellow
    }
    return $Allowed[0]
}

function Show-Summary {
    $keep = Get-KeepSetting
    $logsDir = Get-LogsDir $Root
    $files = @(Get-ReportFiles $logsDir) + @(Get-ReportFiles $Root)   # reports from older versions may still be next to the scripts
    $total = [int64]0; foreach ($f in $files) { $total += $f.Bytes }
    Write-Host ''
    Write-Host '   Reports and logs (folder Logs)' -ForegroundColor White
    if ($files.Count -eq 0) { Write-Host '     none' -ForegroundColor Gray }
    else {
        Write-Host ('     ' + $files.Count + ' file(s), ' + (Format-Size $total)) -ForegroundColor Gray
        foreach ($g in @($files | Group-Object Kind | Sort-Object Name)) { Write-Host ('       ' + $g.Name.PadRight(24) + $g.Count) -ForegroundColor DarkGray }
    }
    if ($keep -eq 0) { Write-Host '     Automatic cleanup is OFF (keep = 0). Nothing is removed by itself.' -ForegroundColor Yellow }
    else { Write-Host ('     Automatic cleanup keeps the newest ' + $keep + ' of each kind (a support bundle keeps ' + ($keep + $script:SupportBundleExtra) + ').') -ForegroundColor Gray }
    $oldReports = @(Select-ReportsToRemove $files $keep)
    $oldBytes = [int64]0; foreach ($f in $oldReports) { $oldBytes += $f.Bytes }
    Write-Host ('     Older than that right now: ' + $oldReports.Count + ' file(s), ' + (Format-Size $oldBytes)) -ForegroundColor Gray

    $items = @(Get-BackupItems $Root)
    $tb = [int64]0; foreach ($i in $items) { $tb += $i.Bytes }
    Write-Host ''
    Write-Host '   Backups (folder Backup, never removed by themselves)' -ForegroundColor White
    if ($items.Count -eq 0) { Write-Host '     none' -ForegroundColor Gray }
    else {
        Write-Host ('     ' + $items.Count + ' backup folder(s), ' + (Format-Size $tb)) -ForegroundColor Gray
        foreach ($g in @($items | Group-Object Group | Sort-Object { ($_.Group | Measure-Object Bytes -Sum).Sum } -Descending)) {
            $b = [int64]($g.Group | Measure-Object Bytes -Sum).Sum
            Write-Host ('       ' + $g.Group[0].Text) -ForegroundColor DarkGray
            Write-Host ('         ' + $g.Count + ' folder(s), ' + (Format-Size $b) + '; the newest ' + $g.Group[0].Keep + ' are kept') -ForegroundColor DarkGray
        }
    }
    $oldBackups = @(Select-BackupsToRemove $items)
    $ob = [int64]0; foreach ($i in $oldBackups) { $ob += $i.Bytes }
    Write-Host ('     Older backups you could remove now: ' + $oldBackups.Count + ' folder(s), ' + (Format-Size $ob)) -ForegroundColor Yellow
    return @{ Keep = $keep; OldReports = $oldReports; OldBackups = $oldBackups }
}

function Start-CleanUp {
    Write-Host '==================================================================' -ForegroundColor Cyan
    Write-Host '   PC OPTIMIZER v4.17 - CLEAN UP OLD REPORTS AND BACKUPS' -ForegroundColor Cyan
    Write-Host '==================================================================' -ForegroundColor Cyan
    # the summary modes only look; moving reports from older versions into Logs happens in the normal interactive run and in the main menu's housekeeping
    if (-not $NoPrompt -and -not $DryRun) {
        $moved = Move-ReportsToLogs $Root
        if ($moved -gt 0) { Write-Host ('   Moved ' + $moved + ' report(s) from older versions into the Logs folder.') -ForegroundColor DarkGray }
    }
    $s = Show-Summary
    if ($NoPrompt) { return }

    Write-Host ''
    Write-Host '   What would you like to do? Nothing is removed unless you choose.' -ForegroundColor White
    $allowed = New-Object System.Collections.Generic.List[string]
    $allowed.Add('N')
    if ($s.OldReports.Count -gt 0) { Write-Host ('   R = remove the ' + $s.OldReports.Count + ' old report file(s) now'); $allowed.Add('R') }
    if ($s.OldBackups.Count -gt 0) { Write-Host ('   B = look at the ' + $s.OldBackups.Count + ' old backup folder(s) and decide'); $allowed.Add('B') }
    Write-Host '   K = change how many reports are kept (0 = never remove reports)'; $allowed.Add('K')
    Write-Host '   N = do nothing (default)'
    $ans = Read-Answer '   Your choice (Enter = N)' @($allowed.ToArray())
    if ($ans -eq 'N') { Write-Host '   Nothing was changed.' -ForegroundColor DarkGray; return }

    if ($ans -eq 'R') {
        $r = Remove-OldReports $Root -Keep $s.Keep -DryRun:$DryRun
        Write-Host ('   ' + $(if ($DryRun) { '[DRY RUN] would remove ' } else { 'Removed ' }) + $r.Count + ' report file(s), ' + (Format-Size $r.Bytes) + '.') -ForegroundColor Green
    }
    if ($ans -eq 'K') {
        $new = $null
        for ($try = 0; $try -lt 10 -and $null -eq $new; $try++) {
            $raw = Read-Host '   Keep how many of each kind? A number from 0 to 99 (Enter = no change)'
            if ($null -eq $raw -or ([string]$raw).Trim() -eq '') { break }
            $n = 0
            if ([int]::TryParse(([string]$raw).Trim(), [ref]$n) -and $n -ge 0 -and $n -le 99) { $new = $n } else { Write-Host '   Please type a whole number from 0 to 99.' -ForegroundColor DarkYellow }
        }
        if ($null -eq $new) { Write-Host '   No change.' -ForegroundColor DarkGray }
        elseif ($DryRun) { Write-Host ('   [DRY RUN] would keep ' + $new + '.') -ForegroundColor Yellow }
        else { Set-KeepSetting $new; Write-Host ('   Saved: the newest ' + $new + ' of each kind are kept' + $(if ($new -eq 0) { ' (automatic removal is off)' } else { '' }) + '.') -ForegroundColor Green }
    }
    if ($ans -eq 'B') {
        Write-Host ''
        Write-Host '   These backup folders would be removed (the newest ones of each kind stay):' -ForegroundColor White
        foreach ($i in @($s.OldBackups | Sort-Object Group, Stamp)) { Write-Host ('     ' + $i.Name.PadRight(40) + (Format-Size $i.Bytes)) -ForegroundColor Gray }
        Write-Host '   Backups are your way back if something goes wrong. Remove them only when the PC works as you want.' -ForegroundColor DarkYellow
        $go = Read-Answer '   Remove these backup folders? Y/N (Enter = N)' @('N', 'Y')
        if ($go -ne 'Y') { Write-Host '   Nothing was removed.' -ForegroundColor DarkGray; return }
        if ($DryRun) { Write-Host '   [DRY RUN] nothing was removed.' -ForegroundColor Yellow; return }
        $r = Remove-BackupItems $s.OldBackups $Root
        Write-Host ('   Removed ' + $r.Count + ' backup folder(s), ' + (Format-Size $r.Bytes) + ' freed.') -ForegroundColor Green
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Start-CleanUp
    exit 0
}
