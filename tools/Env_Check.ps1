# PC Optimizer - environment check (read-only)
# Prints two numbers for the main menu: the Windows build number and 1 if this looks like a laptop, else 0.
#   Example output:  26200 0
# -Human prints a readable summary instead.
param([switch]$Human)

$ErrorActionPreference = 'SilentlyContinue'

$build = 0
try { $build = [int](Get-CimInstance Win32_OperatingSystem).BuildNumber } catch { }

# Chassis types that mean "portable": 8 Portable, 9 Laptop, 10 Notebook, 11 Handheld, 12 Docking Station,
# 14 Sub Notebook, 18 Expansion Chassis, 21 Peripheral Chassis, 30 Tablet, 31 Convertible, 32 Detachable.
# Types that mean "desktop": 3 Desktop, 4 Low Profile Desktop, 5 Pizza Box, 6 Mini Tower, 7 Tower,
# 13 All in One, 15 Space-saving, 16 Lunch Box, 23 Rack Mount, 24 Sealed-case PC, 35 Mini PC, 36 Stick PC.
$portable = @(8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32)
$desktop = @(3, 4, 5, 6, 7, 13, 15, 16, 23, 24, 35, 36)
$chassis = @()
try { $chassis = @((Get-CimInstance Win32_SystemEnclosure).ChassisTypes) } catch { }
$hasBattery = $false
try { $hasBattery = (@(Get-CimInstance Win32_Battery).Count -gt 0) } catch { }

$laptop = 0
$reason = 'no sign of a laptop'
if (@($chassis | Where-Object { $portable -contains [int]$_ }).Count -gt 0) {
    $laptop = 1; $reason = 'the case type is portable'
} elseif (@($chassis | Where-Object { $desktop -contains [int]$_ }).Count -gt 0) {
    $laptop = 0; $reason = 'the case type is a desktop (a battery here is probably a UPS)'
} elseif ($hasBattery) {
    $laptop = 1; $reason = 'a battery was found and the case type is unknown'
}

if ($Human) {
    Write-Host ('Windows build: ' + $build + $(if ($build -ge 22000) { ' (Windows 11)' } else { ' (older than Windows 11)' }))
    Write-Host ('Laptop: ' + $(if ($laptop -eq 1) { 'yes' } else { 'no' }) + ' - ' + $reason)
} else {
    Write-Output ([string]$build + ' ' + [string]$laptop)
}
exit 0
