# Understanding practice integration

Implemented 5 October 2026 on `akshat/learning-models`. Apple compilation and UI tests remain pending; the user has deferred them and the Mac is unavailable.

## Settings and questions

App defaults are account-specific and device-local. Each notebook may inherit them or save an override. Existing libraries decode without overrides. Defaults enable a separate understanding session, three alternatives plus the original, same-level variety, and foreground background batching of five submitted attempts. Alternatives are configurable from one to four. Existing FSRS recall remains independent and available offline.

The existing notebook menu opens practice and its native learning settings. Advanced controls explain each model's purpose, limitations and readiness. Unavailable models remain informational. Predictive components default Off; local evidence collection requires a separate explicit opt-in. Observe displays estimates without affecting rotation; Active permits prepared compatible predictions to influence selection. Preferences apply at session boundaries, preserving the configuration captured for each attempt.

Source-grounded variants are prepared through the existing assistant, saved once, and browsed offline. An independent AI check reviews sources, rubric, prerequisites, reasoning depth and specific Q-matrix skills. AI checks are task checks, not empirical calibration or proof that grading is reliable. Failed checks cannot enter scored sessions. Original/source changes invalidate availability; edited variants require a renewed check. Same-level explain/compare/apply/evaluate variety is the default. Explicit harder progression additionally requires a ready Active skill model and sufficient predicted performance; its threshold is a declared policy heuristic.

## Attempts and grading

Sessions persist question content, sources, reviewed mapping, configuration, provider identity, answer, known assistance, measured foreground answer time and grading revisions. Up to ten distinct variants rotate per session. Equal exposure counts use compatible Active skill predictions, then optional Active Rasch predictions; missing predictions safely fall back to deterministic rotation. Each purpose remains separate. Carousel browsing records exposure without a score. No exposure record is assumed to prove unfamiliarity.

Answers submit and continue immediately. Optional provisional grading uses an injected, already-installed and enabled local adapter. The repository has no executable Laya runtime adapter or supplied model; its control therefore remains informational/unavailable. No download or substitute grader is fabricated. Deeper review works independently through the existing enabled marking provider and selected model.

Automatic batches execute while the app is foreground, after the configured count, with a final flush when the session ends. Session-end-only batching is configurable. This is not an OS background execution guarantee. Requests include individual attempt identities, exact allowed sources and rubrics. Invalid rows fail independently. Provider/source changes mark attempts for attention instead of silently grading stale content. Async results must match the account/library lease.

Existing `LocalAnswerEvidence.validate` is the acceptance boundary. Provisional and deeper grades share one attempt identity. Accepted revisions persist before learner reconciliation, so cold restart can recover an interrupted evidence write. Corrections queue the same attempt and retain previous grades; disputed evidence stops training until reassessed. Explicit skill errors must belong to its mapping and accompany an incorrect result. No generated answer changes an FSRS card.

Typed drafts save on explicit Close and app backgrounding, preserving measured time without creating outcomes. Finish confirms abandonment of a nonempty unsent draft. Older draft timestamps cannot overwrite newer drafts. These saves do not guarantee recovery from termination before a save completes.

## Evidence and readiness

Local shared evidence is scoped to account and library, shared across its notebooks only through reviewed compatible identities. Unknown historical assistance, timing and mappings remain unknown. Opting out revokes collection for pending attempts; enabling it later does not backfill them. Newly observed unrevealed recall captures can record a delay only from an exact prior tracked question exposure.

DAS3H, BKT and dynamic Rasch personal fitting use actual eligible accepted outcomes and held-out reports. No production coefficients ship. A numerically eligible candidate may receive an explicit automated aggregate-report check through the existing provider; this does not authenticate imported provenance or establish scientific validity. Activation still requires readiness and compatible replay between attempts. DINA remains assessment-scoped: identifiable reviewed forms and permitted held-out learners are required. General notebook variants are not treated as complete DINA administrations.

The personal dashboard labels observed recall, unfamiliar performance, confirmed errors and measured time separately from model predictions. Unsupported comparisons say insufficient evidence. Credible comparisons require comparable baseline and delayed recall/novel-transfer forms, validated scoring, exposure and assistance records, duration, policy/configuration identity, corrections, sample counts, uncertainty and attrition. Randomized allocation and adherence records are needed for causal model comparisons. Community uploads, deployment gates and separate consent remain unchanged.

## Validation and remaining work

Final Windows validation on 5 October 2026: `scripts/Test-LearnerModels.ps1` PASS. The runner compiles real core/application/persistence boundaries, typechecks the actual controller in Swift 6 with compile-only platform signatures, parses SwiftUI syntax, and executes meaningful backend assertions against real vendored FSRS. It covers rotation, batches, correction/deduplication, draft recovery/stale writes, task-edit invalidation, consent, restart, scope isolation, replay/switching, fallbacks and unchanged card scheduling. All four synthetic fitting pipelines passed. It does not typecheck SwiftUI against Apple's SDK or simulate touch gestures. Known disposable compiler outputs/test data were removed; the reusable `.build` cache and app data were preserved. No substantial temporary storage was created.

Remaining release work: canonical Apple builds and user UI checks; a real installed Laya runtime adapter and task reliability evaluation; permitted calibration outcomes and supported DINA forms/cohorts; scientific report review and Rasch grid-sensitivity checks. Learner sidecars are local and are not included in existing library cloud sync/export. Retention/export UX and cross-process locking remain follow-up work. No new live inference was executed during development, no models downloaded, and no commits or pushes made.
