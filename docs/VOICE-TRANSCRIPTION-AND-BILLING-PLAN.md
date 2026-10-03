# Voice review, transcription providers and payment specification

Status: implementation specification agreed on 4 October 2026. This document does not claim implementation or production readiness.

## Deliverable and product decisions

No application code, payment configuration or live charging will be changed as part of preparing this document. This newer specification supersedes conflicting voice and review behaviour in the existing voice documents.

Voice will be paid for all production accounts through two alternative paths:

| Path | Access and payment |
|---|---|
| Managed cloud transcription | Prepaid app credits; no monthly subscription required |
| Personal OpenAI key or local transcription | US$2/month voice subscription; no app-credit deductions |

A personal API key does not unlock voice without the subscription. Users pay OpenAI separately for personal-key usage. Their existing ChatGPT connection remains responsible for AI marking; audio transcription through that connection is not assumed supported.

During development, use sandbox purchases, test subscriptions and simulated credit balances. Real provider calls may still incur developer or personal-key costs. Production purchases and charging remain disabled until an explicit release configuration change.

## Providers, settings and informed selection

Introduce a transcription-provider interface shared by voice capture and review. Keep provider selection separate from the ChatGPT marking model.

Initial options:

| Model | Available payment paths | Guidance shown to users |
|---|---|---|
| GPT-4o Mini Transcribe | Managed credits or personal OpenAI key | Lower cost; benchmark medical terms and accents |
| GPT-4o Transcribe | Managed credits or personal OpenAI key | Higher cost; candidate when Mini needs frequent corrections |
| Google Chirp 3 | Managed credits | Dedicated recognition and vocabulary adaptation; higher standard cost |
| Whisper large-v3/turbo | Voice subscription | Offline transcription; model download, memory, battery and device-speed trade-offs |
| Parakeet through FluidAudio | Voice subscription | Local Swift integration; accuracy varies with model and recording conditions |

Default to managed GPT-4o Mini Transcribe. Select one active model per answer; allow changing models between answers. Do not silently switch to a paid provider or a different billing path after failure. Google personal credentials, Deepgram and AssemblyAI are deferred.

Settings will include:

- Provider/model selector, billing path, readiness and estimated usage price.
- Masked personal-key entry, validation, replacement and deletion. Store keys in device-only Keychain; exclude them from logs, backups, library sync and the managed backend.
- Download/delete controls and device compatibility checks for local models.
- A small question-mark icon inside the selection box, with an accessible label and at least a 44-point interaction target.
- A comparison sheet covering cost, offline availability, audio destination, speed expectations, technical vocabulary, downloads and device demands. Clearly label untested accuracy claims.
- A review preference: **Continue while processing** or **Wait for feedback**, defaulting to Continue. Changes apply to the next submission.

Cloud processing requires a clear first-use disclosure identifying where audio is sent. Preserve spoken mistakes, negations and self-corrections. Trim leading/trailing silence conservatively; exclude filler removal and accelerated audio from the first version.

Retain existing local question playback as an optional setting. No paid text-to-speech provider is added.

## Review and background processing

Persist an answer before advancing, including its card/content version, submission time, selected provider, payment path and marking account. Persist audio in protected, backup-excluded app storage until transcription succeeds.

For Continue mode:

- Advance immediately after submission is durably saved.
- Show a compact pending count and brief results: `Card title · Correct`, `Partial`, `Incorrect`, or `Check transcript`.
- Results must not steal focus or play feedback over the next answer.
- Exclude pending cards from the review queue. Permit up to ten unresolved submissions, with at most two transcription requests and one marking request running concurrently.
- At the pending limit, pause new voice submissions and offer feedback review or manual study.

For Wait mode, keep the submitted card visible until feedback or an actionable failure is available.

Exit review opens a summary prioritising incorrect, partial and unresolved answers. Include the transcript, reference answer, explanation, transcript correction, manual rating, assessment discussion and retry actions. Users can leave while work remains pending and reopen the summary later.

Add a durable pending-answer lifecycle: captured, transcribing, awaiting marking, marking, completed, needs attention or cancelled. Finishing a result must not depend on that card still being the current presentation.

Commit each successful assessment exactly once using the original answer time. Preserve current automatic rating mappings and manual overrides. Unclear transcription, missing evidence and provider failures produce no FSRS grade. Content edits or stale evidence require reassessment rather than overwriting a newer schedule.

Transcript corrections invalidate the old assessment and use existing review reconciliation to replace its scheduling effect safely. Superseded jobs cannot commit late results.

Keep processing while the app is foregrounded after review exit. On suspension, persist work and resume on reopening; do not promise continuous iOS background execution. Account switching pauses the prior account's jobs.

Delete audio after a successful transcript is durably stored. Failed audio remains available for retry for up to seven days, or until the user deletes it. Store transcripts and assessments as review evidence; do not sync raw audio.

## Billing, fee calculations and release controls

Use StoreKit 2 consumable top-ups and an auto-renewing voice subscription. Start with a nominal US$10 top-up granting US$10 in app credit. Display the actual localised StoreKit purchase price and explain that app credit is usage credit, not withdrawable cash.

Use the existing authenticated Engram account for production wallets and managed requests. Purchases, balances and usage are verified by a backend ledger; library backups and client preferences cannot mint credit. Keep sandbox and production ledgers separate.

Provide minimum service boundaries for purchase verification, wallet/entitlement retrieval, usage reservation, transcription submission and settlement. Use unique transaction and job IDs to prevent duplicate purchases or charges. Managed provider credentials remain server-side.

Define the proposed 20% operating margin as the share of net proceeds remaining after provider cost, before hosting/support:

`usage price = provider cost ÷ ((1 − commission) × (1 − 0.20))`

Illustrative USD calculations, excluding taxes and other operating costs:

| Item | 15% Apple commission | 30% Apple commission |
|---|---:|---:|
| Net proceeds from $10 purchase | $8.50 | $7.00 |
| Provider budget at 20% margin | $6.80 | $5.60 |
| Required provider-cost multiplier | 1.471× | 1.786× |
| Mini at estimated $0.003/min | $0.00441/min | $0.00536/min |
| Full at estimated $0.006/min | $0.00882/min | $0.01071/min |
| Google at $0.016/min | $0.02353/min | $0.02857/min |
| Net proceeds from $2 subscription | $1.70 | $1.40 |

Use 30% as the conservative planning default until Small Business Program approval is confirmed. Actual storefront taxes and App Store Connect proceeds must inform production rates; do not treat these examples as final settlement amounts. No separate card-processing fee is added on top of Apple's standard IAP commission.

Version usage rates and lock the rate when an answer is submitted. OpenAI's per-minute figures are estimates: settle token-billed requests from reported usage, not by assuming every provider bills duration identically. Use precise monetary accounting without rounding each short answer to a whole cent.

Reserve sufficient credit before managed processing, then settle successful transcription and release the remainder. Failed transcription and internal retries consume no additional customer credits. A successful transcript remains chargeable if later marking fails; retrying marking alone does not retranscribe or recharge. Personal-key usage never deducts app credits.

Purchased credits do not expire. Support pending purchases, transaction replay, refunds/revocations, cross-device wallet access and subscription expiry. Disabling production billing must not create free, unbounded managed-provider access.

Before release, configure products, confirm actual prices/proceeds, verify server purchase handling and deliberately enable production billing. Personal-key functionality is provider configuration, not a substitute payment mechanism for unlocking the app.

Sources: [Apple payment guidelines](https://developer.apple.com/app-store/review/guidelines/), [Small Business Program](https://developer.apple.com/app-store/small-business-program/), [OpenAI pricing](https://developers.openai.com/api/docs/pricing), [Google pricing](https://cloud.google.com/speech-to-text/pricing).

## Acceptance and validation

- Benchmark identical medical recordings across providers: drug names, doses, negations, accents, pauses and self-corrections. Measure correction frequency, latency and total answer time.
- Verify both review preferences, out-of-order results, exit/reopen, account changes, interrupted uploads, queue limits, stale cards and exactly-once scheduling.
- Verify transcript corrections cannot leave duplicate grades or late outdated assessments.
- Test sandbox purchases, duplicate transactions, insufficient funds, concurrent reservations, refunds, subscription expiry and cross-device balances.
- Confirm personal-key/local paths require the subscription and never deduct credits.
- Confirm failed jobs do not produce failure grades or duplicate charges.
- Verify accessible model-help controls, price disclosures, key isolation and audio deletion.
- Prove development builds cannot initiate production purchases and the production backend cannot accept test balances.

This document records the proposed US$2 subscription and US$10 top-up as launch targets; final StoreKit price points, tax-adjusted proceeds and provider rates must be verified before activation.
