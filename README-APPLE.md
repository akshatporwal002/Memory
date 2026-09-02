# Native Apple build and verification

These are **unverified Apple build instructions** for the native SwiftUI implementation. This development run used Windows; Xcode compilation, simulators, SwiftUI previews, VoiceOver, native keyboard behavior and Liquid Glass rendering are pending. A Swift 6.3.3 Windows `swiftc -frontend -parse` pass succeeded for Features and App source; it checks Swift syntax only, without resolving SwiftUI types or linking an Apple app. The HTML contact sheet is only a design mockup.

## Prerequisites and build

- A Mac supported by stable Xcode 26, including installed iOS simulator runtimes. Deployment targets are iOS/iPadOS 17 and macOS 14. Build with the modern SDK for system Liquid Glass on supported OS 26 devices; earlier releases use normal native system chrome.
- XcodeGen installed from its official distribution (for example `brew install xcodegen`). No paid service is required for simulator or local unsigned builds. Device signing requires the user's own Apple development setup.
- The checked-in `Package.swift` and `Vendor/FSRS` source must be present.

From the repository root:

```sh
xcodegen generate --spec project.yml
xcodebuild -resolvePackageDependencies -project Engram.xcodeproj -scheme Engram-iOS
xcodebuild -project Engram.xcodeproj -scheme Engram-iOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Engram.xcodeproj -scheme Engram-macOS -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
open Engram.xcodeproj
```

Choose an installed iPhone simulator, then an iPad simulator, and Run `Engram-iOS`. Run `Engram-macOS` using My Mac. Exact device names vary by installed runtime: `xcrun simctl list devices available`. Record the device and OS used when executing the pending checklist. `xcodegen` generates the project, iOS Info.plist and Mac entitlements from the checked-in specification; those outputs must not be confused with successful compilation.

The application uses `Application Support/Engram/library.json` within its own sandbox/container. It loads an existing file or starts an empty library. Each accepted grade writes the entire validated snapshot atomically before advancing. Media lives in that library snapshot. No network or AI provider is needed for local study. Do not delete the app/container before exporting a complete backup.

macOS uses a single `Window`, removes the New Window command, and sets a minimum readable window size. iOS/iPadOS disable multiple scenes in the generated Info.plist. This avoids multiple repository writers until explicit multiwindow coordination is implemented. A separate installation on another device has separate data; this build does not sync.

## UI behavior and integration

`App/EngramApp.swift` is the concrete composition root: `AtomicFileRepository` + `FSRSScheduler` + `StudyService` + `EngramModel`. The Features target imports only LearningCore, StudyApplication and DesignSystem. It must not create a persistence or scheduler adapter.

`EngramRootView(model:portabilityAction:)` provides a working optional toolbar hook for application-owned import/export. When no action is supplied the button is absent. `CardContentView(text:media:)` is the isolated rendering seam for supported imported formatting/media; the initial implementation displays ordinary text. Imported formatting and portability integration must be supplied before claiming full Anki workflow completion.

Today uses the same queue policy as study and labels available new/due counts within limits. Library lists real notes and generated cards, with per-card suspension, deck filtering, text search, `tag:name` and `is:suspended`. Note context menus expose editing/deletion; deck actions expose rename/delete. New notes support basic and cloze; imported reverse notes retain their type. Editor preview uses the same core renderer as review. Saved note type changes require migration and are disabled. Ordinary text edits and moves preserve schedules. Removing a cloze marker retires that sibling. Unsaved drafts live in the feature model above layout branches, with an explicit discard confirmation.

Review uses an opaque scrollable content surface with controls outside scrolling content. Compact grades are 2×2, wide grades are a row, accessibility text sizes use a column. Question and answer use the core renderer. Space reveals, 1–4 grade after reveal, Command-Z undoes, Escape exits. These shortcuts only exist in the review sheet, which has no editable inputs; editor shortcuts are separate. Busy guards and captured presentation identifiers prevent rapid inputs from grading the next question. Stable mutation IDs permit retries after uncertain completion. Persistence succeeds before the model advances; animation does not drive writes. Exiting keeps the persisted session; completion offers a refresh for newly due learning cards.

Theme and appearance are persisted separately in device UserDefaults. Both stay separate from library/scheduler data. The root updates the theme environment without changing feature identity. The navigation shell adapts by width (<600 compact native tabs, wider native sidebar). Native platform controls provide system material; Increase Contrast/Reduce Transparency request opaque toolbar treatment. Exact optical behavior remains a runtime gate.

## Pending native acceptance run

1. Launch empty, create `Biology::Plants`, create a basic note, create `The {{c1::xylem}} carries {{c2::water}}.`, verify both siblings, preview and edit a note.
2. Study, reveal, exercise Again/Hard/Good/Easy, undo, and rapidly repeat mouse/keyboard events. Confirm exactly one review event per accepted presentation. Exit and resume the saved revealed card; restart and verify cards/history persist.
3. Search tags, suspend one cloze sibling, verify the other stays independently scheduled. Move a note, rename a parent deck, cancel and confirm note/deck deletion. Inspect true empty and no-match states.
4. Switch Warm/Neutral and System/Light/Dark during a draft and between question/answer. Resize iPad/Mac, rotate phone, dismiss/reopen sheets and ensure draft/session selection persists.
5. Run VoiceOver, Full Keyboard Access, largest Dynamic Type, long prompts and answers, empty/invalid cloze inputs, visible focus, Reduce Motion, Reduce Transparency and Increase Contrast. Check Save with keyboard presented and last list row above native tabs.
6. Verify both pre-26 native fallback and OS26 Liquid Glass chrome over warm/light/dark backgrounds. Measure long review responsiveness before making performance claims.
7. Complete the parent portability/media integration and its fixture/round-trip/backup restoration checks before describing the full first build as complete.

Known limitations at this handoff: Apple compilation and runtime tests have not run; app startup recovery provides retry without replacing a corrupt library; source renderer/portability hooks require the parent implementation; no claim is made that static source inspection verifies native behavior.
