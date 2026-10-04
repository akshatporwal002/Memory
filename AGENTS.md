# Project instructions

## Build storage and simulator rules

- Reuse stable build directories. Never create a new DerivedData or Swift scratch directory for every task, commit, retry, or test run.
- Keep at most one reusable build directory per platform/configuration where separate directories are necessary.
- For iOS testing, use the existing iPhone 17 Pro simulator: `E75C5BB1-19D3-4085-9BFA-B296E40DFBE9`.
- For iPad-specific testing, use the existing iPad Pro 13-inch M5: `C9DD5AAC-E456-4648-BCF3-A50DD6D8FFF3`.
- Both simulators use the installed iOS 26.0.1 runtime. Verify their availability before use. Do not create extra devices or download additional runtimes without asking the user. If the app requires a newer runtime, explain that requirement first.
- Preserve these simulators' app data. Do not erase or delete them as routine cleanup.
- After completing and validating a task, remove temporary build folders, exported app bundles, IPA files, archives, copied dependencies, disk images, and staging directories created by that task if they will not be reused or needed as deliverables.
- Preserve the reusable build cache so ordinary incremental builds remain fast. Do not clean it after every build.
- Track temporary artifacts created during the task. Only delete artifacts whose purpose is known; never delete source files, active builds, another task's files, or requested review evidence.
- Before producing an artifact likely to exceed 1 GB, check available disk space and reuse existing outputs where possible. If free space falls below 20 GB, clean this task's disposable artifacts before proceeding. If insufficient space remains, stop and report it rather than deleting unrelated storage.
- Do not install duplicate tooling, simulator runtimes, or dependency environments when a suitable installation already exists.
- Do not clear unrelated app data, Docker volumes, device-support files, or system-managed storage.
- Report substantial temporary storage created or reclaimed when finishing the task.

## Canonical paths and commands

- macOS Debug DerivedData: `<checkout>/.build/xcode`; use `script/build_and_run.sh`.
- iOS Debug DerivedData (physical phone, iPhone simulator and iPad simulator): `/tmp/engram-account-libraries-build`, the existing Mac cache. Use `script/build_ios.sh [build|test] [iphone|ipad|device]`. This path is reusable, not disposable task staging.
- Swift package tests: `<checkout>/.build`, Swift's default. Use `swift test` from the stable checkout; do not add per-run scratch paths.
- Windows isolated auth verification: `<checkout>/.build/chatgpt-auth-verification`, including its reusable `.build` cache. Use `scripts/Test-ChatGPTAuth.ps1`.
- Existing remote validation checkout: `~/Documents/projects/Memory-overnight`. Reuse it for this work; do not copy the repository or its dependencies into a new directory each run.
- `script/build_ios.sh --check [iphone|ipad|device]` validates space and the selected simulator without building, booting, or altering simulator data.
- Keep a task-specific list of disposable outputs and review evidence. Remove only known disposable outputs after validation; do not sweep all of `.build` or `/tmp`. Historical staging copies and another task's scripts are not authority to create additional caches.

## Mac connectivity, signing and phone installation

1. Check `ssh -o ConnectTimeout=10 codex-mac` connectivity before starting remote work. If unreachable, report that blocker; check the current address, Remote Login, VPN/network and whether the Mac is awake. Do not repeatedly rebuild or launch retries against an unreachable Mac. Leave the Mac awake for remote work; do not promise waking a sleeping Mac.
2. Run simulator validation with signing disabled, using the verified existing simulator and canonical cache. Simulator validation does not require an Apple Development private key. An unreachable Mac still blocks local simulation. Do not confuse signing errors with connectivity or simulator errors.
3. For a physical phone, verify the paired device is available with `xcrun devicectl list devices`. If wireless connection fails, prefer a USB connection and request any necessary unlock, trust or Developer Mode interaction. USB does not repair an unreachable Mac or signing failure.
4. Build/sign once using the existing iOS Debug cache. On `errSecInternalComponent` over SSH, do not repeat identical failed builds. Use the proven fallback: launch the same build command in Terminal in the Mac's logged-in desktop session, redirect its output and exit status to known task logs, then inspect those results over SSH. This avoids the SSH signing-session problem; it does not bypass code signing or keychain security.
5. If the local-session build still requires key access, ask the user to unlock the login keychain in Mac Terminal and approve the specific codesign prompt. Never collect, store or embed their password; never broaden key access to all applications or change keychain permissions silently.
6. After a successful signed build, install the existing `.app` with `xcrun devicectl device install app`, then launch `dev.engram.study` and verify success. Reinstalling that unchanged signed output does not require signing again. If source changed, build the new revision first; never describe an older installed build as current.
7. Xcode, Apple Configurator and exported IPA installation still require a valid signature and provisioning profile. There is no supported unsigned-native-app installation fallback for a standard iPhone. Do not disable signing for device builds or strip required entitlements to conceal a capability/provisioning mismatch. Explain missing capabilities such as Sign in with Apple separately.
8. Preserve app data, simulator data and reusable caches. Retain requested review screenshots and concise validation logs; remove only tracked disposable staging/archive outputs after validation. Report precisely whether compilation, signing, installation and launch each succeeded.
