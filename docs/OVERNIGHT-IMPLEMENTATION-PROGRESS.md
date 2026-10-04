# Overnight implementation progress

Goal: implement the complete requirements in OVERNIGHT-IMPLEMENTATION-REQUIREMENTS.md for iPhone and iPad, including the subsequently requested ordering questions. Configuration-dependent work must be recorded and deferred while independent implementation continues.

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
- [ ] Implement ordering questions, editor, review controls and samples.
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
