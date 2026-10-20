# Creates an empty VirtualBox virtual machine for testing the tool (Windows 11: EFI, TPM 2.0, Secure Boot, 8 GB RAM, 4 CPUs, 80 GB disk that grows as needed).
# It does NOT install Windows: the Windows setup starts when you start the VM, and you accept the Windows license yourself.
#   powershell -File tests\vm\Create_Test_VM.ps1 -Iso "C:\path\Windows11.iso" [-Name "test win11"] [-BaseFolder E:\VirtualBox] [-EditionDir E:\win11-optimizer-vm-test]
#   -DryRun   print the VBoxManage commands and change nothing
param(
    [Parameter(Mandatory = $true)][string]$Iso,
    [string]$Name = 'test win11',
    [string]$BaseFolder = 'E:\VirtualBox',
    [string]$EditionDir = 'E:\win11-optimizer-vm-test',
    [int]$MemoryMB = 8192,
    [int]$Cpus = 4,
    [int]$DiskGB = 80,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$vbm = $null
foreach ($c in 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe', 'C:\Program Files (x86)\Oracle\VirtualBox\VBoxManage.exe') { if (Test-Path -LiteralPath $c) { $vbm = $c; break } }
if ($null -eq $vbm) { $g = Get-Command VBoxManage -ErrorAction SilentlyContinue; if ($g) { $vbm = $g.Source } }
if ($null -eq $vbm -and -not $DryRun) { throw 'VirtualBox was not found (VBoxManage.exe).' }
if ($null -eq $vbm) { $vbm = 'VBoxManage' }
if (-not $DryRun -and -not (Test-Path -LiteralPath $Iso)) { throw ('The ISO file was not found: ' + $Iso) }

$vmDir = [IO.Path]::Combine($BaseFolder, $Name)   # not Join-Path: it fails for a drive that is not there (dry run on another PC)
$disk = [IO.Path]::Combine($vmDir, $Name + '.vdi')
$additions = 'C:\Program Files\Oracle\VirtualBox\VBoxGuestAdditions.iso'
$reports = [IO.Path]::Combine($EditionDir, '_reports')

function Vbm([string[]]$VbmArgs, [switch]$Optional) {
    Write-Host ('  VBoxManage ' + (($VbmArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')) -ForegroundColor DarkGray
    if ($DryRun) { return }
    & $vbm @VbmArgs
    if ($LASTEXITCODE -ne 0) {
        if ($Optional) { Write-Host '    (this step failed, it is optional: continuing)' -ForegroundColor Yellow }
        else { throw ('VBoxManage failed (exit ' + $LASTEXITCODE + ')') }
    }
}

if (-not $DryRun) {
    $existing = (& $vbm list vms) -join "`n"
    if ($existing -match ('"' + [regex]::Escape($Name) + '"')) { throw ('A virtual machine named "' + $Name + '" already exists. Pick another -Name.') }
    if (Test-Path -LiteralPath $disk) { throw ('The disk file already exists: ' + $disk) }
}

Write-Host ('Creating the virtual machine "' + $Name + '" in ' + $vmDir) -ForegroundColor Cyan
Vbm @('createvm', '--name', $Name, '--basefolder', $BaseFolder, '--ostype', 'Windows11_64', '--register')
Vbm @('modifyvm', $Name, '--memory', [string]$MemoryMB, '--cpus', [string]$Cpus, '--vram', '128', '--graphicscontroller', 'vboxsvga',
    '--firmware', 'efi', '--tpm-type', '2.0', '--nic1', 'nat', '--audio-driver', 'none',
    '--clipboard-mode', 'bidirectional', '--draganddrop', 'bidirectional', '--boot1', 'dvd', '--boot2', 'disk', '--boot3', 'none', '--boot4', 'none')
# Secure Boot keys (Windows 11 asks for a Secure Boot capable machine)
Vbm @('modifynvram', $Name, 'inituefivarstore') -Optional
Vbm @('modifynvram', $Name, 'enrollmssignatures') -Optional
Vbm @('modifynvram', $Name, 'enrollorclpk') -Optional

Vbm @('createmedium', 'disk', '--filename', $disk, '--size', [string]($DiskGB * 1024), '--format', 'VDI', '--variant', 'Standard')
Vbm @('storagectl', $Name, '--name', 'SATA', '--add', 'sata', '--controller', 'IntelAhci', '--portcount', '3', '--bootable', 'on')
Vbm @('storageattach', $Name, '--storagectl', 'SATA', '--port', '0', '--device', '0', '--type', 'hdd', '--medium', $disk)
Vbm @('storageattach', $Name, '--storagectl', 'SATA', '--port', '1', '--device', '0', '--type', 'dvddrive', '--medium', $Iso)
if ($DryRun -or (Test-Path -LiteralPath $additions)) {
    Vbm @('storageattach', $Name, '--storagectl', 'SATA', '--port', '2', '--device', '0', '--type', 'dvddrive', '--medium', $additions) -Optional
}

# shared folders: the tool (read only) and a folder for the reports (read and write)
if ($DryRun -or (Test-Path -LiteralPath $EditionDir)) {
    if (-not $DryRun) { New-Item -ItemType Directory -Path $reports -Force -ErrorAction SilentlyContinue | Out-Null }
    Vbm @('sharedfolder', 'add', $Name, '--name', 'optimizer', '--hostpath', $EditionDir, '--readonly', '--automount') -Optional
    Vbm @('sharedfolder', 'add', $Name, '--name', 'reports', '--hostpath', $reports, '--automount') -Optional
}

Write-Host ''
Write-Host 'Done. Next:' -ForegroundColor Green
Write-Host '  1. Start the VM and install Windows (you accept the license). The Windows ISO is already in the drive.'
Write-Host '  2. After Windows is installed, in the VM menu Devices, Insert Guest Additions CD image (or open the CD drive) and run VBoxWindowsAdditions.exe, then restart the VM.'
Write-Host '     The shared folders "optimizer" and "reports" then appear in the VM (\\VBoxSvr\optimizer and \\VBoxSvr\reports).'
Write-Host '  3. Take a snapshot called "01 clean Windows", then run Run_VM_Tests (Run as Administrator).bat from the "optimizer" folder.'
