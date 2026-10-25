# PC Optimizer v4.33 - "check after Windows Update": turn the quiet check on or off
# Turning it on adds one entry to the Windows Task Scheduler for YOUR account (it needs no administrator rights and runs only while you
# are signed in): it starts tools\Drift_Report.ps1 after Windows installed an update and two minutes after you sign in. That script only
# reads, writes a short report to the Logs folder and shows one notification when Windows changed settings of this tool back.
# It changes nothing by itself. Turning it off removes the entry again. Nothing else is installed.
#   -Action On | Off | Status
# Exit codes: 0 = done (or status printed), 1 = failed.
# The entry points at this folder: if you move the folder, turn it off and on again.
param(
    [ValidateSet('On', 'Off', 'Status', 'Menu')][string]$Action = 'Status',
    [string]$Root = ''
)

$ErrorActionPreference = 'Continue'
if ($Root -eq '') { $Root = Split-Path -Parent $PSScriptRoot }
$Root = (Resolve-Path -LiteralPath $Root).Path
$TaskName = 'PC_Optimizer_DriftCheck'

function Get-DriftTaskDefinition([string]$Root) {
    # what the task will run and when; separate from registering it, so that a test can check it without touching the Task Scheduler
    $script = Join-Path $Root 'tools\Drift_Report.ps1'
    $query = '<QueryList><Query Id="0" Path="System"><Select Path="System">*[System[Provider[@Name=''Microsoft-Windows-WindowsUpdateClient''] and EventID=19]]</Select></Query></QueryList>'
    return @{
        Execute = 'powershell.exe'
        Argument = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $script + '" -Root "' + $Root + '"')
        EventQuery = $query
        LogonDelay = 'PT2M'
        Script = $script
    }
}

function Get-DriftTask {
    try { return (Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop) } catch { return $null }
}

if ($MyInvocation.InvocationName -eq '.') { return }   # loaded by a test

if ($Action -eq 'Menu') {
    Write-Host '=================================================================='
    Write-Host '   PC OPTIMIZER - CHECK AFTER WINDOWS UPDATE'
    Write-Host '=================================================================='
    Write-Host ''
    Write-Host '   A quiet check after each Windows Update and after you sign in. It only reads, writes a short report'
    Write-Host '   and shows one notification when Windows changed settings of this tool back. It changes nothing.'
    Write-Host ''
    $now = Get-DriftTask
    Write-Host ('   Now: ' + $(if ($null -eq $now) { 'OFF' } else { 'ON' }))
    Write-Host ''
    Write-Host '   1  Turn it on'
    Write-Host '   2  Turn it off'
    Write-Host ''
    $choice = ''
    try { $choice = [string](Read-Host '   Your choice, Enter = leave it as it is') } catch { }
    switch ($choice.Trim()) { '1' { $Action = 'On' } '2' { $Action = 'Off' } default { exit 0 } }
}

if ($Action -eq 'Status') {
    $t = Get-DriftTask
    if ($null -eq $t) { Write-Host 'The check after Windows Update is OFF.'; exit 0 }
    Write-Host ('The check after Windows Update is ON (' + $t.State + ').')
    try { $a = @($t.Actions)[0]; Write-Host ('   It runs: ' + $a.Execute + ' ' + $a.Arguments) } catch { }
    exit 0
}

if ($Action -eq 'Off') {
    if ($null -eq (Get-DriftTask)) { Write-Host '   The check after Windows Update was already off.'; exit 0 }
    try { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop } catch { Write-Host ('   [FAILED] ' + $_.Exception.Message); exit 1 }
    if ($null -ne (Get-DriftTask)) { Write-Host '   [FAILED] The entry is still there.'; exit 1 }
    Write-Host '   [OK] The check after Windows Update is off. Its entry in the Task Scheduler is removed.'
    exit 0
}

# On
$def = Get-DriftTaskDefinition $Root
if (-not (Test-Path -LiteralPath $def.Script)) { Write-Host ('   [FAILED] ' + $def.Script + ' was not found.'); exit 1 }
try {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $taskAction = New-ScheduledTaskAction -Execute $def.Execute -Argument $def.Argument
    $cls = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace 'Root/Microsoft/Windows/TaskScheduler'
    $eventTrigger = New-CimInstance -CimClass $cls -ClientOnly
    $eventTrigger.Subscription = $def.EventQuery
    $eventTrigger.Enabled = $true
    $logonTrigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $logonTrigger.Delay = $def.LogonDelay
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    $task = New-ScheduledTask -Action $taskAction -Trigger @($eventTrigger, $logonTrigger) -Principal $principal -Settings $settings -Description 'PC Optimizer: after Windows Update, check whether settings of the tool were changed back (reads only).'
    Register-ScheduledTask -TaskName $TaskName -InputObject $task -Force -ErrorAction Stop | Out-Null
} catch { Write-Host ('   [FAILED] ' + $_.Exception.Message); exit 1 }
if ($null -eq (Get-DriftTask)) { Write-Host '   [FAILED] The entry was not created.'; exit 1 }
Write-Host '   [OK] The check after Windows Update is on: after an update and two minutes after you sign in. It only reads and tells you.'
exit 0
