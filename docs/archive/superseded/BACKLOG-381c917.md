# Engram — remaining work

> Superseded snapshot of main `381c917`, retained after newer implementation reached main on 5 October. Use the [current backlog](../../BACKLOG.md) and [status](../../CURRENT-STATUS.md).

Reviewed 5 October 2026 against main `381c917`. This is the active list of unfinished work extracted from historical plans and reviews. Source inspection and existing reports establish the classifications below; no app tests were rerun for this documentation cleanup. Work on other branches, including `akshat/overnight-learning-system`, is not counted as delivered on main.

## Which requirements apply

Use the newest dated requirement when documents conflict. Later dated follow-ups within a document override its earlier sections. Historical plans remain in [the archive](../README.md) for context, not as competing instructions. Undated proposals do not override dated requirements.

The [4 October consolidated requirements](../../OVERNIGHT-IMPLEMENTATION-REQUIREMENTS.md) extend and override conflicting parts of the [4 October voice/payment specification](../../VOICE-TRANSCRIPTION-AND-BILLING-PLAN.md). In particular, Google BYOK, cloud speech output and a feature-flagged combined-audio adapter are now requested. The agreed billing rules remain in force. Existing source behavior is evidence of implementation, not authority to override newer requirements.

Superseded requests are excluded: Library Gallery/List and Activity Bars/Line switches; the old one-time BYOK unlock/free-production-voice pricing; old fixed-axis/equal-review-step graph layouts; first-build prohibitions on AI, PDF and cloud work; and previously corrected import defects. The latest graph direction uses calendar time, a one-month default viewport and a dynamic visible-window Y-axis.

## Features and improvements still needed on main

### Accounts and connections

- [ ] Put login choices directly in AI & Connections and provide a compact Manage ChatGPT submenu. The current unified account destination is groundwork; it does not complete the newer direct-settings flow.
- [ ] Add identity linking that preserves the Supabase user ID and libraries, explicitly separate from switching accounts. Never merge existing accounts by similar email addresses.
- [ ] Offer verified local-library transfer when a ChatGPT-only local profile establishes a cloud identity; retain original data until transfer is verified.
- [ ] Deduplicate and migrate ChatGPT registrations by verified issuer/subject, preserve active consent, remove superseded credentials, and serialize sign-in/out/refresh against interrupted operations.
- [ ] Scope conversation/model defaults and local voice preferences to app accounts where they still use device defaults.
- [ ] Complete actionable Apple/provider setup states, including handling unsupported preview builds without exposing raw authorization errors.

Source: [latest account requirements](../../OVERNIGHT-IMPLEMENTATION-REQUIREMENTS.md#3-unified-sign-in-and-account-management). Existing baseline: [accounts and libraries](../../ACCOUNT-AND-LIBRARIES.md).

### AI providers and voice

- [ ] Add Google Gemini and OpenAI API connections through the shared provider transport; support masked BYOK validation/replacement/deletion in device-only Keychain.
- [ ] Use the same retrieval, evidence checks and application actions across providers for chat, grading and PDF generation. Select conversation, grading, transcription and speech-output models by capability without silent provider/payment substitution.
- [ ] Prepare Vertex/GCP integration and deployment instructions with server-only service credentials.
- [ ] Introduce managed and personal-key transcription, defaulting to managed GPT-4o Mini Transcribe. Preserve the specified alternatives: GPT-4o Transcribe, Google Chirp 3, Whisper large-v3/turbo and local Parakeet, with model readiness/download/help/cost disclosures.
- [ ] Add optional Google/OpenAI speech output while retaining local output as the default unless explicitly changed. Prepare a feature-flagged Gemini Live adapter whose speech cannot directly award grades.
- [ ] Complete reliable interruption, echo suppression and stale-speech cancellation across the new providers. Preserve negation, self-correction and the learner's actual mistakes.
- [ ] Finish background/screen-lock, Bluetooth, call interruption and route-change behavior before describing voice as hands-free-ready; retain an explicit synthesis fallback if Kokoro is unstable.

Sources: [latest provider/voice requirements](../../OVERNIGHT-IMPLEMENTATION-REQUIREMENTS.md#4-ai-providers-and-voice), [transcription details](../../VOICE-TRANSCRIPTION-AND-BILLING-PLAN.md#providers-settings-and-informed-selection), and [older device-operation gaps](VOICE-AND-MCQ-REVIEW-SPEC.md#cost-privacy-and-device-operation). Local foreground voice already exists; this list covers the remaining expansion and readiness work.

### Durable answer processing

- [ ] Implement Continue while processing (default) and Wait for feedback. Persist answers, original submission time, question/content versions, provider, billing path and grading identity before advancing.
- [ ] Add a restartable captured → transcribing → awaiting marking → marking → completed / needs attention / cancelled lifecycle, independent of the current card presentation.
- [ ] Limit unresolved submissions to ten, with two transcription workers and one marking worker; prevent pending cards from recurring immediately.
- [ ] Show a compact pending indicator and durable summary of incorrect, partial and unresolved answers. Results must not steal focus or speak over the next answer.
- [ ] Resume jobs after review exit or app restart; pause prior-account jobs during account changes. Do not promise continuous iOS background execution.
- [ ] Reconcile corrected transcripts and their scheduling effect; stale/superseded jobs cannot commit. Grade supported answers exactly once using original answer time; uncertainty and failures remain ungraded.
- [ ] Keep raw audio protected and excluded from backups/sync. Delete it after durable transcription; retain failures for retry for at most seven days or until explicit deletion.

Source: [review/background processing specification](../../VOICE-TRANSCRIPTION-AND-BILLING-PLAN.md#review-and-background-processing). Persisted typed attempts and atomic Next already exist; a general asynchronous voice-job queue remains separate work.

### Billing foundations

- [ ] Prepare StoreKit 2 purchase/restore flows and backend purchase verification, entitlements, wallets, usage reservations and settlement. Keep production charging disabled until configured and validated.
- [ ] Implement the newer payment rules: managed cloud voice uses prepaid credits; personal-key/local voice uses the planned US$2/month entitlement and never deducts app credits.
- [ ] Separate sandbox and production ledgers; use authoritative accounting and unique transaction/job IDs for replay/concurrency safety. Backups and preferences cannot mint balances.
- [ ] Disclose/version transcription and optional speech-output rates. Failed transcription/internal retries cannot double-charge; successful transcription remains chargeable if grading later fails, and grading-only retries do not retranscribe.
- [ ] Handle insufficient credit, pending purchases, refunds/revocations, subscription expiry and cross-device access. Purchased credits do not expire.
- [ ] Configure products, secrets, limits and actual storefront/provider costs before activation. The US$10 top-up and illustrative rate calculations are planning targets, not verified launch prices.

Sources: [billing requirements](../../OVERNIGHT-IMPLEMENTATION-REQUIREMENTS.md#5-billing-foundations-and-release-boundaries), [payment specification](../../VOICE-TRANSCRIPTION-AND-BILLING-PLAN.md#billing-fee-calculations-and-release-controls).

### Testing content

- [ ] Provide a Testing folder with AWS MCQ, AWS short-answer/voice and maths examples, including long content, paraphrases, partial answers, negations and deliberately wrong responses.
- [ ] Independently check original AWS questions against official documentation; include reference answers, explanations and evidence links. Do not bundle private slides or protected exam questions.
- [ ] Use stable sample IDs and repeat-import behavior that avoids duplicates and never silently overwrites user edits. Offer a one-time authenticated-account import through normal application/sync operations.
- [ ] Validate canonical answer identity through shuffled onscreen/spoken choices. Basic MCQ shuffling already exists; the complete testing-content workflow does not.

Source: [latest testing-deck requirements](../../OVERNIGHT-IMPLEMENTATION-REQUIREMENTS.md#6-testing-decks-and-account-import). The existing bundled AWS notebook and DEBUG fixtures do not complete this deliverable.

### Mathematical input and calculator policy

- [ ] Add the full structured equation keyboard: fractions, powers, roots, algebra, inequalities, brackets, Greek, trigonometry/logarithms; derivatives, integrals, limits, sums/products, matrices/vectors, sets, piecewise expressions and probability/statistics (factorials, permutations/combinations, binomial, normal and Poisson notation).
- [ ] Support nested placeholders, cursor movement, readable preview, portable source and compact categories on iPhone, plus hardware input on iPad. Existing math rendering is not equation authoring.
- [ ] Add deck calculator policies Off / Basic / Scientific. Record tool use and award normal grades when calculator use is allowed; AI reveals remain assisted.
- [ ] Add backward-compatible numeric-response metadata, explicit tolerances and deterministic supported numeric grading. Keep unsupported equation equivalence for manual/evidence-backed feedback.

Source: [latest mathematical-input requirements](../../OVERNIGHT-IMPLEMENTATION-REQUIREMENTS.md#7-full-mathematical-equation-entry-keyboard). A CAS solver and unrestricted expression execution are outside the requested scope.

### Tutor specification

- [ ] Specify tutor invitations, up to five initial active students, assigned decks, due dates and assigned-work progress views.
- [ ] Define assigned-work-only permissions, removal/revocation, retention and age/guardian-consent handling; personal libraries/chats remain private.
- [ ] Specify evidence-linked AI misconception/progress suggestions and a capped insight allowance. Check hosting/provider costs before activating the provisional A$3 per tutor/month target.

Source: [latest tutor requirements](../../OVERNIGHT-IMPLEMENTATION-REQUIREMENTS.md#8-tutor-feature-plan-before-full-implementation). Deliver the specification first; a complete tutor platform is not an initial-stage requirement.

### UI, platform and assistant follow-ups

- [ ] Complete the newer pill/text action and flat-settings-row audit, preserving the approved glass chat bubble, themes, touch targets and iPhone quiz composition.
- [ ] Complete later wide-iPad/Mac passes for Today, assistant, document reading with hierarchy/citations, Activity and Settings. First-pass landscape Library/deck support exists.
- [ ] Extend assistant parity to review subcontrols currently reached only by navigating to the owning screen.
- [ ] Evaluate optional vector memory-growth artwork and its scheduling-evidence metric before integration. Keep it opt-in, interruptible and compatible with Reduce Motion; the historical design preview is not a shipped feature.

Sources: [new UI requirements](../../OVERNIGHT-IMPLEMENTATION-REQUIREMENTS.md#2-minimalist-ui-requirements), [remaining iPad passes](IPAD-LANDSCAPE-SUPPORT.md#following-passes), [assistant parity](UNIFIED-IMPLEMENTATION-STATUS.md#assistant-action-map), [optional growth proposal](REVIEW-LAYOUT-THEMES-AND-GROWTH-PLAN.md#5-optional-memory-growth-artwork--later-prototype).

## Implemented foundations needing configuration or acceptance

These are verification/configuration gaps, not requests to rebuild the existing features.

- [ ] Configure and validate hosted Google/Apple/email identity, callbacks, Apple provisioning and email verification delivery. Recheck deployment state rather than treating old planning notes as live provider status.
- [ ] Keep the hosted cloud pilot off until two physical app devices and two users pass synchronization, invitations, revocation, conflicts, offline edits, named-library isolation and private-document acceptance. SQLite/cloud code and local server tests already exist.
- [ ] Exercise live ChatGPT account/model discovery, tool calling, streaming, paraphrase/dispute grading and PDF generation. DEBUG fixtures do not prove provider behavior or answer quality.
- [ ] Measure voice accuracy, false submissions, opening-word preservation, interruption latency, echo, noisy audio, accents/technical terms, repeated synthesis and battery use on hardware.
- [ ] Exercise complete VoiceOver/keyboard traversal, largest text, rotation/narrow windows, theme changes, Reduce Motion/Transparency, increased contrast and older-OS fallbacks on iPhone/iPad/Mac.
- [ ] Verify native backup/restore, corrupted-startup recovery, Anki migration and actual image/audio playback through platform UI with representative nonempty libraries and failure/cancellation cases.
- [ ] Profile large histories/libraries, image decoding, imports/exports, cancellation, memory pressure and sustained reviews on baseline Apple hardware. SQLite currently stores snapshot payloads; the old file-adapter benchmarks do not establish current mobile scalability.
- [ ] Validate staged account/provider/job/payment/math/sample changes using the concrete cases in the latest consolidated specification before marking their backlog items complete.

Evidence boundaries: [account report](../../ACCOUNT-AND-LIBRARIES.md#verification-and-boundaries), [integrated report](UNIFIED-IMPLEMENTATION-STATUS.md#validation-evidence), [PDF limits](../completed/PDF-LEARNING-VALIDATION.md#practical-limits), [first-build acceptance gaps](HANDOFF.md#concrete-remaining-acceptance-checklist), [historical performance limits](../benchmarks/PERFORMANCE.md#limits-and-follow-up).

## Longer-term candidates, not current delivery commitments

Retained from the original product vision where not superseded by later requirements:

- Cumulative/multi-concept assessments, adaptive prerequisite questioning, recurring misconception tracking and separate recall/application evidence.
- Confidence/response-time evidence and helpful workload/weak-topic recommendations; never infer understanding/mastery from ordinary review counts alone.
- Semantic search across resources/conversations, concept relationships/knowledge graphs and broader document ingestion including OCR/diagram understanding.
- Local model-server/hybrid routing with an enforced never-send-resources-to-cloud preference; externally authenticated learning tools/MCP with controlled mutations.
- Rich notebook authoring and multi-select question semantics beyond the existing basic/single-choice flow.
- Automatic sibling burying, parameter optimization/alternative production schedulers with explicit migrations, and multiwindow coordination.
- Wider Anki formats/templates/image occlusion and media support only through explicit compatibility work; current rejected formats are disclosed boundaries, not release promises. Assess safe unused-media cleanup separately.

Sources: [original product vision](ENGRAM-PLAN.md), [original Library proposals](iphone-library-product-brief.md), [compatibility boundary](../../ANKI-COMPATIBILITY.md), [media boundary](../../MEDIA-COMPATIBILITY.md), [architecture](../../ARCHITECTURE.md).
