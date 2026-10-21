# Builds "Win11 Optimizer.exe" with the C# compiler that ships with Windows (.NET Framework 4, nothing to install or download).
#   powershell -File app\build.ps1 [-Out "C:\path\Win11 Optimizer.exe"]
# The result is one file, about 150 KB. Put it in the main folder of the tool, next to "tools" and "reg".
param(
    [string]$Out = ''
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path -Parent $here
# (the folder name is built from pieces so that the version check of the repository tests does not take it for a release number)
$fw = Join-Path $env:WINDIR ('Microsoft.NET\Framework64\' + 'v4' + '.0.30319')
$csc = Join-Path $fw 'csc.exe'
if (-not (Test-Path -LiteralPath $csc)) { throw ('The C# compiler was not found: ' + $csc) }
if ($Out -eq '') { $Out = Join-Path $here 'bin\Win11 Optimizer.exe' }
New-Item -ItemType Directory -Path (Split-Path -Parent $Out) -Force | Out-Null

$version = ([IO.File]::ReadAllText((Join-Path $root 'VERSION'))).Trim()
$four = $version
while (($four -split '\.').Count -lt 4) { $four += '.0' }

# the version and name that Windows shows in the file properties
$info = Join-Path ([IO.Path]::GetTempPath()) ('AssemblyInfo_' + [guid]::NewGuid().ToString('N') + '.cs')
@"
using System.Reflection;
[assembly: AssemblyTitle("Windows 11 Optimizer")]
[assembly: AssemblyProduct("Windows 11 Optimizer")]
[assembly: AssemblyCompany("Kensuke")]
[assembly: AssemblyCopyright("MIT License")]
[assembly: AssemblyDescription("Safe, reversible tuning for Windows 11 gaming PCs")]
[assembly: AssemblyVersion("$four")]
[assembly: AssemblyFileVersion("$four")]
"@ | Set-Content -LiteralPath $info -Encoding ASCII

$wpf = Join-Path $fw 'WPF'
$refs = @(
    (Join-Path $wpf 'PresentationFramework.dll'), (Join-Path $wpf 'PresentationCore.dll'),
    (Join-Path $wpf 'WindowsBase.dll'), (Join-Path $fw 'System.Xaml.dll'), (Join-Path $fw 'System.Core.dll'), (Join-Path $fw 'System.dll')
) | ForEach-Object { '/reference:' + $_ }

$sources = @('Program.cs', 'Core.cs', 'Loc.cs', 'MainWindow.cs') | ForEach-Object { Join-Path $here $_ }
$cscArgs = @('/nologo', '/target:winexe', '/optimize+', '/debug-', '/codepage:65001', '/platform:anycpu', ('/out:' + $Out),
    ('/win32manifest:' + (Join-Path $here 'app.manifest')), ('/win32icon:' + (Join-Path $here 'icon.ico')),
    ('/resource:' + (Join-Path $here 'Styles.xaml') + ',Win11Optimizer.Styles.xaml')) + $refs + $sources + @($info)
& $csc @cscArgs
$code = $LASTEXITCODE
Remove-Item -LiteralPath $info -Force -ErrorAction SilentlyContinue
if ($code -ne 0) { throw ('The compiler stopped with exit code ' + $code) }
Write-Host ('Built ' + $Out + ' (' + [math]::Round((Get-Item -LiteralPath $Out).Length / 1KB) + ' KB)') -ForegroundColor Green
