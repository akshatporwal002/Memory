# Engram architecture

Reviewed against main `381c917` on 5 October 2026. This describes current source boundaries; see [status](CURRENT-STATUS.md) for evidence limits and [backlog](BACKLOG.md) for unfinished requirements. The [original first-build architecture](archive/superseded/ARCHITECTURE.md) remains historical reference.

## Modules and composition

- `App` owns Apple shells, startup/recovery, file panels and concrete composition.
- `Features` owns SwiftUI screens and controllers, using `DesignSystem` for themes and semantic presentation.
- `LearningCore` defines portable library, scheduling, resource, assessment and assistant models.
- `StudyApplication` owns study/content transactions, queue policy, answer attempts, source-grounded operations and selected-library projection.
- `PersistenceAdapters` provides SQLite, atomic-file and memory repositories; `SchedulingAdapters` wraps pinned FSRS.
- `AnkiAdapters` isolates package/SQLite/archive interoperability and complete native backups.
- `ChatGPTAuth` owns OAuth sessions and device-only credentials. `AIInfrastructure` defines shared requests, events and tools; feature controllers apply grounding, consent and application actions.
- `CloudAdapters` provides Supabase transport, projection and sync, backed by the permission operations in `supabase/migrations`.

The concrete dependency list is maintained in [Package.swift](../Package.swift). Local study and portability do not require an AI account or a paid service.

## Persistence and accounts

[App composition](../App/EngramApp.swift) opens `Application Support/Engram/library.sqlite` within the app container. `SQLiteLibraryRepository` uses WAL/FULL synchronous mode and stores revisioned snapshot payloads, account partitions, a durable outbox and cloud state/permissions. Snapshot writes and outgoing markers share a transaction. The snapshot remains encoded data; adopting SQLite does not itself make media or every model independently normalized.

On first migration from the legacy `library.json`, the repository validates the old snapshot, copies and verifies a uniquely named backup, then verifies its SQLite representation. Original legacy data is retained. Repository-context leases and revision checks reject writes captured before an account switch.

`LibrarySpaceRepository` projects the selected named library for study, retrieval and feature operations, while preserving other libraries during commits/restores. Account cloud synchronization uses the underlying repository. Device-only content is excluded from cloud projection. Native backup/export operates on the active library; export libraries individually for recovery.

ChatGPT's verified local profile supplies AI access but is not a Supabase session. Google/Apple/email supply cloud identity when configured. The hosted pilot is disabled by default in [project.yml](../project.yml). See [account/library behavior](ACCOUNT-AND-LIBRARIES.md).

## Study and scheduling

Notes own content; generated cards own independent schedules. Stable presentation/mutation IDs and atomic transactions protect grades against duplicate or stale submission. Undo records corrections rather than erasing history. Typed attempts retain original responses, evidence and provisional feedback; accepted improvements and scheduling are committed through the explicit Next boundary.

The FSRS adapter is pinned under `Vendor/FSRS`, with vendor-neutral state envelopes and review history. Queue policy owns limits, study-day/timezone rules, deck selection and suspension. A production scheduler change requires explicit state migration and validation; a test adapter is not a user-selectable alternative. Automatic sibling burying and parameter optimization remain future work.

## AI, sources and voice

Assistant actions call bounded application operations, retain a mutation journal, and use confirmation/undo where required. Retrieval returns scoped, versioned evidence; a provider response cannot independently mutate the repository or award a grade. PDF generation keeps local page text, a learning brief, approved samples and resumable draft batches; saving is atomic/idempotent. Unsupported evidence leaves output withheld or an answer ungraded.

Markdown, KaTeX and Mermaid rendering use bundled offline resources. This is distinct from the restricted markup supported by imported Anki templates. Local foreground voice uses FluidAudio-backed recognition/synthesis and application assessment operations. The newer cloud voice/job/billing/math requirements are tracked in [the backlog](BACKLOG.md), not treated as implemented by these foundations.

## Replacement and release boundaries

Keep themes behind semantic DesignSystem roles, schedulers behind the scheduling contract, persistence behind validated repository transactions, and package parsing behind inspected candidates. Preserve IDs, histories, originals and backup semantics through migrations. Credentials remain outside library snapshots, exports and cloud projection.

The native shell currently limits competing app windows. Cross-process/multiwindow editing, large-library scalability, full platform accessibility, live AI quality and hosted device sync require their own acceptance checks. Historical file-adapter [benchmarks](archive/benchmarks/PERFORMANCE.md) describe their tested implementation, not current SQLite performance.
