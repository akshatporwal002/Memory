# Verification evidence

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

- Compile/test Anki/native backup adapters; run real Anki fixtures in a disposable profile.
- Build iOS/iPadOS and macOS with stable Xcode; exercise create → study → relaunch.
- Runtime layout: iPhone portrait/landscape, iPad narrow/full, Mac resize, long content and keyboard-visible editor.
- Runtime accessibility: VoiceOver, Dynamic Type, focus/keyboard, reduced motion/transparency, increased contrast.
- Runtime native glass, reveal/grade interruptibility and frame timing; no frame-rate claim.
- Large-library memory/write throughput and media playback on Apple platforms.

This file is updated as verification proceeds. No native release-readiness claim is made.
