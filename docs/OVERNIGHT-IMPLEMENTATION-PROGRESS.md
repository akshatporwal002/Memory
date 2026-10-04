# Overnight implementation progress

Goal: implement the approved requirements in OVERNIGHT-IMPLEMENTATION-REQUIREMENTS.md for iPhone and iPad. The latest instruction requires individual approval of every new question type, including ordering; retain those as proposals rather than implement them. Configuration-dependent work must be recorded and deferred while independent implementation continues.

## Delivery checklist

- [x] Merge reviewed branch and requirements into main, preserving commits.
- [x] Create and push akshat/overnight-learning-system from merged main.
- [x] Inline account controls, linked-identity operations and shared capsule action styles.
- [ ] Complete the remaining app-wide shape audit and live linked-account acceptance.
- [x] Deduplicate ChatGPT registrations and prevent accumulation on reconnect (migration/replacement tests).
- [x] Add provider-neutral Google/OpenAI chat connections and secure BYOK settings.
- [ ] Prepare Vertex server integration and validate live provider accounts.
- [ ] Implement voice adapters, interruption and durable answer processing.
- [ ] Implement sandbox billing, authoritative wallet/entitlement interfaces and release guards.
- [ ] Provide repeatable AWS MCQ, short-answer and maths sample imports.
- [ ] Implement full equation-entry palette, numeric response metadata and deck calculator policies.
- [ ] Specify five-student tutor tier, permissions and capped insight workflows.
- [ ] Obtain individual approval before implementing any new question type, including ordering or numeric-response metadata. Not authorized for implementation yet.
- [ ] Validate stages, capture iPhone/iPad changes and publish reviewable commits.
- [ ] Audit every requirement against evidence before declaring completion.

## Session safety

The temporary Windows wake helper is explicitly authorized. Its state is recorded in ignored .build/overnight-awake-20261004.status and its owned PID in .build/overnight-awake.pid. The implementation must request stop, verify process exit and release the wake request before every final response. Restart it only for a new active work session. Do not permanently alter power settings.

## Awaiting external setup

- GCP/Vertex project, region and server credentials.
- Managed provider credentials and authenticated service deployment.
- Apple authentication provisioning/provider configuration.
- StoreKit products and production billing acceptance.
- A real authenticated cloud account for the user's test-deck import.

These do not block local implementation, fixtures or configuration instructions. Production billing and unconfigured managed calls remain disabled.

## Stage 1 evidence

- Exact staged source passed 207 Mac package tests, one skipped, zero failures. The combined working tree passed 210 tests; unrelated feedback/AI changes are excluded from this stage's commit.
- iPhone light inline-account capture, iPhone dark account/email/library isolation flow, and iPad landscape inline-account/email flow passed.
- Current screenshots and one preceding capture are grouped under `current_ui/Settings/Account`. The iPad baseline is captured separately from the unchanged prior source.
- Apple sign-in readiness defaults to false until provisioning/provider setup is validated. Browser linking stores expiring account ownership metadata, never tokens, and ordinary sign-in callbacks are not intercepted as linking callbacks.
- Hosted account linking, revocation and live authentication remain configuration-dependent and unverified.
- Recovered Mac build space by removing three inspected redundant generated build directories, preserving sources and screenshot evidence.

## Stage 2 in progress

- OpenAI personal API adapter now shares the existing streaming contract, with its own API catalog/function schema and provider-owned continuation state.
- Added account-scoped device-only Keychain operations for OpenAI/Gemini personal keys and secret-safe local validation.
- Foundation suite: 211 tests, one skipped, zero failures. These are contract/regression tests, not live provider validation.
- Gemini discovery/streaming, opaque signature continuation, masked key-entry UI and shared chat/grading/PDF routing are now implemented. Unavailable selections never silently change provider.
- Exact isolated provider source passed 222 Mac package tests (one skipped, zero failures); unrelated feedback/action-expansion source was excluded from that checkout. iPhone key-entry validation and inline account capture passed; the isolated iPhone key-entry regression also passed.
- iPad application landscape bounds and key-page traversal pass, but exported screen pixels remained portrait. Direct screenshot-dimension validation fails even after a forced orientation transition, so those captures are not accepted as landscape evidence. The stronger UI test retains this failure; investigate simulator surfaces before accepting the capture gate. Do not claim that the landscape screenshot review passed.
- iPhone provider-key and validation captures are stored under `current_ui/Settings/PersonalAPIKey`. The account-light capture was updated, retaining one previous revision. New key pages have no pre-feature screenshot.
- Live personal-provider behavior, Vertex, voice jobs and billing remain outstanding. See PERSONAL-AI-PROVIDER-FOUNDATION.md.

## Stage 3 started: speech adapters

- Added separate transcription/output interfaces and an OpenAI personal API audio adapter. Bounded multipart recordings, WAV output checks, cancellation, blocked credential redirects and secret-safe errors are implemented.
- Transcription requests never contain the card's expected answer. Transcript spelling, negations and self-corrections are preserved; provider usage is recorded separately from correctness.
- No automatic retries or billing-path fallbacks. A network interruption reports uncertain delivery because personal audio requests are not assumed idempotent.
- The provider source plus initial speech fixtures passed 226 Mac package tests (one skipped, zero failures). No live audio request or audio-quality claim is made.
- These adapters are not yet connected to recording/settings. Durable jobs, capture storage, entitlement checks, provider disclosure, Google audio and managed backend integration still need implementation before cloud voice is usable.

## Durable voice jobs in progress

- Added transactional capture/advance, pending-card exclusion, durable worker claims and capacity limits, transcript persistence, explicit retry/cancel, pending transcript correction and restart recovery.
- Exactly-once scheduling uses the original submission time independently of the visible card/session. Wait-mode advancement is a separate transaction that cannot add another grade. Stale content/settings/evidence and unsupported/unclear grades are rejected.
- Protected device recording storage supports immutable saves, retry reads, deletion and seven-day expiry. Raw audio never enters library entities, backups or cloud projection; device metadata is excluded from cloud projection.
- Pending correction preserves transcript history and invalidates older worker generations. Reconciliation of corrections after a completed grade remains outstanding.
- Final isolated Mac regression passed 235 package tests (one skipped, zero failures), including the cloud-projection check that pending recording IDs, device IDs and voice ownership metadata are not uploaded.
- No UI or phone installation changed in this stage. Worker/capture UI integration and entitlement enforcement remain outstanding; no new question types are implemented.

## Foreground voice worker

- Added bounded foreground dispatch, saved-transcript grading, post-transcription recording deletion and cancellation that rejects late provider results. Account ownership remains explicit; adapter closures must supply access/credential checks before networking.
- Ordinary repository revision races reuse the returned transcript or assessment rather than repeating a provider request. Superseded claims fail validation. Interrupted uploads require explicit retry after recovery.
- Shared marking accepts frozen per-job model/evidence. MCQ dispatch uses local canonical-choice grading; no new question type was introduced.
- Isolated Mac package validation passed 240 tests, one skipped, zero failures. Five worker tests verify cancellation/restart, account isolation, marking retry, completion after review exit and result-save races.
- Recording/settings integration, production entitlement enforcement, cleanup retry UI, live provider tests and device deployment remain outstanding. This stage changed no iPhone or iPad layout.

## Voice access and StoreKit foundation

- Worker dispatch requires explicit stage authorization. Denied access retains audio, records needs-attention and invokes no provider.
- Added account/environment-bound subscription, provider/purpose disclosure and job/rate-bound reservation checks. Production remains disabled by default. These are not yet wired into the existing local voice UI.
- Added inactive StoreKit product/purchase/restore/update handling with app-account binding, verified transaction/environment checks and server acknowledgement before finish. No products/backend are configured and no purchase was attempted.
- Isolated Mac package run passed 246 tests, one skipped, zero failures; StoreKit code compiled. Live purchase/ledger and device capture validation remain outstanding. See VOICE-PURCHASE-AND-ACCESS-FOUNDATION.md.

## Testing samples implemented, validation pending

- Added a Library import sheet for iPhone/iPad and Mac: Testing folder with four AWS MCQs, six short answers and three mathematical notation examples using existing text-answer cards. No new question types were added.
- Import is one transaction with library-scoped stable IDs. Reimports preserve edits, scheduling and deletions; unrelated name collisions fail without partial changes.
- Official AWS references were inspected. The configured Supabase project's read-only auth count is still zero, so authenticated account import remains deferred; no hosted writes were made.
- Three package tests and iPhone/iPad import/capture flows are written but unexecuted. SSH to mac.modem timed out during transfer and test attempts; no claim of compilation, screenshot acceptance or phone installation is made. The last passing 246-test run predates these changes.
- See TESTING-LIBRARY.md for variants and pending acceptance gates. Existing current_ui images are retained until new validated captures can be obtained.

## Equation-entry editor started

- Added a structured notation tree with nested editable slots, portable LaTeX output and bounded/escaped input. Palettes cover the requested arithmetic, algebra, functions, calculus, matrices, sets, probability and Greek families.
- Existing typed answers now offer Equation entry. iPhone uses a stacked editor; wide iPad/Mac use two columns with an accessibility fallback. No solver or new question type was added.
- Named-slot editing is implemented; direct visual caret editing, variable-size matrices/piecewise structures, structural removal/undo and optional evaluative calculators remain outstanding.
- Four package tests and iPhone/landscape iPad capture flows are written but unexecuted. A bounded Mac SSH recheck still timed out; Windows has no Swift compiler. Compilation, screenshot review and phone deployment remain pending. See MATH-EQUATION-ENTRY.md.

## Structural equation editing and tutor specification

- Added bounded structural undo/redo, removing the nearest template without losing its values/identities, and configurable matrices (1–6 rows/columns) and piecewise expressions (1–6 cases). Direct formula cursor hit-testing and resizing existing structures remain outstanding.
- Two additional package tests and UI undo/redo assertions are written; all new equation tests remain unexecuted pending Mac access. Do not apply the earlier passing-suite count to this code.
- Delivered TUTOR-ASSIGNMENTS-PLAN.md: provisional A$3 total/five-student tier, assigned-work-only access, invitations/consent/capacity, versioned assignments, bounded weekly insights, removal/revocation/expiry, iPhone/iPad layouts and acceptance gates. No tutor tier or hosted student access was activated.

## Voice capture and result controls, validation pending

- Connected on-device recognition to durable answer jobs, added bounded WAV capture, provider/Continue/Wait settings and an explicit debug-only local preview. Unconfigured cloud recording remains disabled.
- Added pending-count navigation, results/transcript correction/retry/cancel forms and Wait-mode advancement without duplicate grading. Worker scopes stop on suspension and connection changes.
- Added four focused tests; none has run. A fresh bounded SSH check still timed out. No new screenshots or phone installation can be claimed. See VOICE-CAPTURE-INTEGRATION.md for remaining production, reconciliation and lifecycle gates.
- New question types remain proposals awaiting individual user approval. No stay-awake helper was started in this stage.

## Completed transcript correction, validation pending

- Added atomic removal of the previous voice grade, retained recognition/assessment revisions and replay of later reviews from the preserved imported baseline. Replacement grading keeps the original answer time and a stable revision-specific ID.
- Correcting a completed result is available through the same transcript editor on iPhone/iPad. Its explanation states that saving recalculates due dates. A changed reference, account, unsupported scheduling state or concurrent mutation prevents an automatic overwrite.
- Cloud reconciliation uses the full review/correction history so a later event cannot resurrect a removed first grade. Three focused tests are written; compilation, tests and simulator/device review remain unexecuted pending Mac access.

## Recording cleanup and old-connection recovery, validation pending

- Persisted cleanup-needed state independently of grades, with protected-file removal and idempotent acknowledgement. The results list offers recording cleanup retries without uploading or remarking.
- Same-account/device pending jobs survive grading-connection changes visibly. Cancel releases their cards; retries/corrections stay tied to the original connection. New jobs carry explicit app-account ownership; legacy format recognition stays inside the account-isolated repository.
- Removed grades are labelled as previous results rather than claiming they remain scheduled. No question layout or new question type was added.
- Three focused tests are written, unexecuted. A new bounded Mac SSH check still timed out. Phone/iPad screenshots and installation remain pending; the stay-awake helper remains off.

## Existing equation structure resizing, validation pending

- Added in-place matrix/piecewise resizing through a compact Structure menu. Coordinates, nested expressions and stable field identities survive expansion; removing entered content requires confirmation and remains undoable.
- Added four core tests plus iPhone/landscape iPad resize and before/after capture flows. Rejected dimension/slot-limit changes preserve the whole document and editing history. All remain unexecuted pending Mac access.
- This extends the separately approved notation keyboard on existing text-answer cards. It adds no question type or solver. Direct visual/native-caret editing, optional calculators and runtime visual review remain outstanding.

## GCP/Vertex server preparation

- Added server-only, credential-injected Chirp 3 and Vertex text adapters with disabled-by-default sandbox dispatch and unavailable production. Strict endpoint/configuration/model/language/input limits, no automatic retries, completion checks and secret-safe errors are implemented.
- Configuration example and setup/integration documentation are in server/google_cloud/README.md. No provider call, hosting/IAM provisioning or credential change was made. Longer Chirp audio, streaming/tools, Google speech output, Gemini Live and hosted accounting remain outstanding.
- Eleven Python fixture tests passed locally. This is independent of the pending Swift compilation, phone/iPad capture and installation gates. The stay-awake helper remains off.

## Google speech output preparation

- Added server-only speech synthesis with an explicit voice/language allowlist, bounded plain text and validated PCM WAV output. Empty voice configuration disables output; no mobile playback, provider call or production activation occurred.
- Mandatory authorization now includes the exact serialized payload hash for transcription, speech output and text generation. Durable authenticated dispatch/accounting integration remains outstanding.
- Fifteen Python fixture tests passed locally, including malformed/truncated audio, voice/language mismatch and payload binding. Swift compilation, iPhone/iPad screenshots and installation remain pending; no new question type was implemented. The stay-awake helper remains off.

## Mac validation resumed

- The Mac became reachable after the user woke it. Transferred committed revision 54f6ba2 into the existing isolated source snapshot, excluding the other task's unfinished changes.
- Fixed the sample importer's access to the selected-library accessor and split its source assembly for Swift type checking. Fixed bindings through the immutable voice-controller reference and promoted weak captures before the MainActor authorization closure.
- With these fixes, the Mac package suite passed 269 tests, one skipped, zero failures; the iPhone simulator build succeeded. Evidence: .build/engram-overnight-validation-54f6ba2.log locally and /tmp/engram-overnight-ios-54f6ba2.log on the Mac.
- Targeted iPhone sample import/reimport passed. Fraction entry/insert/undo/redo and matrix resize/preserved value/undo passed after adapting the test to the actual keyboard Next control and stepper children. Three targeted phone flows pass in total; captures were exported and visually inspected. Current/previous pairs are saved under current_ui/iphone for library-testing, math-matrix and typed-equation-answer; math-entry contains the current fraction editor.
- On iPad, all three workflows reached their final functional assertions, then failed the actual screenshot aspect check: app frame was landscape but UIImage size was 1032 by 1376. The assertion remains intact. Results are /tmp/engram-overnight-ipad-641df58.xcresult on the Mac; screenshots exported there, but SSH timed out during download and a bounded retry. No iPad visual acceptance is claimed.
- Live providers and physical-device installation remain pending. No new question type was added and the stay-awake helper remains off.

## Speech output validation extended, pending Mac run

- Replaced OpenAI output's signature-only check with bounded RIFF/WAV chunk and sample validation. Truncated or inconsistent headers, duplicate format/data chunks, unsupported encoding and excessive duration are rejected before playback. No automatic retry or billing-path change was added.
- Two regression tests cover provider rejection without retry, valid PCM preservation, metadata padding and malformed size/format claims. They are written but unexecuted: an elevated SSH check to the Mac still timed out. The passing 269-test run predates this extension.
- No UI layout or question type changed. iPad screenshot validation and device installation remain pending; the stay-awake helper remains off.

## Combined Google audio bridge prepared

- Added disabled-by-default, sandbox-only Gemini Live connection/stream normalization with explicit model allowlists, session/payload authorization, bounded PCM input/output, duration watchdog, cancellation and no automatic reconnect. No live SDK/provider connection was made.
- Local speech-start events interrupt playback generations and suppress old output until provider acknowledgement. Input transcripts remain provisional; provider tools are rejected and this bridge has no grading, scheduling or repository access.
- Ten additional asynchronous fixture tests passed; the full server fixture suite now passes 25 tests. Native iPhone/iPad transport/playback/echo control, hosted accounting, SDK compatibility and live benchmarks remain pending. See server/google_cloud/LIVE-AUDIO.md.
- No new question type or UI layout was implemented; the stay-awake helper remains off.

## Durable sandbox voice accounting prepared

- Added persisted, account-scoped purchase grants, immutable rates, locked usage reservations, payload-bound dispatch records and idempotent settlement/release. Duplicate purchases and concurrent reservations cannot grant/spend credit twice. Production remains rejected and default access is disabled.
- Crashed/uncertain dispatches retain a hold and cannot automatically resend or release. Settlement can reuse verified usage without another provider call. No client preference, local voice path or personal key can mint/deduct managed credits through this ledger.
- Nine new local tests passed; the combined server fixture suite passes 34 tests. Temporary databases/fake verified receipts only; no Supabase wallet, Apple purchase or provider charge was made. Hosted auth/JWS verification, refunds, receipt reconciliation and app integration remain pending. See server/google_cloud/VOICE-LEDGER.md.
- No iPhone/iPad layout or new question type changed; the stay-awake helper remains off.
