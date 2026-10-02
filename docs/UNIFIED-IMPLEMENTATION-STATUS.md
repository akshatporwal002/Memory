# Unified Engram implementation

Branch: `akshat/dev`. Reviewed minimalist work and corrected requirements merged into main at `744bc3a`. The reviewed UI stage (`e2c8dc0`, `c04d747`) has also been fast-forwarded into main. Later AI and cloud stages remain on dev pending their separate acceptance gates.

## Checkpoints

- UI/rendering: `e2c8dc0`, `c04d747` are on main. Later dev refinements add accessible large-text typed feedback, line/bar preferences removal, offline Markdown/math/Mermaid, and account/action screens. The Mac simulator recheck at `0d12049` passed the model-picker target, keyboard dismissal, readable feedback and one-time Next advancement in light, dark and large text.
- Shared AI: normalized provider stream/events/tools, persistent conversations/model choice, bounded orchestrator, versioned source retrieval, native navigation, versioned mutation journal, confirmation and atomic run undo implemented. Live account/model-capability and tool-call checks remain. Action parity is tracked below.
- Typed feedback: persisted provisional attempts, Unicode span checks, discussion and explicit accepted improvements. Next atomically records recall/scheduling and queued accepted changes. The Mac fixture verified exact-answer feedback and one review; live paraphrase/dispute grading remains unverified.
- SQLite/cloud: verified migration backup, account partitions, compact durable outbox, pinned Supabase adapter, incremental sync/merge/review replay, expiring invitations, member removal, conflicts, private original-PDF Storage and permission-aware question moves implemented. Hosted pilot remains disabled until two app devices/two users pass acceptance.

## Validation evidence

Mac unsigned generic iPhone build succeeds. The latest Swift package suite had 170 passing tests, one platform-dependent skip; the new cloud move test passed in its focused suite after that full run. Tests cover provisional persistence/Next idempotency, assisted grading, Unicode spans, retry/undo, SQLite account isolation, owner-private PDF round-trip, offline changes and revocation during study. The local Supabase database was reset from the complete ordered CLI migration chain; SQL permissions and real localhost Auth/REST/Storage/Realtime flows pass for two separate test users, including moved-question privacy, CAS and revoked access. Local security advisor previously reported no issues. These fixtures establish neither live ChatGPT behavior nor two physical app devices syncing.

The signed build at `0d12049` was installed and launched on the paired iPhone. Later cloud code is currently on the development branch and has not yet been installed there.

## Assistant action map

`inspect` reads bounded library/deck/note/settings/progress/history/search data. `retrieve` returns versioned, scoped source quotations. `edit` directly handles deck creation/renaming/deletion, note creation/editing/deletion/move, notebook sections, retention, suspension, study settings, appearance and cover removal; deletion awaits confirmation. `memory` lists or explicitly confirms save/delete. `reveal_answer` marks recall assisted. `navigate` opens Today, Library, Activity, deck, questions, notes, settings page, deck/note editor, study, PDF setup or its native file picker, the native cover photo picker, import/export, action review, app account, sharing or memory. Authentication, choosing the file/photo and OS permissions remain native. PDF generation follows the dedicated grounded workflow; ordinary app tool execution does not impersonate its source picker or confirmation steps. The latest picker, cover and iPad Library refinements are awaiting the next Mac build and simulator review because the Mac became unreachable over SSH.

Remaining parity work: the assistant cannot yet directly target every review subcontrol; it opens the owning screen. Conversation/model defaults and local voice preferences should be scoped to app accounts in a later pass. Large live libraries and complete app-device sync need profiling. The hosted pilot flag is off by default.

Local Supabase uses CLI 2.119.0 and the Mac's existing Docker runtime. SDK pinned to 2.55.3; no hosted project or privileged app key has been created.

## External prerequisites

User-created Engram organization, confirmed project cost and Apple/Google provider configuration remain pending. The connected unrelated stocks project is untouched. Live AI tool calling, account/model discovery, grading and PDF generation must be checked separately from fixtures; physical two-device/two-user synchronization and accessibility checks remain before enabling hosted collaboration. Existing local study remains available.
