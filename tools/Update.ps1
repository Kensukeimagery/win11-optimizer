# PC Optimizer - updater
# Looks for a newer release on GitHub and, ONLY if you say yes, installs it over this folder.
# Nothing is downloaded or changed without your choice. Your Backup folder, logs and reports are never touched,
# and the old version is moved to Backup\update_<old version>_<time> so you can go back.
#   -Action Run    ask, show what is new, and update if you choose (default)
#   -Action Check  quiet check for the menu: prints one line if a new version exists
#   -Action Apply  internal step started by Run after the menu has closed
# Exit codes: 0 = nothing to do or an error was reported, 10 = an update was started (close the menu window).
param(
    [ValidateSet('Run', 'Check', 'Apply')][string]$Action = 'Run',
    [string]$Root = '',
    [switch]$Quiet,
    [string]$Staged = '',
    [string]$BackupDir = '',
    [int]$WaitPid = 0,
    [string]$NewVersion = '',
    [string]$WorkDir = '',
    [switch]$Relaunch
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

$Repo = 'Kensukeimagery/win11-optimizer'
$ApiUrl = 'https://api.github.com/repos/' + $Repo + '/releases/latest'
$AllowedPrefix = 'https://github.com/' + $Repo + '/releases/download/'
$StateKey = 'HKCU:\Software\PCOptimizer'
$ManagedDirs = @('reg', 'reg_undo', 'tools', 'docs', 'repair-tools')
$ManagedFiles = @('README.md', 'CHANGELOG.md', 'LICENSE', 'VERSION')

if ($Root -eq '') { $Root = Split-Path -Parent $PSScriptRoot }
$Root = (Resolve-Path -LiteralPath $Root).Path

function Say([string]$Text, [string]$Color = 'Gray') { Write-Host $Text -ForegroundColor $Color }

function Get-LocalVersion {
    try {
        $raw = ([IO.File]::ReadAllText((Join-Path $Root 'VERSION'))).Trim()
        return [version]$raw
    } catch { return [version]'0.0' }
}

function Get-SkippedVersion {
    try { return [string](Get-ItemProperty -Path $StateKey -Name 'SkipVersion' -ErrorAction Stop).SkipVersion } catch { return '' }
}

function Get-LatestRelease {
    $headers = @{ 'User-Agent' = 'win11-optimizer-updater'; 'Accept' = 'application/vnd.github+json' }
    $rel = Invoke-RestMethod -Uri $ApiUrl -Headers $headers -TimeoutSec 8
    $tag = [string]$rel.tag_name
    $ver = [version]($tag.TrimStart('v', 'V'))
    $zip = $rel.assets | Where-Object { $_.name -eq 'win11-optimizer.zip' } | Select-Object -First 1
    $sha = $rel.assets | Where-Object { $_.name -eq 'win11-optimizer.zip.sha256' } | Select-Object -First 1
    return [pscustomobject]@{
        Version = $ver; Tag = $tag; Notes = [string]$rel.body; Page = [string]$rel.html_url
        ZipUrl = $(if ($zip) { [string]$zip.browser_download_url } else { '' }); ZipSize = $(if ($zip) { [int64]$zip.size } else { 0 })
        ShaUrl = $(if ($sha) { [string]$sha.browser_download_url } else { '' })
    }
}

function Read-Answer([string]$Prompt, [string[]]$Allowed) {
    while ($true) {
        $a = ([string](Read-Host $Prompt)).Trim().ToUpper()
        if ($a -eq '') { $a = $Allowed[0] }
        if ($Allowed -contains $a) { return $a }
        Say ('   Please type one of: ' + ($Allowed -join ', ')) 'DarkYellow'
    }
}

function Test-ZipEntries([string]$ZipPath) {
    # Refuse a ZIP that tries to write outside the folder it is extracted to.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        foreach ($e in $z.Entries) {
            $n = $e.FullName
            if ($n.Contains('..') -or $n.StartsWith('/') -or $n.StartsWith('\') -or $n.Contains(':')) { return $false }
        }
    } finally { $z.Dispose() }
    return $true
}

# ---------------------------------------------------------------- Check (quiet, for the menu)
if ($Action -eq 'Check') {
    try {
        $local = Get-LocalVersion
        $latest = Get-LatestRelease
        if ($latest.Version -gt $local -and (Get-SkippedVersion) -ne $latest.Version.ToString()) {
            Write-Output ('Update available: ' + $latest.Tag + ', you have v' + $local + '. Press U in the menu to see what is new.')
            exit 10
        }
    } catch { }
    exit 0
}

# ---------------------------------------------------------------- Apply (runs after the menu window closed)
if ($Action -eq 'Apply') {
    $log = Join-Path $Root ('UpdateLog_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.txt')
    function Log([string]$Text, [string]$Color = 'Gray') { Say $Text $Color; try { Add-Content -LiteralPath $log -Value $Text -Encoding ASCII } catch { } }
    Log '=================================================================' 'Cyan'
    Log '   PC OPTIMIZER - UPDATING. Please do not close this window.' 'Cyan'
    Log '=================================================================' 'Cyan'
    if ($WaitPid -gt 0) {
        Log '   Waiting for the menu window to close...'
        try { Wait-Process -Id $WaitPid -Timeout 60 } catch { }
    }
    $moved = New-Object System.Collections.Generic.List[string]
    $ok = $false
    try {
        if (-not (Test-Path -LiteralPath (Join-Path $Staged 'VERSION'))) { throw 'The downloaded files are incomplete.' }
        New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
        $items = New-Object System.Collections.Generic.List[string]
        foreach ($d in $ManagedDirs) { if (Test-Path -LiteralPath (Join-Path $Root $d)) { $items.Add($d) } }
        foreach ($f in $ManagedFiles) { if (Test-Path -LiteralPath (Join-Path $Root $f)) { $items.Add($f) } }
        foreach ($b in @(Get-ChildItem -LiteralPath $Root -File -Filter '*.bat')) { $items.Add($b.Name) }
        # Anything the new version is about to overwrite is saved too, so a rollback never loses a file.
        foreach ($child in @(Get-ChildItem -LiteralPath $Staged -Force)) {
            if ($child.Name -ne 'Backup' -and -not $items.Contains($child.Name) -and (Test-Path -LiteralPath (Join-Path $Root $child.Name))) { $items.Add($child.Name) }
        }
        Log ('   Saving the current version to ' + (Split-Path -Leaf $BackupDir) + ' ...')
        foreach ($name in $items) {
            Move-Item -LiteralPath (Join-Path $Root $name) -Destination (Join-Path $BackupDir $name) -Force
            $moved.Add($name)
        }
        Log '   Installing the new version ...'
        foreach ($child in @(Get-ChildItem -LiteralPath $Staged -Force)) {
            Copy-Item -LiteralPath $child.FullName -Destination (Join-Path $Root $child.Name) -Recurse -Force
        }
        $now = ([IO.File]::ReadAllText((Join-Path $Root 'VERSION'))).Trim()
        $hasMaster = @(Get-ChildItem -LiteralPath $Root -File -Filter '1_Start_Here*.bat').Count -gt 0
        if ($now -ne $NewVersion -or -not $hasMaster) { throw 'The new files did not pass the final check.' }
        $ok = $true
    } catch {
        Log ('   [FAILED] ' + $_.Exception.Message) 'Red'
        Log '   Putting the old version back ...' 'Yellow'
        try {
            foreach ($child in @(Get-ChildItem -LiteralPath $Staged -Force)) {
                $target = Join-Path $Root $child.Name
                if (Test-Path -LiteralPath $target -PathType Container) { [IO.Directory]::Delete($target, $true) }
                elseif (Test-Path -LiteralPath $target -PathType Leaf) { [IO.File]::Delete($target) }
            }
            foreach ($name in $moved) { Move-Item -LiteralPath (Join-Path $BackupDir $name) -Destination (Join-Path $Root $name) -Force }
            Log '   [OK] The old version is back. Nothing was lost.' 'Green'
        } catch { Log ('   [ERROR] Could not restore automatically: ' + $_.Exception.Message + ' Your old files are in ' + $BackupDir) 'Red' }
    }
    if ($ok) {
        Log ('   [OK] Updated to v' + $NewVersion + '. The old version is saved in Backup\' + (Split-Path -Leaf $BackupDir)) 'Green'
        Log '   Your Backup folder, logs and reports were not touched.' 'DarkGray'
    }
    try { if ($WorkDir -ne '' -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) } } catch { }
    if ($ok -and $Relaunch) {
        $master = Get-ChildItem -LiteralPath $Root -File -Filter '1_Start_Here*.bat' | Select-Object -First 1
        if ($master) {
            Log '   Reopening the menu ...' 'DarkGray'
            Start-Sleep -Seconds 2
            Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', 'start', '""', ('"' + $master.FullName + '"')) | Out-Null
            exit 0
        }
    }
    [void](Read-Host '   Press Enter to close this window')
    exit 0
}

# ---------------------------------------------------------------- Run (interactive)
$local = Get-LocalVersion
Say ''
Say '=================================================================' 'Cyan'
Say '   PC OPTIMIZER - CHECK FOR UPDATES' 'Cyan'
Say '=================================================================' 'Cyan'
Say ('   Your version: v' + $local) 'White'
Say '   Contacting github.com (nothing about you is sent) ...' 'DarkGray'
try {
    $latest = Get-LatestRelease
} catch {
    Say '   Could not reach GitHub. Check your internet connection and try again later.' 'Yellow'
    exit 0
}
if ($latest.Version -le $local) {
    Say ('   You are up to date (' + $latest.Tag + ' is the newest).') 'Green'
    exit 0
}
Say ('   New version: ' + $latest.Tag) 'Yellow'
Say ''
Say '   What is new:' 'White'
$lines = @($latest.Notes -split "`r?`n" | Select-Object -First 25)
foreach ($l in $lines) { Say ('     ' + $l) }
Say ''
Say '   U = update now (the old version is saved first and you can go back)' 'White'
Say '   N = not now (default)' 'White'
Say '   S = skip this version (do not ask again until a newer one appears)' 'White'
Say '   L = open the release page in my browser' 'White'
$a = Read-Answer '   Your choice (Enter = N)' @('N', 'U', 'S', 'L')
if ($a -eq 'N') { Say '   Nothing was changed.' 'DarkGray'; exit 0 }
if ($a -eq 'S') {
    if (-not (Test-Path $StateKey)) { New-Item -Path $StateKey -Force | Out-Null }
    New-ItemProperty -Path $StateKey -Name 'SkipVersion' -Value $latest.Version.ToString() -PropertyType String -Force | Out-Null
    Say ('   OK. You will not be asked about ' + $latest.Tag + ' again.') 'DarkGray'
    exit 0
}
if ($a -eq 'L') { Start-Process $latest.Page; exit 0 }

# U: download, check, stage
if ($latest.ZipUrl -eq '' -or -not $latest.ZipUrl.StartsWith($AllowedPrefix)) {
    Say '   This release has no download file the updater trusts. Use the release page instead.' 'Red'
    exit 0
}
if ($latest.ShaUrl -eq '' -or -not $latest.ShaUrl.StartsWith($AllowedPrefix)) {
    Say '   This release has no checksum file, so the updater will not install it. Download it from the release page instead.' 'Red'
    exit 0
}
$work = Join-Path $env:TEMP ('pcopt_update_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
try {
    Say '   Downloading ...' 'DarkGray'
    $zipPath = Join-Path $work 'update.zip'
    Invoke-WebRequest -Uri $latest.ZipUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 120
    $shaText = (Invoke-WebRequest -Uri $latest.ShaUrl -UseBasicParsing -TimeoutSec 30).Content
    if ($shaText -is [byte[]]) { $shaText = [Text.Encoding]::ASCII.GetString($shaText) }
    $expected = ([string]$shaText).Trim().Split(' ')[0].ToLower()
    $actual = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLower()
    if ((Get-Item -LiteralPath $zipPath).Length -ne $latest.ZipSize) { throw 'The download size does not match GitHub.' }
    if ($expected -ne $actual) { throw 'The download does not match its checksum, so it was discarded.' }
    Say '   [OK] Download verified (SHA-256 matches).' 'Green'
    if (-not (Test-ZipEntries $zipPath)) { throw 'The ZIP contains unsafe paths, so it was discarded.' }
    $x = Join-Path $work 'x'
    Expand-Archive -LiteralPath $zipPath -DestinationPath $x -Force
    $stagedRoot = $x
    if (-not (Test-Path -LiteralPath (Join-Path $x 'VERSION'))) {
        $sub = Get-ChildItem -LiteralPath $x -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'VERSION') } | Select-Object -First 1
        if ($sub) { $stagedRoot = $sub.FullName }
    }
    $stagedVersion = ''
    try { $stagedVersion = ([IO.File]::ReadAllText((Join-Path $stagedRoot 'VERSION'))).Trim() } catch { }
    if ($stagedVersion -ne $latest.Version.ToString()) { throw ('The package says version "' + $stagedVersion + '", expected ' + $latest.Version + '.') }
    if (@(Get-ChildItem -LiteralPath $stagedRoot -File -Filter '1_Start_Here*.bat').Count -eq 0 -or -not (Test-Path -LiteralPath (Join-Path $stagedRoot 'tools\Update.ps1'))) { throw 'The package is missing required files.' }
} catch {
    Say ('   [FAILED] ' + $_.Exception.Message + ' Nothing was changed.') 'Red'
    try { [IO.Directory]::Delete($work, $true) } catch { }
    exit 0
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backup = Join-Path $Root ('Backup\update_' + $local + '_' + $stamp)
$helper = Join-Path $env:TEMP ('pcopt_update_apply_' + [guid]::NewGuid().ToString('N') + '.ps1')
Copy-Item -LiteralPath $PSCommandPath -Destination $helper -Force
$parentPid = 0
try {
    $me = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $PID)
    $par = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$me.ParentProcessId)
    # Only wait for the batch window that started us (cmd.exe), never for an interactive PowerShell console.
    if ($par -and $par.Name -ieq 'cmd.exe') { $parentPid = [int]$par.ProcessId }
} catch { }
$argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $helper + '"'), '-Action', 'Apply',
    '-Root', ('"' + $Root + '"'), '-Staged', ('"' + $stagedRoot + '"'), '-BackupDir', ('"' + $backup + '"'),
    '-NewVersion', $latest.Version.ToString(), '-WorkDir', ('"' + $work + '"'), '-WaitPid', [string]$parentPid)
if ($Relaunch) { $argList += '-Relaunch' }
Say ''
Say '   The update finishes in a new window after this one closes. Do not start anything meanwhile.' 'White'
Start-Process -FilePath 'powershell.exe' -ArgumentList $argList | Out-Null
exit 10
