# Swift test tooling on this Windows host

> Archived on 5 October 2026 from main `381c917`. This is historical context, not current implementation guidance. Outstanding work is tracked in [the backlog](../../BACKLOG.md); newer requirements take precedence.

Setup and verification date: 2026-09-03 (Australia/Sydney).

## Verified result

Official Swift 6.3.3 successfully compiled, linked, and ran a real Swift package. Its Foundation atomic JSON file write/read round-trip XCTest passed (1 test, 0 failures), and its Swift Testing test passed (1 test, 0 failures). `swift test` exited 0. The first smoke build took 34.77 seconds. This verifies the compiler and test environment, not Engram application behavior.

No Apple host, Xcode, Apple SDK, or simulator is available here. Windows tests cannot verify SwiftUI, SwiftData, Apple platform layouts, accessibility or runtime behavior. Those remain Apple build/runtime gates.

## Installed tools

- Host: Windows 11 x64, OS build 10.0.26200.
- Swift: 6.3.3 (`swift-6.3.3-RELEASE`), target `x86_64-unknown-windows-msvc`, assertions enabled.
- Swift binary: `C:\Users\aoswa\AppData\Local\Programs\Swift\Toolchains\6.3.3+Asserts\usr\bin\swift.exe`.
- Swift SDK: `C:\Users\aoswa\AppData\Local\Programs\Swift\Platforms\6.3.3\Windows.platform\Developer\SDKs\Windows.sdk\`.
- Microsoft Visual Studio Build Tools 2022: 17.14.39 (installation version 17.14.37614.0), in `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools`.
- MSVC: 14.44.35207.
- Windows SDK: 10.0.22621.0.
- Swift installer also supplies Python 3.10.1 under its installation root.
- Bundled general Python: `C:\Users\aoswa\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe`, version 3.12.13.

Both installers returned exit 0; neither required a restart. `vswhere` verified a complete, launchable Build Tools installation with `isRebootRequired: false`.

## Reproducible commands on this host

From PowerShell in the Engram repository root, initialize the installed tools and run tests:

```powershell
. .\scripts\Enter-SwiftEnvironment.ps1
swift test
```

The separate toolchain smoke test is reproducible with:

```powershell
. 'C:\Users\aoswa\OneDrive\Documents\ChatGPT\Memory\tooling\Enter-SwiftEnvironment.ps1'
swift test --package-path 'C:\Users\aoswa\OneDrive\Documents\ChatGPT\Memory\tooling\SwiftSmoke'
```

The helper enters Microsoft's x64 developer environment and reads the installed user/machine PATH and SDKROOT. It does not persist environment changes. The Codex filesystem sandbox cannot read this machine's standard user Swift installation directory, so compiler commands in this session require `require_escalated` access. No such sandbox-specific flag is needed in a normal user terminal.

SwiftPM emitted a warning that the `.build/debug` convenience symlink could not be created (I/O code 512); compilation and both test runners completed successfully via the target-specific output directory. Developer Mode has not been changed. Use `swift test` rather than assuming the convenience symlink exists.

Smoke output is retained locally in `tooling/swift-smoke.log`; installers and logs are ignored by Git. The environment helper is included in `scripts/Enter-SwiftEnvironment.ps1`; the separate smoke source remains in the tooling workspace.

## Acquisition evidence

Swift, clang/MSVC, Visual Studio, Docker and usable WSL were initially absent from inspected paths and PATH. `wsl --list --verbose` reported that Windows Subsystem for Linux is not installed. Git and Node.js were already present. Windows Swift was chosen to avoid installing a VM/WSL and requiring a host restart.

The user authorized needed tools. Downloaded Microsoft's official bootstrapper from https://aka.ms/vs/17/release/vs_buildtools.exe; its Authenticode signature was valid and signed by Microsoft Corporation. Installed the host C++ compiler and Windows SDK requirements, without the IDE:

```powershell
Start-Process .\tooling\vs_buildtools.exe -WindowStyle Hidden -Wait -ArgumentList '--quiet','--wait','--norestart','--nocache','--add','Microsoft.VisualStudio.Component.VC.Tools.x86.x64','--add','Microsoft.VisualStudio.Component.Windows11SDK.22621'
```

Downloaded the official Swift x64 installer from https://download.swift.org/swift-6.3.3-release/windows10/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE-windows10.exe. Its Authenticode signature was valid and signed by Apple Inc. SHA-256: `235626548F249CD516D3D4D90EEE980DCCAD46F3822DAC1F8E3119B0FEDE94B7`.

The initial PowerShell transfer failed with a decryption error; `curl.exe --fail --location --retry 3 --continue-at -` resumed it successfully. Signature verification occurred after the complete download and before execution.

```powershell
Start-Process .\tooling\swift-6.3.3.exe -WindowStyle Hidden -Wait -ArgumentList '/install','/quiet','/norestart'
```

## Official references

- https://www.swift.org/install/windows/
- https://www.swift.org/install/windows/manual/
- https://learn.microsoft.com/en-us/visualstudio/install/workload-component-id-vs-build-tools
- https://learn.microsoft.com/en-us/visualstudio/install/use-command-line-parameters-to-install-visual-studio

The Swift manual documents the MSVC and Windows SDK requirements and notes that only the compiler matching the host architecture is essential.
