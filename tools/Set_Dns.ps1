# PC Optimizer v4.9 - DNS helper (optional tweak 17)
# Sets the IPv4 DNS servers of your active physical network adapters, or puts them back.
# The DNS settings you had before are saved first, so Undo restores exactly those
# (including "obtain automatically" if that is what you had).
#   -Action Apply -Servers 1.1.1.1,1.0.0.1 | Undo | Status
#   -DryRun   shows what would change and changes nothing (no administrator rights needed)
# Exit codes: 0 = done, 1 = failed, 2 = not administrator.
param(
    [ValidateSet('Apply', 'Undo', 'Status')][string]$Action = 'Status',
    [string[]]$Servers = @(),
    [string]$Root = '',
    [string]$ResultFile = '',
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'
$StateKey = 'HKCU:\Software\PCOptimizer'

function Out-Result([string]$Text, [string]$Color = 'Gray') {
    Write-Host $Text -ForegroundColor $Color
    if ($ResultFile -ne '') { try { Add-Content -LiteralPath $ResultFile -Value $Text -Encoding ASCII } catch { } }
}

function Test-Admin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-State([string]$Name) {
    try { return [string](Get-ItemProperty -Path $StateKey -Name $Name -ErrorAction Stop).$Name } catch { return '' }
}

function Set-State([string]$Name, [string]$Value) {
    if (-not (Test-Path $StateKey)) { New-Item -Path $StateKey -Force | Out-Null }
    New-ItemProperty -Path $StateKey -Name $Name -Value $Value -PropertyType String -Force | Out-Null
}

function Get-TargetAdapters {
    # Active hardware adapters only: Ethernet and Wi-Fi, not VPN or virtual ones.
    return @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
}

function Test-StaticDns([string]$Guid) {
    # If a NameServer value exists for the adapter, the DNS was typed in by hand.
    try {
        $v = (Get-ItemProperty -Path ('HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\' + $Guid) -Name NameServer -ErrorAction Stop).NameServer
        return (-not [string]::IsNullOrWhiteSpace([string]$v))
    } catch { return $false }
}

function Get-Ipv4Dns([int]$Index) {
    $a = Get-DnsClientServerAddress -InterfaceIndex $Index -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($null -eq $a -or $null -eq $a.ServerAddresses) { return @() }
    return @($a.ServerAddresses)
}

$adapters = Get-TargetAdapters

if ($Action -eq 'Status') {
    if ($adapters.Count -eq 0) { Out-Result '   No active network adapter was found.' 'Yellow'; exit 0 }
    foreach ($ad in $adapters) {
        $kind = 'automatic'
        if (Test-StaticDns ([string]$ad.InterfaceGuid)) { $kind = 'set by hand' }
        Out-Result ('   ' + $ad.Name + ': ' + ((Get-Ipv4Dns $ad.ifIndex) -join ', ') + ' (' + $kind + ')')
    }
    exit 0
}

if (-not $DryRun -and -not (Test-Admin)) {
    Out-Result '   [ERROR] Administrator rights are needed to change DNS servers. Nothing was changed.' 'Red'
    exit 2
}
if ($adapters.Count -eq 0) { Out-Result '   [ERROR] No active network adapter was found. Nothing was changed.' 'Red'; exit 1 }

$backupFile = ''
if ($Root -ne '') { try { $backupFile = Join-Path (Resolve-Path -LiteralPath $Root).Path 'Backup\DNS_before.json' } catch { } }

if ($Action -eq 'Apply') {
    # "-File" passes "1.1.1.1,1.0.0.1" as one string, so split on commas as well
    $valid = @($Servers | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' })
    if ($valid.Count -eq 0) { Out-Result '   [ERROR] No valid DNS server address was given. Nothing was changed.' 'Red'; exit 1 }

    # Keep the ORIGINAL settings. Adapters are only added to an existing backup, never overwritten,
    # so an adapter that appeared after the first change is also restored by Undo.
    $existing = @()
    $oldJson = Get-State 'DnsBackup'
    if ($oldJson -ne '') {
        # Windows PowerShell 5.1 returns the whole JSON array as ONE object, so keep it as it comes and wrap only a single object
        try { $existing = ConvertFrom-Json -InputObject $oldJson; if ($existing -isnot [System.Array]) { $existing = @($existing) } } catch { $existing = @() }
    }
    $known = @($existing | ForEach-Object { [string]$_.Guid })
    $added = @($adapters | Where-Object { $known -notcontains [string]$_.InterfaceGuid } | ForEach-Object { [pscustomobject]@{ Guid = [string]$_.InterfaceGuid; Name = [string]$_.Name; Static = (Test-StaticDns ([string]$_.InterfaceGuid)); Servers = @(Get-Ipv4Dns $_.ifIndex) } })
    if ($added.Count -gt 0) {
        $json = ConvertTo-Json -InputObject @(@($existing) + @($added)) -Compress
        if (-not $DryRun) {
            Set-State 'DnsBackup' $json
            if ($backupFile -ne '') { try { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupFile) | Out-Null; [IO.File]::WriteAllText($backupFile, $json) } catch { } }
        }
    }
    $allOk = $true
    foreach ($ad in $adapters) {
        if ($DryRun) { Out-Result ('   [DRY RUN] ' + $ad.Name + ': would change ' + ((Get-Ipv4Dns $ad.ifIndex) -join ', ') + ' to ' + ($valid -join ', ')); continue }
        try {
            Set-DnsClientServerAddress -InterfaceIndex $ad.ifIndex -ServerAddresses $valid -ErrorAction Stop
            $now = @(Get-Ipv4Dns $ad.ifIndex)
            if (($now -join ',') -eq ($valid -join ',')) { Out-Result ('   [OK] ' + $ad.Name + ': DNS is now ' + ($valid -join ', ')) 'Green' }
            else { Out-Result ('   [FAILED] ' + $ad.Name + ': read back ' + ($now -join ', ')) 'Red'; $allOk = $false }
        } catch { Out-Result ('   [FAILED] ' + $ad.Name + ': ' + $_.Exception.Message) 'Red'; $allOk = $false }
    }
    if ($DryRun) { exit 0 }
    try { Clear-DnsClientCache } catch { }
    if ($allOk) { Set-State 'DnsApplied' ($valid -join ','); Set-State 'Choice_17' 'Y'; exit 0 }
    exit 1
}

# Undo
$json = Get-State 'DnsBackup'
if ($json -eq '' -and $backupFile -ne '' -and (Test-Path -LiteralPath $backupFile)) { $json = [IO.File]::ReadAllText($backupFile) }
if ($json -eq '') {
    Out-Result '   No saved earlier DNS settings were found, so there is nothing to undo here.' 'Yellow'
    exit 0
}
$items = ConvertFrom-Json -InputObject $json
if ($items -isnot [System.Array]) { $items = @($items) }
$allOk = $true
$skippedAny = $false
foreach ($it in $items) {
    $ad = $adapters | Where-Object { [string]$_.InterfaceGuid -eq [string]$it.Guid } | Select-Object -First 1
    if ($null -eq $ad) { Out-Result ('   [SKIPPED] ' + $it.Name + ' is not connected right now. Run Undo again when it is connected.') 'DarkYellow'; $skippedAny = $true; continue }
    $was = 'automatic'
    if ($it.Static) { $was = (@($it.Servers) -join ', ') }
    if ($DryRun) { Out-Result ('   [DRY RUN] ' + $ad.Name + ': would go back to ' + $was); continue }
    try {
        if ($it.Static) { Set-DnsClientServerAddress -InterfaceIndex $ad.ifIndex -ServerAddresses @($it.Servers) -ErrorAction Stop }
        else { Set-DnsClientServerAddress -InterfaceIndex $ad.ifIndex -ResetServerAddresses -ErrorAction Stop }
        Out-Result ('   [OK] ' + $ad.Name + ': DNS is back to ' + $was) 'Green'
    } catch { Out-Result ('   [FAILED] ' + $ad.Name + ': ' + $_.Exception.Message) 'Red'; $allOk = $false }
}
if ($DryRun) { exit 0 }
try { Clear-DnsClientCache } catch { }
if ($allOk -and $skippedAny) {
    Out-Result '   The saved settings were kept so the skipped adapter can be restored later.' 'Yellow'
    exit 1
}
if ($allOk) {
    Remove-ItemProperty -Path $StateKey -Name 'DnsBackup' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $StateKey -Name 'DnsApplied' -ErrorAction SilentlyContinue
    Set-State 'Choice_17' 'N'
    exit 0
}
exit 1
