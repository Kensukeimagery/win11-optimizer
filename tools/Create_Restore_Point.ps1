# PC Optimizer v4.6 - creates the "Before_PC_Optimizer" restore point with a time limit.
# Exit codes: 0 = created, 1 = failed, 2 = timed out.
param([int]$TimeoutSeconds = 600)
$ErrorActionPreference = 'Continue'

$job = Start-Job -ScriptBlock {
    try {
        Enable-ComputerRestore -Drive ($env:SystemDrive + '\') -ErrorAction SilentlyContinue
        $rk = 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        New-ItemProperty -Path $rk -Name 'SystemRestorePointCreationFrequency' -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
        Checkpoint-Computer -Description 'Before_PC_Optimizer' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        'OK'
    } catch {
        'FAIL: ' + $_.Exception.Message
    }
}

if (Wait-Job -Job $job -Timeout $TimeoutSeconds) {
    $result = @(Receive-Job -Job $job)
    Remove-Job -Job $job -Force
    if ($result -contains 'OK') { exit 0 }
    Write-Host ('   ' + ($result -join ' '))
    exit 1
}

Stop-Job -Job $job
Remove-Job -Job $job -Force
exit 2
