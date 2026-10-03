# PC Optimizer v4.4 - Network test (read-only: changes nothing on your PC)
# Pings your router, 1.1.1.1, 8.8.8.8 and an optional game server, then shows average ping,
# jitter and packet loss, and says where a problem most likely is.
param(
    [string]$Root = '',
    [string]$Target = '',
    [int]$Count = 30,
    [switch]$NoPrompt
)

$ErrorActionPreference = 'Continue'
$script:Lines = New-Object System.Collections.Generic.List[string]

function Write-Log([string]$Text, [string]$Color = 'Gray') {
    Write-Host $Text -ForegroundColor $Color
    $script:Lines.Add($Text)
}

function Get-GatewayInfo {
    # Default gateway of the connection with the lowest metric, and its connection type.
    $info = @{ Gateway = ''; Type = 'unknown'; Name = '' }
    try {
        $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop | Where-Object { $_.NextHop -ne '0.0.0.0' } | Sort-Object { $_.RouteMetric + $_.InterfaceMetric } | Select-Object -First 1
        if ($null -ne $route) {
            $info.Gateway = [string]$route.NextHop
            $ad = Get-NetAdapter -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue
            if ($null -ne $ad) {
                $info.Name = [string]$ad.Name
                if ($ad.PhysicalMediaType -match '802\.11' -or $ad.InterfaceDescription -match 'Wi-?Fi|Wireless|WLAN') { $info.Type = 'Wi-Fi' }
                elseif ($ad.PhysicalMediaType -match '802\.3' -or $ad.InterfaceDescription -match 'Ethernet|GbE|Gigabit') { $info.Type = 'Ethernet' }
            }
        }
    } catch { }
    return $info
}

function Measure-Host([string]$Address, [int]$Pings) {
    $times = New-Object System.Collections.Generic.List[double]
    $lost = 0
    $ping = New-Object System.Net.NetworkInformation.Ping
    for ($i = 0; $i -lt $Pings; $i++) {
        try {
            $r = $ping.Send($Address, 1000)
            if ($r.Status -eq 'Success') { $times.Add([double]$r.RoundtripTime) } else { $lost++ }
        } catch { $lost++ }
        Start-Sleep -Milliseconds 150
    }
    $res = @{ Address = $Address; Sent = $Pings; Lost = $lost; Avg = $null; Min = $null; Max = $null; Jitter = $null; LossPct = 0 }
    if ($Pings -gt 0) { $res.LossPct = [math]::Round(100.0 * $lost / $Pings, 1) }
    if ($times.Count -gt 0) {
        $res.Avg = [math]::Round((($times | Measure-Object -Average).Average), 1)
        $res.Min = ($times | Measure-Object -Minimum).Minimum
        $res.Max = ($times | Measure-Object -Maximum).Maximum
        if ($times.Count -gt 1) {
            $sum = 0.0
            for ($i = 1; $i -lt $times.Count; $i++) { $sum += [math]::Abs($times[$i] - $times[$i - 1]) }
            $res.Jitter = [math]::Round($sum / ($times.Count - 1), 1)
        } else { $res.Jitter = 0 }
    }
    return $res
}

function Get-Grade($R, [bool]$IsLocal) {
    # Returns 'Good', 'Fair', 'Poor' or 'No reply'
    if ($null -eq $R.Avg) { return 'No reply' }
    $lossBad = 2.0
    $jitFair = 8
    $jitBad = 20
    $avgFair = 60
    $avgBad = 120
    if ($IsLocal) { $jitFair = 4; $jitBad = 12; $avgFair = 8; $avgBad = 20 }
    if ($R.LossPct -ge $lossBad -or $R.Jitter -ge $jitBad -or $R.Avg -ge $avgBad) { return 'Poor' }
    if ($R.LossPct -gt 0 -or $R.Jitter -ge $jitFair -or $R.Avg -ge $avgFair) { return 'Fair' }
    return 'Good'
}

function Get-GradeColor([string]$Grade) {
    switch ($Grade) { 'Good' { return 'Green' } 'Fair' { return 'Yellow' } 'Poor' { return 'Red' } default { return 'DarkYellow' } }
}

function Show-Row($Label, $R, [string]$Grade) {
    $avg = if ($null -eq $R.Avg) { '-' } else { [string]$R.Avg }
    $jit = if ($null -eq $R.Jitter) { '-' } else { [string]$R.Jitter }
    $line = ('  ' + $Label.PadRight(22) + ('avg ' + $avg + ' ms').PadRight(15) + ('jitter ' + $jit + ' ms').PadRight(18) + ('loss ' + $R.LossPct + '%').PadRight(12) + $Grade)
    Write-Log $line (Get-GradeColor $Grade)
}

# ---------------------------------------------------------------- main
if ($Count -lt 5) { $Count = 5 }
if ($Count -gt 200) { $Count = 200 }

Write-Log '==================================================================' 'Cyan'
Write-Log '   PC OPTIMIZER v4.4 - NETWORK TEST (nothing is changed)' 'Cyan'
Write-Log ('   ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')) 'Cyan'
Write-Log '==================================================================' 'Cyan'
Write-Log ''

if ($Target -eq '' -and -not $NoPrompt) {
    Write-Host '   Optional: type a game server address or IP to test it too, or just press Enter to skip.' -ForegroundColor White
    $Target = ([string](Read-Host '   Game server (Enter = skip)')).Trim()
    Write-Host ''
}

$gw = Get-GatewayInfo
if ($gw.Gateway -ne '') {
    Write-Log ('   Connection: ' + $gw.Type + $(if ($gw.Name -ne '') { ' (' + $gw.Name + ')' } else { '' }) + ', router ' + $gw.Gateway) 'White'
} else {
    Write-Log '   Connection: no default router was found. Are you connected to a network?' 'Red'
}
Write-Log ('   Sending ' + $Count + ' pings to each address. This takes about ' + [math]::Ceiling($Count * 0.2 * 3) + ' seconds or more. No key press is needed.') 'DarkGray'
Write-Log '   Note: this sends ordinary ping packets to 1.1.1.1 and 8.8.8.8 (public DNS servers) and to any address you typed.' 'DarkGray'
Write-Log ''

$results = New-Object System.Collections.Generic.List[object]
$targets = New-Object System.Collections.Generic.List[object]
if ($gw.Gateway -ne '') { $targets.Add(@{ Label = 'Router'; Addr = $gw.Gateway; Local = $true }) }
$targets.Add(@{ Label = 'Internet 1.1.1.1'; Addr = '1.1.1.1'; Local = $false })
$targets.Add(@{ Label = 'Internet 8.8.8.8'; Addr = '8.8.8.8'; Local = $false })
if ($Target -ne '') { $targets.Add(@{ Label = ('Game: ' + $Target); Addr = $Target; Local = $false }) }

foreach ($t in $targets) {
    Write-Host ('   Testing ' + $t.Label + ' ...') -ForegroundColor DarkGray
    $r = Measure-Host $t.Addr $Count
    $g = Get-Grade $r $t.Local
    $results.Add(@{ Label = $t.Label; R = $r; Grade = $g; Local = $t.Local })
}

Write-Log ''
Write-Log '   Results' 'White'
foreach ($x in $results) { Show-Row $x.Label $x.R $x.Grade }
Write-Log ''
Write-Log '   Ping = delay. Jitter = how much the delay jumps around (what you feel as rubber-banding).' 'DarkGray'
Write-Log '   Loss = packets that never came back. Local router figures should be very low.' 'DarkGray'
Write-Log ''

# ---------------------------------------------------------------- verdict
$router = $results | Where-Object { $_.Label -eq 'Router' } | Select-Object -First 1
$net = @($results | Where-Object { $_.Label -like 'Internet*' })
$game = $results | Where-Object { $_.Label -like 'Game:*' } | Select-Object -First 1
$netBad = @($net | Where-Object { $_.Grade -eq 'Poor' -or $_.Grade -eq 'No reply' }).Count -eq $net.Count
$netFair = @($net | Where-Object { $_.Grade -ne 'Good' }).Count -gt 0

Write-Log '   What this means' 'White'
if ($gw.Type -eq 'Wi-Fi') {
    Write-Log '   - You are on Wi-Fi. Wi-Fi is the most common cause of ping spikes. A network cable is the single biggest fix.' 'Yellow'
}
if ($null -ne $router -and ($router.Grade -eq 'Poor' -or $router.Grade -eq 'Fair')) {
    Write-Log '   - The problem is already between this PC and your router (Wi-Fi signal, cable, router load or other devices using the network).' 'Yellow'
    Write-Log '     Try a cable, move closer to the router, or pause downloads and streams on other devices, then test again.' 'Gray'
} elseif ($netBad) {
    Write-Log '   - Your router answers well but the internet does not. This points to your internet provider or the line. Restart the router; if it stays like this, contact the provider.' 'Yellow'
} elseif ($netFair) {
    Write-Log '   - The internet shows some jitter or loss even though your router is fine. This is often the provider at busy hours. Test again at another time.' 'Yellow'
} else {
    Write-Log '   - Your router and the internet both look healthy.' 'Green'
}
if ($null -ne $game) {
    if ($game.Grade -eq 'No reply') {
        Write-Log '   - The game server did not answer pings. Many servers block ping, so this does not prove a problem.' 'DarkYellow'
    } elseif (($game.Grade -eq 'Poor' -or $game.Grade -eq 'Fair') -and -not $netFair -and ($null -eq $router -or $router.Grade -eq 'Good')) {
        Write-Log '   - Your own connection is fine but the path to that game server is not. That is the route or the server itself. Nothing on your PC can fix it. Try another server or region.' 'Yellow'
    } elseif ($game.Grade -eq 'Good') {
        Write-Log '   - The path to your game server looks good. If the game still lags, the cause is probably not the network.' 'Green'
    }
}
Write-Log ''
Write-Log '   PC tweaks cannot lower ping by much. A cable, a good router and a nearby server matter far more.' 'DarkGray'

if ($Root -ne '') {
    try {
        $file = Join-Path (Resolve-Path -LiteralPath $Root).Path ('NetworkTest_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.txt')
        [IO.File]::WriteAllLines($file, $script:Lines)
        Write-Host ''
        Write-Host ('   Report saved: ' + (Split-Path -Leaf $file)) -ForegroundColor DarkGray
    } catch { }
}
exit 0
