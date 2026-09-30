# Runs the same auth sources/tests in isolation on Windows, without Apple SwiftUI targets.
$ErrorActionPreference = 'Stop'
$authRepo = Split-Path $PSScriptRoot -Parent
$authScratch = Join-Path $authRepo ('.build/chatgpt-auth-verification-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $authScratch 'Sources/ChatGPTAuth') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $authScratch 'Tests/ChatGPTAuthTests') -Force | Out-Null
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
