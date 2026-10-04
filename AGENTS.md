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
