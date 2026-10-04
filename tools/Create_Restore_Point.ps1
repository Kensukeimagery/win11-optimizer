# PC Optimizer v4.7 - creates a restore point with a time limit. The default name is "Before_PC_Optimizer",
# which 2_Revert_Everything looks for. Other tools pass their own -Description so they never take that name.
# Exit codes: 0 = created, 1 = failed, 2 = timed out.
param([int]$TimeoutSeconds = 600, [string]$Description = 'Before_PC_Optimizer')
$ErrorActionPreference = 'Continue'

$job = Start-Job -ArgumentList $Description, ($env:SystemDrive + '\') -ScriptBlock {
    param($Name, $Drive)
    try {
        Enable-ComputerRestore -Drive $Drive -ErrorAction SilentlyContinue
        $rk = 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        New-ItemProperty -Path $rk -Name 'SystemRestorePointCreationFrequency' -Value 0 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
        Checkpoint-Computer -Description $Name -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
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
