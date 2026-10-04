# Provider account controls

## Behavior

- Connected providers show Manage ChatGPT/Google/Apple/Email, based on verified provider identities rather than merely having an Engram session.
- Disconnected providers show Continue with the provider. Google continuation automatically starts verified identity linking when an Engram session already exists. Apple and email retain their existing verified linking workflows.
- Each management page identifies the connection and explains its scope. Removing Google/Apple is confirmed and requires another login identity. Email cannot be removed through this control.
- Engram sign-out is explicitly labelled and affects the shared app session on this device, keeping ChatGPT AI access connected. Supabase sign-out uses local scope rather than logging out other devices.
- Sign out all confirms disconnection of the app session and every stored ChatGPT registration. Saved libraries remain preserved. ChatGPT disconnection from a local ChatGPT library profile returns to the guest library; the original remains saved.
- Generic Connected/Sign out rows and duplicate provider-linked footnotes are removed. Provider controls use the existing themed capsule treatment and adapt within the existing constrained iPad layout.
- AGENTS.md now documents SSH reachability, unsigned simulator validation, physical-device connectivity, the proven local Terminal signing fallback, keychain handoff and verified install/launch.

## Validation

279 Swift package tests passed on the existing Mac checkout; one was skipped. Added regressions for verified-provider labels and durable multi-registration ChatGPT sign-out. No live credentials are used in these tests.

iPhone UI validation was attempted using the existing E75C5BB1-19D3-4085-9BFA-B296E40DFBE9 simulator and `/tmp/engram-account-libraries-build`. Xcode 26.6 rejected simulator destinations with “iOS 26.5 is not installed.” Explicit simulator SDK selection and generic simulator build encountered the same platform eligibility blocker. The installed iOS 26.0.1 runtime and both required simulators remain unchanged; the app deployment target remains iOS 17. No extra runtime or device was created. A compatible existing Xcode/platform installation or user-approved platform repair is needed before screenshots or device deployment can be validated. No current_ui images were replaced with old-build captures. These changes have not been installed on the phone.

The iOS script now finds the existing Homebrew XcodeGen installation in SSH sessions and accepts additional xcodebuild arguments for focused tests. Build caches remain intact. Disposable task transfer archives and error result bundles are removed after validation; logs remain as evidence.

## User-approved runtime upgrade

Installed Apple's arm64 iOS 26.5 runtime, build `23F73` (8.52 GB download). Upgraded the existing iPhone and iPad device IDs using `simctl upgrade`; both completed their first boot. A temporary app-data backup verified that saved Engram libraries and drafts were unchanged, excluding tar-generated AppleDouble metadata entries. Removed that temporary backup after verification.

Removed only the old iOS 26.0.1 runtime through `simctl runtime delete`, reclaiming its approximately 8.04 GB runtime image. No device was erased or recreated. The Mac has approximately 89 GiB free after installation and cleanup; reusable caches remain intact.

Xcode's SDK defaulted to absent runtime build `23F81a`. Mapping `iphoneos26.5` to the verified installed runtime `23F73` restored both simulator destinations. The account-changes iPhone simulator build subsequently succeeded using `/tmp/engram-account-libraries-build`. AGENTS.md and the simulator preflight now require 26.5. Visual UI tests/screenshots and physical-phone installation remain separate validation steps.
