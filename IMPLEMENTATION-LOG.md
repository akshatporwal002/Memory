# Implementation log

## 2026-09-03 — foundation

- Authoritative scope: ENGRAM-FIRST-BUILD.md and supplied goal-objective.md. Standalone native app; AI, voice, MCP, billing and sync deferred.
- Existing repository baseline preserved on codex/engram-first-build, commit 4b18899. No Git author configured; commits explicitly use Codex <codex@localhost>, without changing global Git configuration.
- Windows host initially has no Swift, Xcode, MSVC or WSL distribution. Toolchain installation is authorized and being investigated. Apple runtime checks remain pending.
- Source changes are assembled in the sandbox staging directory then copied to the requested project with reviewed permission; supplied documents remain unchanged.
- Tests are written before implementations. Until a Swift compiler is available, they are unexecuted tests, not claimed RED/GREEN evidence. User explicitly directs continuing native source work when Apple tooling is unavailable.
- First contract slice: create deck/note → reveal → preview/grade → durable reopen → undo; cloze sibling preservation; repository CAS/failure; deterministic alternative scheduler.
- Production scheduler candidate: official open-spaced-repetition/swift-fsrs, MIT, revision 4fbaf20184d62f82a9f44f343337c61a2c5483e9. Inspect FSRS-6 defaults explicitly rather than library's legacy v5 default.
