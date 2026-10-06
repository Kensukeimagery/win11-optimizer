# Shared rules for PC_Health.ps1 and PC_Specs.ps1: pure functions that turn a measured value into a plain-words hint.
# Nothing here reads or changes the PC.

function Get-RamHint([int]$RunningMhz, [int]$RatedMhz, [int]$Modules) {
    $out = @()
    if ($RatedMhz -gt 0 -and $RunningMhz -gt 0 -and $RunningMhz -lt ($RatedMhz * 0.9)) {
        $out += ('the RAM runs at ' + $RunningMhz + ' MT/s but the modules are rated for ' + $RatedMhz + '. XMP / EXPO is probably off in the BIOS; turning it on is free speed for games')
    }
    if ($Modules -eq 1) { $out += 'only one RAM module is installed (single channel). Two matching modules usually give more memory bandwidth' }
    return $out
}

function Get-LanHint([string]$Description, [double]$Mbps) {
    # An adapter that says Gigabit but links at 100 Mbps or less: cable, port or router.
    if ($Description -match 'GbE|Gigabit|1000|2\.5G|2\.5 G' -and $Mbps -gt 0 -and $Mbps -le 100) {
        return ('the adapter supports Gigabit but the link is only ' + $Mbps + ' Mbps. Try another cable (Cat5e or better) or another router port')
    }
    return ''
}

function Get-RefreshHint([int]$Current, [int]$Max) {
    if ($Max -gt 0 -and $Current -gt 0 -and $Current -lt ($Max - 1)) {
        return ('Windows uses ' + $Current + ' Hz but this screen supports ' + $Max + ' Hz at this resolution. Settings > System > Display > Advanced display (some laptops lower it on purpose to save battery)')
    }
    return ''
}
