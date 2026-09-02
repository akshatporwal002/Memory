# Implementation log

## 2026-09-03 — foundation

- Authoritative scope: ENGRAM-FIRST-BUILD.md and supplied goal-objective.md. Standalone native app; AI, voice, MCP, billing and sync deferred.
- Existing repository baseline preserved on codex/engram-first-build, commit 4b18899. No Git author configured; commits explicitly use Codex <codex@localhost>, without changing global Git configuration.
- Windows host initially has no Swift, Xcode, MSVC or WSL distribution. Toolchain installation is authorized and being investigated. Apple runtime checks remain pending.
- Source changes are assembled in the sandbox staging directory then copied to the requested project with reviewed permission; supplied documents remain unchanged.
- Tests are written before implementations. Until a Swift compiler is available, they are unexecuted tests, not claimed RED/GREEN evidence. User explicitly directs continuing native source work when Apple tooling is unavailable.
- First contract slice: create deck/note → reveal → preview/grade → durable reopen → undo; cloze sibling preservation; repository CAS/failure; deterministic alternative scheduler.
- Production scheduler candidate: official open-spaced-repetition/swift-fsrs, MIT, revision 4fbaf20184d62f82a9f44f343337c61a2c5483e9. Inspect FSRS-6 defaults explicitly rather than library's legacy v5 default.

## Implemented decisions and verification

- Installed official Swift 6.3.3 and the required Microsoft C++/Windows SDK toolchain with the user's permission. No Mac/Xcode environment became available. Production core, adapters and tests execute on Windows; native Apple source is syntax-checked only.
- Selected a validated atomic snapshot repository for the first build, one library window, FSRS-6 with explicit weights and deterministic fuzz-off behavior, named source identities for evolving Anki exports, and a constrained native markup/media renderer. These are documented boundaries, not implied Anki or multi-device parity.
- Confirmed legacy-compatible Anki26.08.1 fixtures through four official-backend roundtrips, including native-authored templates and a new Engram grade. Modern package codecs, custom templates and unmappable source scheduling are explicitly reported before mutation.
- Independent reviewers produced actual failing hierarchy, import identity/history and markup tests. Remediation preserved the assertions and progress/history semantics. Added cancellation, backup/commit failure and concurrent-write contracts, plus exact-byte startup recovery.
- A final review found that direct same-library APKG reimport cannot safely reconstruct native IDs/history. Chose explicit refusal using source-library provenance, independent of user namespace overrides; complete native backup restore is the recovery route. Separate-library transfers remain supported. The original duplicate mutation was reproduced before adding the guard.
- Native UI includes adaptive Library detail, persistent draft/selection/session ownership, completion/count transitions, system accessibility settings, explicit file operations and bundled dependency notices. Browser screenshots are labelled mockups; Apple build/runtime/accessibility/media verification remains pending.
- Milestone and RED/fix commits are retained on codex/engram-first-build. TEST-RESULTS.md and HANDOFF.md are the final evidence and acceptance audit; this chronological log is not a release-readiness claim.
