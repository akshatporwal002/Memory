# Engram architecture

## Boundaries

```text
App (Apple shells + composition root)
  -> Features -> StudyApplication -> LearningCore
  -> DesignSystem
  -> PersistenceAdapters -> LearningCore
  -> SchedulingAdapters -> LearningCore + pinned MIT FSRS
  -> AnkiAdapters -> LearningCore + SQLite + archive codec
```

LearningCore and StudyApplication import Foundation only. SwiftUI does not determine when a grade is saved. Dependencies are passed to one shared StudyService actor. Pure Swift targets and their tests compile separately from Apple presentation. No AI, network provider, entitlement or billing service is required for local study or portability.

## Data and transactions

Notes own content; generated cards own independent scheduling. Basic uses ordinal 0, reversed uses 0/1, cloze cN uses N-1. Repeated cN markers form one card. Removing a cloze retires its card; adding it back restores its identity/state. Ordinary content edits preserve schedules and increment card versions, invalidating stale presentations. Moving a note moves all its cards together. Deck names use `::` hierarchy. Deletion produces tombstones so native backups retain review evidence.

LibraryRepository exposes read and atomic compare-and-swap commit. A transaction includes schedule, review event, persisted session, and revision. A rejected write must change none of them. AtomicFileRepository serializes native snapshots via Foundation atomic file replacement; MemoryRepository exercises the same contract and injected failures. Its single-instance contract is deliberate: the platform app has one library window and one shared repository actor. A second process writing the same file is unsupported; revision checks detect sequential external changes, not an OS-level cross-process transaction. Do not introduce multi-window/multi-process editing without a stronger repository implementation.

The native snapshot is a versioned portable model, not view state. The first adapter trades whole-snapshot write cost for a small, inspectable recovery path. SQLite and SwiftData were considered: SQLite gives scalable transactions but adds mapping/migration work; SwiftData ties schema tooling to Apple SDKs and cannot be verified on this Windows host. The format adapter already uses isolated SQLite to read Anki. Replace the production repository with normalized SQLite before lifting the documented 250,000-note / 512 MB media limits; large-library responsiveness remains a benchmark gate, not a claim.

Review IDs are idempotency keys. Each presentation has a separate token; a stale token cannot grade the next card. Reveal saves outcomes and the scheduling time. Grade commits exactly the displayed outcome and separately records commit time. Undo appends a correction and restores the prior schedule; it does not erase the original event. Imported review rows retain their source namespace and raw fields separately, including manual operations which are not recall grades.

## Scheduling and queues

FSRSScheduler wraps official swift-fsrs revision `4fbaf20184d62f82a9f44f343337c61a2c5483e9` with explicit FSRS-6 (21 weights), desired retention 0.9 by default, 1m/10m learning steps, 10m relearning, 36,500-day maximum and fuzz disabled. There is no parameter optimizer or claimed exact Anki scheduling parity. Vendor source and MIT notice are preserved under Vendor/FSRS. A fresh vendor engine per calculation avoids shared mutable algorithm state.

ScheduleState is a versioned envelope with opaque payload, scheduler ID, implementation ID, state/settings versions, due time and phase. Unsupported envelopes fail visibly rather than becoming new cards. ImportedScheduleMapping is an optional adapter capability; imported FSRS review memory can retain due/stability/difficulty with explicit disclosure that future intervals use Engram's parameters. Exact source originals remain separate.

QueuePolicy owns due selection, deck subtree filtering, global daily new/review limits and ordering (learning, due review, new). Defaults: 20 new, 200 review; learning repetitions do not consume review-card budget. Suspension is independent from phase. Siblings have independent schedules; automatic sibling burying is not implemented. Counts and sessions use this same policy. New cards becoming due join at the next refresh. Learning waits expose their actual next due time; the app may leave and resume rather than pretending a future card is currently due.

The study day starts at 04:00 in a persisted IANA timezone selected from the device on first creation. Calendar date arithmetic handles daylight saving; travelling does not silently change the library timezone. Timezone changes are deliberate settings changes. Due instants remain absolute. Review statistics exclude corrections and identify imported evidence separately.

## Replacing components

**Theme:** add a declarative EngramTheme preset and its palette/typography mappings in DesignSystem, expose it in preferences, and run all contrast pairs. Feature views request semantic roles. Theme and System/Light/Dark appearance are device preferences and do not rebuild StudyService or drafts. Native glass belongs to standard tabs/sidebar/toolbars; opaque reading surfaces remain separate. Accessibility settings override decorative movement/transparency.

**Scheduler:** implement Scheduler, inject it at composition, and run the same workflow contracts. FixedScheduler exists only in tests. A production switch requires a pre-migration backup and an explicit migration of each envelope: replay available evidence, convert proven states, or reset with learner consent. Retain originals and history. Never swap the algorithm midway through a revealed presentation. State-schema, algorithm implementation and settings versions are independent.

**Repository:** implement LibraryRepository with validated CAS transactions, run both durable reopen and failure tests, and migrate the portable snapshot. Preserve IDs, media, originals, history and corrections. Changing a database schema is separate from changing the native backup version. Current schema is v1; unknown versions reject without mutation. No fictitious old-format migration is claimed.

**Format adapter:** parsing returns inspected data and compatibility findings. Only application use cases commit confirmed imports. Extend package variants without adding SQLite/archive knowledge to views. Preserve source identifiers/templates and report unsupported formats before import. Native backup must restore separately from Anki interoperability tests.

## Future seams (documentation only)

- AI/resource ingestion/retrieval: application operations accept source references today. Later source records need stable resource/version/page/section/span identifiers. Evidence and abstention policy sits above provider adapters; missing or contradictory evidence must leave assessments ungraded.
- Voice: transcription and speech output are independent adapters. A transcript is not a recall grade. Store ambiguity and source-backed assessment evidence separately.
- MCP: authenticated tools call these application use cases; they do not get direct repository access or duplicate learning rules.
- Sync: use stable IDs, idempotent events, corrections and tombstones. Define field/content conflicts and scheduler reconciliation explicitly; timestamps alone do not resolve conflicting histories. No sync exists today.
- Entitlements/billing: optional managed services may be metered; local cards, offline study and exports remain independent. Credentials belong to platform secure storage and never to library snapshots/backups. There are no placeholder provider clients or paid controls.

## Verification status

The initial five core workflow tests compiled and passed on Windows Swift 6.3.3. Independent review identified hierarchy/wait defects and triggered regression tests. See TEST-RESULTS.md for current evidence rather than treating this architecture description as test proof. SwiftUI, Apple file panels, accessibility and motion require Apple builds/runtime checks.
