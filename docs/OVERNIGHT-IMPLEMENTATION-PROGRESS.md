# Overnight implementation progress

Goal: implement the complete requirements in OVERNIGHT-IMPLEMENTATION-REQUIREMENTS.md for iPhone and iPad, including the subsequently requested ordering questions. Configuration-dependent work must be recorded and deferred while independent implementation continues.

## Delivery checklist

- [x] Merge reviewed branch and requirements into main, preserving commits.
- [x] Create and push akshat/overnight-learning-system from merged main.
- [x] Inline account controls, linked-identity operations and shared capsule action styles.
- [ ] Complete the remaining app-wide shape audit and live linked-account acceptance.
- [x] Deduplicate ChatGPT registrations and prevent accumulation on reconnect (migration/replacement tests).
- [ ] Add provider-neutral Google/OpenAI connections, secure BYOK and Vertex preparation.
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
