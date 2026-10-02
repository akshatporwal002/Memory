# Unified Engram implementation

Branch: `akshat/dev`. Reviewed minimalist work and corrected requirements merged into main at `744bc3a`. Main remains at that reviewed revision while the new stages undergo review.

## Checkpoints

- UI/rendering: `e2c8dc0`; Mac review found four defects. `c04d747` repairs local WebKit loading, large-text Library overlap, Activity filter placement and chart label density. Re-review pending.
- Shared AI: normalized provider stream/events/tools, persistent conversations/model choice, bounded orchestrator, native navigation, versioned mutation journal, confirmation and atomic run undo implemented. Further parity, interruption and live model-capability checks remain.
- Typed feedback: persisted provisional attempts, Unicode span checks, discussion and explicit accepted improvements. Next atomically records recall/scheduling and queued accepted changes. Further grading fixtures and device feedback review remain.
- SQLite/cloud: local repository and verified migration backup, durable account partitions/outbox, pinned Supabase adapter, incremental sync/merge/review replay foundation and account/sharing/conflict screens implemented. Hosted pilot stays disabled until the full two-device/two-user acceptance gate passes. Remaining synchronization edge cases are under test; fixture success is not hosted acceptance.

## Validation evidence

Mac unsigned generic iPhone build succeeds. Swift package suite: 154 tests, zero failures, one platform-dependent test skipped. New tests exercise provisional persistence/Next idempotency, assisted grading, Unicode spans, retry/atomic undo, SQLite isolation/outbox and field/section merges. The local Supabase schema and CLI-generated migrations were applied from a clean database; owner/editor/viewer/outsider, private attempt isolation, revocation, CAS and retry checks pass. Local security advisor reports no issues. These counts do not establish live ChatGPT or device-to-device synchronization acceptance.

Local Supabase uses CLI 2.119.0 and the Mac's existing Docker runtime. SDK pinned to 2.55.3; no hosted project or privileged app key has been created.

## External prerequisites

User-created Engram organization, confirmed project cost and Apple/Google provider configuration remain pending. The connected unrelated stocks project is untouched. Live AI tool calling, account/model discovery, grading and PDF generation must be checked separately from fixtures. Hosted pilot remains off by default. Existing local study is available.
