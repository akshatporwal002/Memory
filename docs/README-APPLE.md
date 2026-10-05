# Build and run on Apple platforms

Deployment targets are iOS/iPadOS 17 and macOS 14. Use a Mac with Xcode, installed simulator runtimes and XcodeGen. Physical-device signing requires the user's development configuration. The checked-in [project.yml](../project.yml) and [Package.swift](../Package.swift) define the project and dependencies.

## Build

From the repository root:

```sh
xcodegen generate --spec project.yml
xcodebuild -resolvePackageDependencies -project Engram.xcodeproj -scheme Engram-iOS
xcodebuild -project Engram.xcodeproj -scheme Engram-iOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Engram.xcodeproj -scheme Engram-macOS -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
open Engram.xcodeproj
```

Run `Engram-iOS` with an installed iPhone/iPad simulator, or `Engram-macOS` with My Mac. Discover available simulator names using `xcrun simctl list devices available`. Run a device build only with the appropriate signing/provisioning configuration.

## Tests

```sh
swift test
swift test --package-path Vendor/FSRS
```

For UI tests, select an available simulator and run the shared iOS scheme's test action. DEBUG `--ui-testing` fixtures isolate sample data and simulated responses; they do not verify live account/provider behavior.

## Storage and configuration

The app opens `Application Support/Engram/library.sqlite` in its own container and can migrate the legacy JSON library with a verified recovery copy. Named libraries are isolated by account and selected library. Export each active library to a complete `.engram` backup before removing an app/container or changing production data. Recovery and data migration are implemented in source; check their full platform behavior using disposable test data.

ChatGPT credentials are stored separately in device-only Keychain. Google/Apple/email and hosted sync need provider/backend configuration; `EngramCloudPilotEnabled` remains false by default. A configured endpoint or successful build is not proof of live authentication or two-device synchronization.

## Verification scope

Later repository reports record Apple builds, simulator tests and signed iPhone installations, superseding the [original Windows-only instructions](archive/superseded/README-APPLE.md). No build/tests were rerun for the 5 October documentation cleanup. See [current status](CURRENT-STATUS.md) for evidence and [the backlog](BACKLOG.md#implemented-foundations-needing-configuration-or-acceptance) for remaining accessibility, media, backup, performance, live AI and device/cloud acceptance.
