# Runs the same auth sources/tests in isolation on Windows, without Apple SwiftUI targets.
$ErrorActionPreference = 'Stop'
$authRepo = Split-Path $PSScriptRoot -Parent
$authScratch = Join-Path $authRepo '.build/chatgpt-auth-verification'
$authDrive = [System.IO.DriveInfo]::new([System.IO.Path]::GetPathRoot($authRepo))
if ($authDrive.AvailableFreeSpace -lt 20GB) {
    throw 'Less than 20 GB free. Remove only this task''s known disposable artifacts before testing; preserve reusable caches.'
}
New-Item -ItemType Directory -Path (Join-Path $authScratch 'Sources/ChatGPTAuth') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $authScratch 'Tests/ChatGPTAuthTests') -Force | Out-Null
# Refresh only the generated source copies, retaining the incremental build cache.
foreach ($authSubdir in @('Sources/ChatGPTAuth', 'Tests/ChatGPTAuthTests')) {
    $authCopyPath = [System.IO.Path]::GetFullPath((Join-Path $authScratch $authSubdir))
    $authBoundary = [System.IO.Path]::GetFullPath($authScratch) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $authCopyPath.StartsWith($authBoundary, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe auth copy path.' }
    Get-ChildItem -LiteralPath $authCopyPath -Filter '*.swift' -File | Remove-Item -Force
}
Copy-Item -Path (Join-Path $authRepo 'Sources/ChatGPTAuth/*.swift') -Destination (Join-Path $authScratch 'Sources/ChatGPTAuth')
Copy-Item -Path (Join-Path $authRepo 'Tests/ChatGPTAuthTests/*.swift') -Destination (Join-Path $authScratch 'Tests/ChatGPTAuthTests')
@'
// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "ChatGPTAuthVerification", targets: [
    .target(name: "ChatGPTAuth"),
    .testTarget(name: "ChatGPTAuthTests", dependencies: ["ChatGPTAuth"])
])
'@ | Set-Content -LiteralPath (Join-Path $authScratch 'Package.swift') -Encoding utf8
& swift test --package-path $authScratch
if ($LASTEXITCODE -ne 0) { throw "ChatGPT auth verification failed with exit code $LASTEXITCODE" }
