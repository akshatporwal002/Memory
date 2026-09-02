# Initializes the installed Swift and MSVC toolchains for this PowerShell session.
# Dot-source this script before invoking swift build/test.
$ErrorActionPreference = 'Stop'
$toolchainVSWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $toolchainVSWhere)) { throw 'Install Visual Studio C++ Build Tools first.' }
$toolchainVS = & $toolchainVSWhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $toolchainVS) { throw 'No complete Visual Studio x64 C++ Build Tools installation found.' }
& (Join-Path $toolchainVS 'Common7\Tools\Launch-VsDevShell.ps1') -Arch amd64 -HostArch amd64 -SkipAutomaticLocation
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User') + ';' + $env:Path
foreach ($toolchainVar in @('SDKROOT','DEVELOPER_DIR')) {
    $toolchainValue = [Environment]::GetEnvironmentVariable($toolchainVar,'User')
    if (-not $toolchainValue) { $toolchainValue = [Environment]::GetEnvironmentVariable($toolchainVar,'Machine') }
    if ($toolchainValue) { Set-Item -LiteralPath "Env:$toolchainVar" -Value $toolchainValue }
}
if (-not (Get-Command swift -ErrorAction SilentlyContinue)) { throw 'Swift is absent from the installed user/machine PATH. Install the official Windows Swift toolchain.' }
swift --version
