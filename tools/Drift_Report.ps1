# PC Optimizer v4.33 - quiet check: did Windows change my settings back? (reads only)
# Started by the scheduled task from Drift_Task.ps1 after a Windows Update and at sign-in, or by hand. It compares the live PC with
# the settings this tool put in place (the same comparison as Check Status), writes a short report to the Logs folder and, when
# something was changed back, shows one notification. It never changes a setting: open Win11 Optimizer or Check Status to fix it.
#   -Action Check (default)   check, write the report, notify when something changed back
#   -NoToast                  do not show the notification
# A PC where the tool has never put anything in place has nothing that can be changed back: the result is then "nothing".
param(
    [string]$Root = '',
    [switch]$NoToast,
    [string]$DriftKey = 'HKCU:\Software\PCOptimizer'   # where the result is remembered (a test passes a temporary key)
)

$ErrorActionPreference = 'SilentlyContinue'
if ($Root -eq '') { $Root = Split-Path -Parent $PSScriptRoot }
$Root = (Resolve-Path -LiteralPath $Root).Path
. (Join-Path $PSScriptRoot 'Report_Files.ps1')
. (Join-Path $PSScriptRoot 'Check_Status.ps1') -Root $Root

function Get-DriftItems($Items) {
    # items that were in place and are not any more: CHANGED, or MISSING for a tweak that was applied (its saved choice is Y)
    $out = @()
    foreach ($i in $Items) {   # not @($Items): the list is a generic List, and @() of it fails on Windows PowerShell 5.1
        if ($i.Status -eq 'CHANGED') { $out += $i; continue }
        if ($i.Status -eq 'MISSING' -and $i.Id -match '^\d{2}$' -and (Get-Choice $i.Id) -eq 'Y') { $out += $i }
    }
    return $out
}

function Test-EverApplied {
    try {
        $p = Get-ItemProperty -Path 'HKCU:\Software\PCOptimizer' -ErrorAction Stop
        return @($p.PSObject.Properties | Where-Object { $_.Name -like 'Choice_*' -and $_.Value -eq 'Y' }).Count -gt 0
    } catch { return $false }
}

function Show-Toast([string]$Title, [string]$Text) {
    # a normal Windows notification, shown in the name of Windows PowerShell; failing quietly is fine
    try {
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $esc = { param($s) [Security.SecurityElement]::Escape($s) }
        $xml.LoadXml('<toast><visual><binding template="ToastGeneric"><text>' + (& $esc $Title) + '</text><text>' + (& $esc $Text) + '</text></binding></visual></toast>')
        $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1' + '.0\powershell.exe'   # the id of Windows PowerShell (written in two pieces: the version check of the tests reads "v1.0" as a version)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
    } catch { }
}

if ($MyInvocation.InvocationName -eq '.') { return }   # loaded by a test

Invoke-Checks (Join-Path $Root 'reg') (Join-Path $env:TEMP 'pcopt_drift_unused')
$drift = @()
if (Test-EverApplied) { $drift = @(Get-DriftItems $script:Items.ToArray()) }

$lines = @('PC Optimizer - check after Windows Update', ('Time: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')), '')
if ($drift.Count -eq 0) { $lines += 'Nothing was changed back. Every setting this tool put in place is still in place.' }
else {
    $lines += ('Windows (or a program) changed ' + $drift.Count + ' setting(s) back:')
    foreach ($d in $drift) { $lines += ('  ' + $d.Id.PadRight(5) + ' ' + $d.Title + $(if ($d.Detail) { ' - ' + $d.Detail } else { '' })) }
    $lines += ''; $lines += 'Open Win11 Optimizer and press Fix them, or run Check Status, to put them back.'
}
try { [IO.File]::WriteAllLines((New-ReportPath $Root 'DriftReport'), $lines); Remove-OldReports $Root | Out-Null } catch { }

# remember the result, and notify only when the set of changed settings is new (not again at every sign-in)
$signature = ($drift | ForEach-Object { $_.Id } | Sort-Object) -join ','
$last = ''
try { $last = [string](Get-ItemProperty -Path $DriftKey -Name 'DriftNotified' -ErrorAction Stop).DriftNotified } catch { }
try {
    if (-not (Test-Path $DriftKey)) { New-Item -Path $DriftKey -Force | Out-Null }
    New-ItemProperty -Path $DriftKey -Name 'DriftCount' -Value ([string]$drift.Count) -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $DriftKey -Name 'DriftTime' -Value (Get-Date -Format 's') -PropertyType String -Force | Out-Null
} catch { }
if ($drift.Count -gt 0 -and $signature -ne $last -and -not $NoToast) {
    Show-Toast 'PC Optimizer' ('Windows changed ' + $drift.Count + ' of your settings back. Open Win11 Optimizer and press Fix them.')
    try { New-ItemProperty -Path $DriftKey -Name 'DriftNotified' -Value $signature -PropertyType String -Force | Out-Null } catch { }
}
if ($drift.Count -eq 0) { try { Remove-ItemProperty -Path $DriftKey -Name 'DriftNotified' -ErrorAction SilentlyContinue } catch { } }
Write-Output ($lines -join "`r`n")
exit 0
