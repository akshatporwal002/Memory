# Feature specification: modular learning models

**Decision date:** 5 October 2026 (Australia/Melbourne).  
**Status:** selected product direction; implementation pending. This document records the user's model choices and switcher requirements. It does not claim that any new component has been implemented or that the combined system has demonstrated superior learning outcomes.

## 1. Outcome

Provide a persistent learner model with interchangeable components for recall, skill performance, difficulty and diagnosis. Users can keep ordinary fixed-question study or opt into generated adaptive practice. Optional components can be disabled without losing answer history or resetting existing recall schedules.

Use the selected models as the preferred configuration. Alternatives are available only after their adapters, fitting, compatibility and validation are implemented. An extensible architecture does not mean every listed model must ship in the first release.

Research context and evidence: [literature review](</Users/akshatporwal/Documents/projects/Memory/literature review.md>). The original `FSRS + KT + IRT + Semantics + LLM` idea becomes a concrete configuration here; DINA adds optional diagnostic assessment. A Q-matrix supplies question-to-skill mappings, not a complete semantic/prerequisite graph.

## 2. Selected defaults

Distinguish the preferred model from whether its optional feature is enabled. Dynamic IRT remains opt-in. Existing libraries retain their study settings and schedules; installing this feature does not enroll users in generated practice, model downloads, cloud processing or research collection.

| Role | Preferred model / behavior | Initial activation and fallback |
|---|---|---|
| Skill mapping | Reviewed Q-matrix | Required for skill-aware estimates. Missing or unreviewed mappings leave the task outside validated skill/diagnostic updates. Ordinary card review remains available. |
| Recall prediction and scheduling | FSRS | Remains the active review scheduler. Preserve the pinned FSRS-6 configuration initially; upgrades are separate, versioned changes. |
| Ongoing skill performance | DAS3H | Default tracker for supported skill-aware practice once a validated fitted configuration is available. During cold start, expose limited evidence rather than invented proficiency. |
| Difficulty adaptation | Dynamic IRT; initially investigate a dynamic Rasch-style formulation | Off by default. When enabled, use only a validated, calibrated model and supported item families. Off/unavailable uses reviewed difficulty bands or fixed questions. |
| Diagnostic assessment | DINA | Preferred diagnostic model where the domain has a validated Q-matrix and adequate assessment coverage. Diagnosis can be disabled; lack of readiness must not block ordinary study. |
| Review policy | FSRS determines due recall items | Adaptive selection operates within explicitly defined review opportunities; it does not silently replace FSRS timing. |
| Question supply | Fixed questions for fixed practice; generative AI for user-selected adaptive generated practice | Preserve fixed practice as the fallback. AI-generated tasks require sources, rubric and checked mappings before use for validated measurement. |
| Immediate marking | Deterministic checks where applicable, otherwise local Laya on validated task types | Laya feedback is provisional and optional; retain existing manual/deferred assessment if unavailable. |
| Deeper assessment | Selected AI grading provider, with existing acceptance/correction flow | Supplies reasoning, partial credit and bounded learner evidence. Follow current provider, funding, consent and no-cloud preferences. |
| Integrated alternative | None initially | PSI-KT/Deep-IRT remain later research configurations, not additional default layers. |

Do not label DAS3H predictions, DINA attributes, IRT proficiency and FSRS retrievability as interchangeable “mastery percentages.” Each output names what it estimates, its evidence and uncertainty.

## 3. User-facing modes

| Mode | Behavior |
|---|---|
| Fixed practice | Reviewed cards/questions with FSRS timing and the existing supported assessment flow. AI generation is disabled. Supported learner estimates may be shown separately if enabled. |
| Adaptive generated practice | FSRS identifies due review opportunities; the selection policy uses supported skill information and optional calibrated difficulty to request source-grounded generated tasks. |
| Advanced / research configuration | Exposes implemented model alternatives, readiness, observation-only comparisons and configuration versions. Research upload/assignment requires its existing separate consent and authorization. |

Generation and adaptive selection are separate capabilities internally. This allows later adaptive selection from reviewed questions without changing the user's selected fixed/generated distinction now.

If generation fails or sources/mappings cannot be validated, offer a reviewed question or defer the adaptive task. Do not penalize the learner or fabricate a grade. Generated practice must not silently incur unsupported provider spending or send device-only content to a cloud service.

## 4. Model switchers

Use one selected decision-making model per role. Other models can run in observation-only mode for comparison. Do not combine their outputs by averaging unrelated scores or multiplying estimates as independent evidence.

| Category | Initial choices to implement | Later adapter candidates | Required switching treatment |
|---|---|---|---|
| Skill tracker | DAS3H, BKT; skill-aware influence on/off | PFA, AKT, simpleKT; DKT/DKVMN/SAKT as research baselines if justified | Fit the destination model, replay compatible history, validate readiness, then activate between attempts/sessions. |
| Difficulty | Off, selected dynamic IRT when ready | Static Rasch, 2PL, multidimensional variants | Calibrate and identify the destination scale; never copy an ability score between models. “Dynamic” and “multidimensional” are properties that can coexist, not necessarily exclusive model families. |
| Diagnosis | Off, DINA | G-DINA | Require compatible reviewed mappings and adequate diagnostic coverage; rebuild estimates for changed assessment designs. |
| Recall scheduler | FSRS initially | HLR or another scheduler only when implemented and validated | Preview and explicitly apply a controlled schedule migration; preserve original states/history and backup recovery. |
| Immediate assessment | Supported deterministic checks, Laya off/on | Other validated local classifiers | New attempts use the selected configuration; in-flight attempts retain their recorded assessment versions. |
| Deeper assessment | Existing supported AI providers/manual path | Additional validated providers | Record provider/model/rubric version; a switch alone does not retroactively regrade history. |
| Question supply | Reviewed bank, generative AI mode | Controlled templates | Apply to future tasks; preserve previously presented question identities and content versions. |
| Integrated research preset | Separate components | PSI-KT, Deep-IRT | Declare which roles are replaced together. Do not insert an integrated model into one dropdown while leaving conflicting components active. |

Show unavailable candidates as informational only if helpful; do not expose nonfunctional choices as usable models.

## 5. Off, Observe and Active

Optional predictive components have distinct execution states:

- **Off:** no inference or training for that component; no influence on practice. Preserve prior state/history under the applicable retention settings.
- **Observe:** make predictions and evaluate them locally, but do not select tasks, alter schedules or affect displayed committed grades. Observation alone does not authorize research upload.
- **Active:** use the selected model through a defined practice policy after readiness checks pass.

On reactivation, rebuild or advance from compatible accepted history and account for elapsed time before reporting current estimates. Do not display a stale saved estimate as current.

Scheduler replacement is a migration, not an ordinary on/off toggle. Disabling skill adaptation falls back to FSRS fixed review; it does not disable FSRS or reset cards.

## 6. Settings presentation

Use plain-language controls with model names available in their details:

- Practice mode: Fixed / Adaptive generated.
- Skill-aware practice: Off / On; selected tracker defaults to DAS3H.
- Adaptive difficulty: Off / On; selected model defaults to dynamic IRT when supported.
- Diagnostic profile: Off / On; selected model defaults to DINA when supported.
- Immediate local feedback: Off / On; Laya where validated.
- Advanced model comparison: implemented alternatives and Observe mode.

Each model detail includes a concise explanation, strengths, limitations, evidence type, required data, device/cloud requirements, readiness, version and expected effect on practice. Link the literature review. Use labels such as “prediction evidence” and “learning benefit not yet established”; do not imply that the exact combination is proven better.

Show “Not enough calibrated questions,” “Preparing model,” or “Limited evidence” where appropriate. A switch should explain its concrete consequence, such as changed future difficulty selection or schedule migration. Avoid false precision and unexplained score changes.

Persist configuration per learner/account and named library. A library default applies to its notebooks; optional explicit notebook overrides can narrow the scope, but account changes must not carry another learner's model state. Record the effective configuration on every attempt. If sync is enabled, incompatible/stale changes must not overwrite newer accepted state silently.

## 7. Adaptive review flow and model boundaries

1. FSRS identifies a repeatable recall item due under the current queue/settings policy.
2. In fixed mode, present the reviewed item. In adaptive generated mode, use its reviewed skill mapping to define eligible targets.
3. DAS3H may inform target/coverage selection. This is an explicit Engram policy to validate, not an automatic property of FSRS or DAS3H.
4. If dynamic IRT is active and ready, use calibrated proficiency/difficulty information. Otherwise use reviewed task bands or a fixed task; an LLM's requested difficulty is not measured difficulty.
5. Generate and validate question content, answer/rubric, sources, item-family identity and proposed skill mapping. A newly generated mapping is not “reviewed” merely because the generator produced it.
6. Save the question and model configuration; obtain pre-response predictions before any component sees the response.
7. Save the learner's original answer, timestamp and assistance status before supplying feedback.
8. Provide deterministic or provisional Laya feedback; perform deeper assessment under the existing acceptance flow.
9. Commit eligible accepted evidence once per attempt; update the appropriate components and retain provenance.

A novel application task is distinct from a repeatable recall card. Initial implementation must not use its success to reset a related card's FSRS schedule. Where no reviewed recall-equivalence rule exists, offer the original recall check or leave it due. Any later equivalence rule is separately versioned and validated. Distinguish application practice from completion of the due recall item in the UI and research data.

DINA consumes eligible diagnostic assessments with sufficient coverage. Do not automatically infer all attributes from a final answer to one multi-skill question. Optional graphs must not award direct mastery evidence to neighboring concepts without a specified validated model.

## 8. Evidence, assessment and replay

Store one durable attempt event with stable identifiers and versioned derived assessments. Minimum information needed for supported models includes:

- Learner/account, library, question ID/version, item-family ID and attempt ID.
- Reviewed skill mapping/Q-matrix version, including review status and applicability.
- Presentation/submission timestamps, duration and elapsed-time context.
- Original response, input modality and assistance/hints/source-lookup status, subject to existing storage/consent boundaries.
- Rubric and assessment versions, grader identity, provisional/final/accepted/disputed/ungraded status, partial-credit dimensions and correction links.
- Effective model/policy configuration, parameter/fitting version and pre-response predictions.
- Direct versus inferred evidence, readiness and calibration/uncertainty metadata where available.

Use existing answer-attempt and correction records where possible; extend rather than duplicate them. Research export remains a separate permitted projection. Missing historical fields remain unknown, not fabricated. Do not retrofit skill tags or unassisted status onto imported history as if originally observed.

Laya and deeper AI assess the same attempt. The later result revises the provisional assessment and must not count as a second retrieval. Several models can legitimately update from that event; their correlated estimates are not independent confirmations.

Pending, failed, ambiguous and disputed assessments do not automatically commit learner/schedule changes. Preserve existing explicit acceptance boundaries. Corrections invalidate and replay affected derived state, with deterministic ordering and idempotent application. Retain original pre-response predictions for honest evaluation even when grading is corrected later.

FSRS ratings, rubric partial credit and skill outcomes require explicit versioned conversion policies. A grader's confidence is not validated measurement reliability. Neither Laya nor a deeper grader directly mutates learner states outside the application transaction boundary.

## 9. Safe switching and persistence

“Hot-swappable” means the app can prepare and activate a compatible replacement without losing data or interrupting an attempt. It does not mean arbitrary latent scores can be transferred unchanged.

1. Snapshot destination choice and check capabilities, domain, data, fitting resources and consent.
2. Prepare the destination from compatible accepted evidence, retaining the active model meanwhile.
3. Track the library revision. Catch up or rebuild if new attempts/corrections arrive during preparation.
4. Validate the destination and its policy dependencies; show any effect requiring migration review.
5. Activate atomically at an attempt/session boundary. An in-flight question keeps its original grading and selection configuration.
6. Keep recoverable previous state/configuration. Failure or cancellation leaves the active model intact.

Version model IDs, implementations, schemas, parameters, fitting procedures, mappings and policies. Native backup/restore retains supported configurations and states alongside original evidence. Import/export reports unsupported components accurately; Anki-compatible recall exports must not pretend to encode the full concept learner model.

Swapping back must catch up the old model or replay it from accepted history. Off does not erase state. Explicit deletion and any research retention rules remain separate controls.

## 10. Architecture direction

Reuse the existing `Scheduler`, `MemoryEstimating`, versioned `ScheduleState`, attempt/assessment records and review correction/replay foundations. Relevant current source: [contracts](/Users/akshatporwal/Documents/projects/Memory/Sources/LearningCore/Contracts.swift), [FSRS adapter](/Users/akshatporwal/Documents/projects/Memory/Sources/SchedulingAdapters/FSRSScheduler.swift), [review reconciliation](/Users/akshatporwal/Documents/projects/Memory/Sources/LearningCore/ReviewReconciliation.swift).

Introduce bounded interfaces for skill prediction, difficulty measurement, diagnosis, question selection, generation and assessment. A model registry describes supported inputs, outputs, readiness, training requirements, state compatibility and fallback policy. Do not make optional AI infrastructure a prerequisite for fixed offline study.

Parameter training and calibration need a specified data source, fitting objective, validation split and reproducible artifact. Shipping a formula with arbitrary coefficients is not a trained DAS3H/dynamic IRT implementation. Cold-start priors and any pooled configurations require documented provenance and evaluation; local personalization and research uploads have separate permission boundaries.

## 11. Implementation stages

1. **Foundations:** shared accepted evidence, reviewed mappings, versioned configuration/registry, Off/Observe/Active, replay and persistence. Preserve FSRS behavior.
2. **Interpretable tracking:** DAS3H and BKT fitting/inference, shadow comparisons, calibrated outputs and model switcher. Validate before active selection.
3. **Adaptive practice:** source-grounded generation, reviewed mapping workflow, explicit selection policy and fixed-question fallback; maintain separate recall/application evidence.
4. **Difficulty and diagnosis:** optional dynamic IRT and DINA, each with readiness checks, calibration/test design and fallbacks.
5. **Assessment integration:** Laya provisional feedback followed by deeper accepted assessment; coordinate with the existing Laya backlog item.
6. **Additional alternatives:** add only adapters justified by evaluation. Joint models belong to separate integrated presets.

Stages can share groundwork, but active use must wait for the relevant validation. This document specifies staged implementation; it does not authorize production research upload, paid provider calls or infrastructure activation beyond existing approvals.

## 12. Acceptance criteria

- [ ] Default supported configuration selects reviewed Q-matrix, FSRS and DAS3H; dynamic IRT is optional/off initially, DINA is the selected diagnostic option, and fixed/generated mode respects user choice.
- [ ] Existing FSRS schedules, histories, corrections, library isolation and fixed offline study remain intact.
- [ ] Switching DAS3H/BKT preserves accepted evidence, prepares replacement state and applies atomically; failure/cancellation does not disrupt study.
- [ ] Off stops model execution/influence; Observe cannot change grades, task selection or schedules; reactivation handles elapsed time and intervening corrections.
- [ ] Unsupported/cold-start models display readiness limits and use defined fallbacks without invented scores.
- [ ] Dynamic IRT uses linked/calibrated questions or supported families; generated difficulty labels are not presented as measured difficulty.
- [ ] DINA is enabled only for supported diagnostic designs; mappings and coverage are validated.
- [ ] Generated application success does not silently complete/reset the associated FSRS card.
- [ ] Provisional/final grading, feedback assistance and corrections remain one attempt; retries, concurrent updates and replay do not double-count it.
- [ ] Native backup/restore and allowed sync retain versioned configuration/evidence; unsupported imports/exports are disclosed.
- [ ] Model comparisons hold out learners/question families as appropriate, prevent future/multi-skill leakage, and report prediction/calibration separately from learning outcomes.
- [ ] Laya grading is validated against adjudicated marks, including fluent incorrect answers, negation, contradictions, partial answers and unseen families; actual device memory/latency/battery are measured.
- [ ] Controlled delayed, unassisted recall/application studies compare FSRS baseline, DAS3H-informed practice and optional difficulty adaptation before superiority claims.

Follow repository build/cache and simulator rules during implementation. Documentation creation needs no build; no models, runtimes, dependencies or simulator changes were made to create this specification.
