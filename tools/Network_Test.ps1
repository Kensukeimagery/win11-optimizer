# PC Optimizer v4.15 - Network test (read-only: changes nothing on your PC)
# Pings your router, 1.1.1.1, 8.8.8.8 and an optional game server, then shows average ping,
# jitter and packet loss, and says where a problem most likely is.
param(
    [string]$Root = '',
    [string]$Target = '',
    [int]$Count = 30,
    [switch]$NoPrompt,
    [switch]$SkipDns
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'Report_Files.ps1')
$script:Lines = New-Object System.Collections.Generic.List[string]

function Write-Log([string]$Text, [string]$Color = 'Gray') {
    Write-Host $Text -ForegroundColor $Color
    $script:Lines.Add($Text)
}

function Get-GatewayInfo {
    # Default gateway of the connection with the lowest metric, and its connection type.
    $info = @{ Gateway = ''; Type = 'unknown'; Name = ''; Index = 0 }
    try {
        $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop | Where-Object { $_.NextHop -ne '0.0.0.0' } | Sort-Object { $_.RouteMetric + $_.InterfaceMetric } | Select-Object -First 1
        if ($null -ne $route) {
            $info.Gateway = [string]$route.NextHop
            $info.Index = [int]$route.InterfaceIndex
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

function Test-DnsServer([string]$Server, [string]$Name) {
    # Sends one real DNS lookup (A record) straight to $Server and returns the time in ms, or $null if it failed.
    $udp = New-Object System.Net.Sockets.UdpClient
    try {
        $udp.Client.ReceiveTimeout = 1500
        $udp.Connect($Server, 53)
        $id = Get-Random -Minimum 1 -Maximum 65535
        $bytes = New-Object System.Collections.Generic.List[byte]
        $bytes.Add([byte]($id -shr 8)); $bytes.Add([byte]($id -band 255))
        $bytes.AddRange([byte[]](1, 0, 0, 1, 0, 0, 0, 0, 0, 0))
        foreach ($label in $Name.Split('.')) {
            $lb = [Text.Encoding]::ASCII.GetBytes($label)
            $bytes.Add([byte]$lb.Length); $bytes.AddRange($lb)
        }
        $bytes.Add(0); $bytes.AddRange([byte[]](0, 1, 0, 1))
        $arr = $bytes.ToArray()
        $sw = [Diagnostics.Stopwatch]::StartNew()
        [void]$udp.Send($arr, $arr.Length)
        $ep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        $resp = $udp.Receive([ref]$ep)
        $sw.Stop()
        if ($resp.Length -lt 12) { return $null }
        if ((([int]$resp[0] -shl 8) -bor [int]$resp[1]) -ne $id) { return $null }
        $answers = ([int]$resp[6] -shl 8) -bor [int]$resp[7]
        if (([int]$resp[3] -band 15) -ne 0 -or $answers -lt 1) { return $null }
        return [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
    } catch { return $null } finally { $udp.Close() }
}

function Measure-Dns([string]$Server) {
    $domains = @('google.com', 'youtube.com', 'steampowered.com', 'epicgames.com', 'riotgames.com', 'discord.com', 'microsoft.com', 'amazon.com')
    $times = New-Object System.Collections.Generic.List[double]
    $fail = 0
    $total = 0
    for ($round = 0; $round -lt 3; $round++) {
        foreach ($d in $domains) {
            $total++
            $ms = Test-DnsServer $Server $d
            if ($null -eq $ms) { $fail++ } else { $times.Add([double]$ms) }
        }
        if ($round -eq 0 -and $times.Count -eq 0) { break }   # first round all failed: the server does not answer
    }
    $res = @{ Server = $Server; Median = $null; Fail = $fail; Total = $total }
    if ($times.Count -gt 0) {
        $sorted = @($times | Sort-Object)
        $mid = [int][math]::Floor($sorted.Count / 2)
        if ($sorted.Count % 2 -eq 1) { $res.Median = [math]::Round($sorted[$mid], 1) } else { $res.Median = [math]::Round(($sorted[$mid - 1] + $sorted[$mid]) / 2, 1) }
    }
    return $res
}

function Test-IsAdmin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---------------------------------------------------------------- main
if ($Count -lt 5) { $Count = 5 }
if ($Count -gt 200) { $Count = 200 }

Write-Log '==================================================================' 'Cyan'
Write-Log '   PC OPTIMIZER v4.15 - NETWORK TEST (nothing is changed)' 'Cyan'
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

# ---------------------------------------------------------------- DNS
if (-not $SkipDns) {
    Write-Log ''
    Write-Log '   DNS speed (how fast names like steampowered.com are turned into addresses)' 'White'
    Write-Log '   Testing 8 popular sites, 3 times each, on each DNS server. About 10-30 seconds. No key press is needed...' 'DarkGray'
    $current = @()
    if ($gw.Index -gt 0) { try { $current = @((Get-DnsClientServerAddress -InterfaceIndex $gw.Index -AddressFamily IPv4 -ErrorAction Stop).ServerAddresses) } catch { } }
    $presets = @(
        @{ Label = 'Cloudflare 1.1.1.1'; Server = '1.1.1.1'; Key = '1'; Pair = @('1.1.1.1', '1.0.0.1') },
        @{ Label = 'Google 8.8.8.8'; Server = '8.8.8.8'; Key = '2'; Pair = @('8.8.8.8', '8.8.4.4') },
        @{ Label = 'Quad9 9.9.9.9'; Server = '9.9.9.9'; Key = '3'; Pair = @('9.9.9.9', '149.112.112.112') }
    )
    $dnsRes = New-Object System.Collections.Generic.List[object]
    $curServer = ''
    if ($current.Count -gt 0) {
        $curServer = [string]$current[0]
        $curLabel = 'Your current DNS (' + $curServer + ')'
        foreach ($p in $presets) { if ($p.Server -eq $curServer) { $curLabel = 'Your current DNS (' + $curServer + ', ' + $p.Label.Split(' ')[0] + ')' } }
        $dnsRes.Add(@{ Label = $curLabel; Server = $curServer; IsCurrent = $true; Preset = $null; M = (Measure-Dns $curServer) })
    }
    foreach ($p in $presets) {
        if ($p.Server -eq $curServer) { continue }
        $dnsRes.Add(@{ Label = $p.Label; Server = $p.Server; IsCurrent = $false; Preset = $p; M = (Measure-Dns $p.Server) })
    }
    Write-Log ''
    $best = $null
    foreach ($x in $dnsRes) {
        $med = 'no answer'
        if ($null -ne $x.M.Median) { $med = [string]$x.M.Median + ' ms' }
        $failTxt = ''
        if ($x.M.Fail -gt 0) { $failTxt = '(' + $x.M.Fail + ' of ' + $x.M.Total + ' lookups failed)' }
        $color = 'Gray'
        if ($null -eq $x.M.Median) { $color = 'DarkYellow' }
        Write-Log ('  ' + $x.Label.PadRight(44) + ('typical ' + $med).PadRight(22) + $failTxt) $color
        if ($null -ne $x.M.Median -and ($null -eq $best -or $x.M.Median -lt $best.M.Median)) { $best = $x }
    }
    $curRes = $dnsRes | Where-Object { $_.IsCurrent } | Select-Object -First 1
    Write-Log ''
    Write-Log '   What changing DNS would mean' 'White'
    if ($null -ne $best -and $null -ne $curRes -and $null -ne $curRes.M.Median) {
        $gain = [math]::Round($curRes.M.Median - $best.M.Median, 1)
        if ($best.IsCurrent -or $gain -lt 5) {
            Write-Log '   - Your current DNS is already about as fast as the others. Changing it would make no noticeable difference.' 'Green'
        } elseif ($gain -lt 30) {
            Write-Log ('   - ' + $best.Label + ' answers about ' + $gain + ' ms faster. Small: web pages and launchers may start a touch quicker. You will hardly notice it.') 'Yellow'
        } else {
            Write-Log ('   - ' + $best.Label + ' answers about ' + $gain + ' ms faster. This is noticeable when opening sites and launchers.') 'Yellow'
        }
        if ($curRes.M.Fail -gt 0) { Write-Log '   - Some lookups failed on your current DNS. That alone can make sites or game servers fail to load now and then, so switching may help.' 'Yellow' }
    } elseif ($null -ne $curRes) {
        Write-Log '   - Your current DNS did not answer the test lookups. Switching may fix sites that do not load, but check your router and connection first.' 'Yellow'
    } else {
        Write-Log '   - Your current DNS could not be read, so it cannot be compared.' 'DarkYellow'
    }
    Write-Log '   - DNS is used once, when you connect to a site or a game server. It does NOT change your in-game ping or FPS.' 'Gray'
    Write-Log '   - Privacy: the DNS provider you pick sees the names of the sites you visit. Today your current provider sees them. Choose whom you trust.' 'Gray'

    if (-not $NoPrompt) {
        Write-Log ''
        $saved = ''
        try { $saved = [string](Get-ItemProperty -Path 'HKCU:\Software\PCOptimizer' -Name 'DnsBackup' -ErrorAction Stop).DnsBackup } catch { }
        # the backup file next to the scripts counts too, in case the registry copy is gone
        $applied = ''
        try { $applied = [string](Get-ItemProperty -Path 'HKCU:\Software\PCOptimizer' -Name 'DnsApplied' -ErrorAction Stop).DnsApplied } catch { }
        if ($saved -eq '' -and $applied -ne '' -and $Root -ne '') {
            try { if (Test-Path -LiteralPath (Join-Path (Resolve-Path -LiteralPath $Root).Path 'Backup\DNS_before.json')) { $saved = 'file' } } catch { }
        }
        $allowed = New-Object System.Collections.Generic.List[string]
        Write-Host '   Change DNS now? Nothing changes unless you pick a number.' -ForegroundColor White
        foreach ($p in $presets) {
            $row = $dnsRes | Where-Object { $_.Server -eq $p.Server } | Select-Object -First 1
            $note = ''
            if ($null -ne $row -and $null -ne $best -and $row.Server -eq $best.Server) { $note = '  (fastest here)' }
            if ($null -ne $row -and $null -eq $row.M.Median) { $note = '  (did not answer in the test)' }
            if ($p.Server -eq $curServer) { $note += '  (this is what you use now)' }
            Write-Host ('   ' + $p.Key + ' = ' + $p.Label.Split(' ')[0] + ' (' + ($p.Pair -join ', ') + ')' + $note)
            $allowed.Add($p.Key)
        }
        $allowed.Add('N')
        if ($saved -ne '') { Write-Host '   U = put back the DNS I had before my last change'; $allowed.Add('U') }
        Write-Host '   N = keep my current DNS (default)'
        $ans = 'N'
        for ($try = 0; $try -lt 20; $try++) {
            $raw = Read-Host '   Your choice (Enter = N)'
            if ($null -eq $raw) { break }   # input closed: keep the current DNS
            $cand = ([string]$raw).Trim().ToUpper()
            if ($cand -eq '') { $cand = 'N' }
            if ($allowed -contains $cand) { $ans = $cand; break }
            Write-Host ('   Please type one of: ' + ($allowed -join ', ')) -ForegroundColor DarkYellow
        }
        if ($ans -eq 'N') {
            Write-Log '   DNS left as it is.' 'DarkGray'
        } else {
            $helper = Join-Path $PSScriptRoot 'Set_Dns.ps1'
            if (-not (Test-Path -LiteralPath $helper)) {
                Write-Log '   [ERROR] tools\Set_Dns.ps1 was not found, so nothing was changed.' 'Red'
            } else {
                $action = 'Undo'
                $serverArg = ''
                if ($ans -ne 'U') {
                    $action = 'Apply'
                    $pick = $presets | Where-Object { $_.Key -eq $ans } | Select-Object -First 1
                    $serverArg = $pick.Pair -join ','
                }
                $resultFile = Join-Path $env:TEMP ('PCOptimizer_dns_' + [guid]::NewGuid().ToString('N') + '.txt')
                $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $helper + '"'), '-Action', $action, '-ResultFile', ('"' + $resultFile + '"'))
                if ($serverArg -ne '') { $argList += @('-Servers', $serverArg) }
                if ($Root -ne '') { $argList += @('-Root', ('"' + (Resolve-Path -LiteralPath $Root).Path + '"')) }
                try {
                    if (Test-IsAdmin) {
                        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Wait -NoNewWindow
                    } else {
                        Write-Host '   Windows will now ask for administrator permission to change DNS. Choose No to cancel.' -ForegroundColor White
                        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs -Wait -WindowStyle Hidden
                    }
                    if (Test-Path -LiteralPath $resultFile) {
                        foreach ($rl in (Get-Content -LiteralPath $resultFile)) { Write-Log $rl 'Gray' }
                        [IO.File]::Delete($resultFile)
                    } else {
                        Write-Log '   No result was reported. DNS was probably not changed.' 'Yellow'
                    }
                    Write-Log '   Undo any time: run this test again and choose U, or use menu 7 then 17 in 1_Start_Here.' 'DarkGray'
                } catch {
                    Write-Log '   Administrator permission was not given, so DNS was not changed.' 'Yellow'
                }
            }
        }
    }
}

if ($Root -ne '') {
    try {
        $file = New-ReportPath (Resolve-Path -LiteralPath $Root).Path 'NetworkTest'
        [IO.File]::WriteAllLines($file, $script:Lines)
        Remove-OldReports (Resolve-Path -LiteralPath $Root).Path | Out-Null
        Write-Host ''
        Write-Host ('   Report saved: ' + (Split-Path -Leaf $file)) -ForegroundColor DarkGray
    } catch { }
}
exit 0
