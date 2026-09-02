# Verification evidence

## Current integrated result

3 September 2026, 04:06:48 Australia/Sydney: **56 XCTest cases passed, 0 failures**, using the production core, application, file/memory repositories, FSRS adapter, archive/Anki adapters and startup recovery helper. Full output: `validation/swift-tests-windows.log`. The trailing Swift Testing runner reports zero tests because Engram's suite uses XCTest; it does not negate the 56 executed XCTest cases.

The pinned upstream FSRS source independently passed **98 tests in 23 suites**; output: `validation/fsrs-upstream-tests-windows.log`. Four actual Swift-produced package variants passed official Anki 26.08.1 backend import/semantic comparison in disposable collections; structured output: `validation/anki-roundtrip-results.json`. See ANKI-COMPATIBILITY.md for exact fixture provenance, tested content and limitations.

Additional verified contracts include all six independently reproduced import regressions, seven import transaction tests (backup failure, repeated import, stale inspection/media collision, concurrent change during backup, pre-commit cancellation, final commit failure, native evidence rejection), twelve safe-markup tests and four damaged-startup recovery tests. Test assertions were retained through remediation. Historical RED logs are preserved under `validation/`; the native-evidence merge failure was reproduced before adding its explicit rejection. The recovery tests compare exact original bytes and validate failure safety.

Final App/Features/DesignSystem source passed Swift syntax parsing; `validation/apple-source-syntax-only.log` explicitly labels its limitation. `project.yml` parsed with YAML anchors resolving identically for both apps' document types. **XcodeGen, SwiftUI typechecking, Apple linking and native execution have not run.** No code-coverage percentage, UI conformance or frame-rate claim is made.

From the delivered repository root on Windows:

```powershell
. ./scripts/Enter-SwiftEnvironment.ps1
swift test
swift test --package-path Vendor/FSRS
node design/previews/build-previews.cjs
```

The first integrated run used `--package-path staging` in the working sandbox. The delivered tree is copied without build artifacts, and the final clean delivery verification is recorded below. Apple commands are in README-APPLE.md. Anki fixture commands are in ANKI-COMPATIBILITY.md. Ordinary tests use bundled fixtures without requiring Anki installed.

## Host

Windows x64, Swift 6.3.3, Microsoft Visual C++ 14.44, Windows SDK 10.0.22621. See TOOLCHAIN.md. No Mac/Xcode/simulators are available in this session.

## First workflow run

2026-09-03, `swift test --package-path staging` using scripts/Enter-SwiftEnvironment.ps1: build succeeded, 5 XCTest tests, 0 failures. Covers durable create/study/reopen/undo, cloze sibling preservation, invalid input rollback, memory/file repository CAS and validation, deterministic injected scheduler, memory transaction failure and retry. This run predates Anki adapter integration and later regression tests.

An initial compilation failure was due to async expressions inside XCTest autoclosures; assertions were changed to await values first. This was test harness repair, not a business-behaviour RED test.

## Design

`node design/previews/build-previews.cjs`: 72 contrast pairs passed; minimum ordinary-text ratio 5.289:1. Contact sheet is a design mockup, not a native runtime capture. See DESIGN-HANDOFF.md for remaining checks.

## Expanded core regression run

2026-09-03 03:44 Sydney, full `swift test`: 20 XCTest tests, 0 failures. Includes 17 core/application tests plus 3 archive tests. Verified all four real FSRS grades, concurrent duplicate attempts, daily limit/undo and DST boundary, learning→review→relearning, persisted revealed-session resume, actual filesystem write failure/retry, corrupt-file non-overwrite, unsupported scheduler rejection, retirement/reintroduction and stale editor/deletion protection.

Independent review regression RED: 12-test run had two failures (parent deck learning wait omitted children; parent no-op rename collided with own children). Both tests passed after sharing eligibility policy and validating rename mappings against unaffected decks case-insensitively. Baseline/RED source is checkpoint 079df56.

## Required pending checks

- Native document-picker Anki migration and backup/restore workflows; adapter and disposable backend checks above have passed.
- Build iOS/iPadOS and macOS with stable Xcode; exercise create → study → relaunch.
- Runtime layout: iPhone portrait/landscape, iPad narrow/full, Mac resize, long content and keyboard-visible editor.
- Runtime accessibility: VoiceOver, Dynamic Type, focus/keyboard, reduced motion/transparency, increased contrast.
- Runtime native glass, reveal/grade interruptibility and frame timing; no frame-rate claim.
- Large-library memory/write throughput and media playback on Apple platforms.

This file is updated as verification proceeds. No native release-readiness claim is made.
