# Engram

Engram is a standalone, local flashcard application being built in native SwiftUI for iPhone, iPad and Mac. The source includes deck management, basic/cloze editing, a durable review loop, FSRS scheduling, Anki package adapters and complete native backups. Core study and import/export have no paid AI dependency.

## Documentation

Project plans, research, architecture, build guides, and review reports live in [`docs/`](docs/README.md). Start with the [documentation index](docs/README.md) to find the relevant guide.

**Status: implemented foundations with outstanding release acceptance.** Later reports include native builds, simulator checks and device installations. See [current status](docs/CURRENT-STATUS.md) for implementation/evidence boundaries and [remaining work](docs/BACKLOG.md) for unfinished features and acceptance gates. Historical test counts are retained in the [archive](docs/archive/README.md).

## Build and run on Apple platforms

Prerequisites: a Mac supported by stable Xcode 26, installed iOS simulator runtimes, and XcodeGen. Deployment targets are iOS/iPadOS 17 and macOS 14. Native system controls use OS26 Liquid Glass when supported; older releases use ordinary system chrome. The configuration is in `project.yml`; the project is generated reproducibly.

From this repository root:

```sh
xcodegen generate --spec project.yml
xcodebuild -resolvePackageDependencies -project Engram.xcodeproj -scheme Engram-iOS
xcodebuild -project Engram.xcodeproj -scheme Engram-iOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Engram.xcodeproj -scheme Engram-macOS -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
open Engram.xcodeproj
```

In Xcode, choose an available iPhone or iPad simulator and Run `Engram-iOS`; choose My Mac and Run `Engram-macOS`. List installed simulator devices with `xcrun simctl list devices available`. Physical-device installation requires the user's own signing configuration. More detail: [README-APPLE.md](docs/README-APPLE.md).

## Run backend tests

The shared Swift package tests scheduling, repositories, import transactions, markup validation, archives and Anki fixtures independently of SwiftUI.

```sh
swift test
```

The pinned scheduler's own suite is separately reproducible with `swift test --package-path Vendor/FSRS`.

On the configured Windows machine, initialize Swift/MSVC first:

```powershell
. .\scripts\Enter-SwiftEnvironment.ps1
swift test
```

The [historical Windows setup](docs/archive/environment/TOOLCHAIN.md) records the earlier Swift/MSVC environment. Current app dependencies include Apple features; use the [Apple build guide](docs/README-APPLE.md) for native verification. Do not treat archived test counts as results for this checkout.

The design contact sheet is a standalone **mockup**, not a web version of Engram:

```sh
node design/previews/build-previews.cjs
```

Open `design/previews/design-preview.html` to review six screen compositions, three layout families, four theme/appearance combinations and enlarged text. The generator checks 72 color pairings directly from the Swift theme definitions. See [DESIGN-HANDOFF.md](docs/archive/superseded/DESIGN-HANDOFF.md).

## Study and storage

Create a deck in Today or Library, then add a basic question/answer or a cloze note. Cloze syntax is `{{c1::answer}}` or `{{c1::answer::hint}}`; each distinct number creates a separately scheduled card. Repeating a number hides those spans together. The editor validates content, supports tags and a manual source field, and provides a preview. Ordinary text edits and moves preserve schedules.

Study shows a question, then an explicit reveal action, then Again/Hard/Good/Easy. The service saves a grade before advancing, rejects stale/duplicate presentations and supports undo. In the review sheet, Space reveals, 1–4 grade, Command-Z undoes and Escape exits. The persisted session can resume after exit/restart. Keyboard behavior still needs native verification.

The app stores account-partitioned data in `Application Support/Engram/library.sqlite` inside its container, with verified migration from legacy JSON. Named libraries and device-only content are supported. Cloud synchronization code exists, but the hosted pilot is disabled pending live device acceptance. See [accounts and libraries](docs/ACCOUNT-AND-LIBRARIES.md) and [architecture](docs/ARCHITECTURE.md). The app limits competing library windows; current large-library performance remains a verification gate.

Use **Import and export → Save complete Engram backup** to save a versioned `.engram` archive outside the app. It contains the whole library and media payloads. Confirmed imports/restores first create a local recovery backup. Deleting the app or losing the device can remove both the active library and local recovery copies; keep an external copy. Restore requires explicit replacement confirmation. If the library cannot open, startup recovery can inspect a complete backup and preserve the unreadable original before confirmed replacement; its backend tests pass, while the Apple UI path remains unverified.

## Anki compatibility

The verified interoperability path uses official Anki **26.08.1**, legacy-compatible **schema11** `.apkg` import/export and `.colpkg` import. Export from Anki with **Support older Anki versions** enabled. Personal transfer includes supported progress; sharing omits personal scheduling/history. Ordinary basic, reversed and cloze content, supported inline formatting, local image/audio references, tags, nested decks and source evidence are supported within the documented subset.

Give each Anki profile a distinct **source name** and reuse it for future imports from that profile. Without a name, external packages use their exact file contents as identity, so changed exports are separate sources; Engram's direct exports carry a stable library identity. Import results report added/updated/kept-or-skipped notes, cards, history and media. Structural conflicts are rejected with an explicit resolution instead of silently duplicating cards or discarding history.

Importing an Anki package directly back into the same Engram library that exported it is blocked, including when a different source name is entered. Anki transfer cannot reconstruct all original native identities and undo evidence safely. Use a complete `.engram` backup and confirmed restore for recovery of that library. Transfers into a different library remain supported.

Modern zstd/protobuf packages, custom CSS/JavaScript templates, image occlusion and other unsupported formats are explicitly rejected. Exact continuation of legacy SM-2 or source learning/relearning/buried/filtered states is not implemented; the user can cancel or explicitly restart eligible content while retaining original evidence. FSRS review-state continuation preserves supported memory/due/history, but future intervals use Engram's documented scheduler policy.

Four Swift-generated package variants were imported into fresh official Anki backend collections and passed semantic comparisons; this is not an Apple UI migration test. See [ANKI-COMPATIBILITY.md](docs/ANKI-COMPATIBILITY.md), [MEDIA-COMPATIBILITY.md](docs/MEDIA-COMPATIBILITY.md), fixture provenance, and `validation/anki-roundtrip-results.json` for exact evidence and limits.

## Architecture and scope

[ARCHITECTURE.md](docs/ARCHITECTURE.md) describes the dependency boundaries and how to replace the theme, scheduler, persistence or format adapter. [ANKI-SOURCE-REVIEW.md](docs/archive/research/ANKI-SOURCE-REVIEW.md) records the inspected upstream revision and behavior map. Pinned FSRS, SQLite and archive-codec provenance/licenses are retained beside their source; Anki's backend is validation tooling, not a shipped application dependency.

Main includes grounded PDF generation, assistant actions, typed feedback, local foreground voice and cloud foundations. Later main updates add personal providers, durable voice jobs, inline maths and tutor/research groundwork. Remaining implementation and hosted/payment/device acceptance are in the [backlog](docs/BACKLOG.md). DEBUG fixture replies are labelled separately from live AI. Core study and portability remain available locally.

