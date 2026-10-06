# Modular learner models: backend implementation

Implemented on `akshat/learning-models` in the Windows checkout, 5 October 2026. UI/device testing is deferred at the user's request. The requested Mac checkout is unreachable; its `feat_learning_models.md`, `literature review.md` and original backlog must be reconciled with this supplement before integration there. No commits, pushes, deployments, paid calls, downloads or uploads were made.

## Evidence, mappings and persistence

Shared append-only evidence records one logical attempt with provisional/final/corrected/retracted revisions. Stable reviewed question-content identity is separate from card scheduling/concurrency revisions. Before-answer captures freeze known configuration/policy metadata. Unknown historical assistance, mappings, exposure, duration and correctness remain unknown.

Backend Q-matrix review, graph retrieval, mapping correction and explicit skill-error labeling are available. The graph contains reviewed question-to-skill edges, without inferred prerequisites. Mapping corrections require exact captured content and invalidate incompatible states/artifacts. Wrong multi-skill answers do not automatically mark every skill wrong.

Atomic account/library persistence includes the legacy default library, optimistic revisions, scope/schema checks, captures, candidates and archived states. Use one repository actor per directory; cross-process write locking is not supplied. The local store is not enrolled in cloud sharing or research uploads.

## Models and fitting

| Component | Implemented backend | Limits |
| --- | --- | --- |
| FSRS | Existing recall scheduler and review policy | No learner-model replacement or application-answer resets |
| DAS3H | Logistic prediction, expanding time windows and sparse ridge fitting | Embedding dimension zero; personal fit; known reviewed items |
| BKT | Single-skill tracing and penalized sequence maximum-likelihood fitting with multiple starts | Accepted unassisted binary outcomes; single-skill mappings |
| Dynamic Rasch | Finite-grid Bayesian filtering; anchored item difficulties, fitted initial distribution and estimated random-walk variance; static alternative considered | One dimension; truncated grid; conditional uncertainty; connected repeated items required |
| DINA | Assessment-scoped mastery posterior and EM fitting of profile priors/slip/guess | Supported identifiable Q designs, complete training administrations and held-out learners |

Rasch is a simplified state-space implementation, not the full dynamic IRT model in the cited paper. Grid sensitivity requires scientific review before deployment. DINA inference supports at most 10 skills and fitting at most 8. Its conservative known-Q gate requires an identity block, three measurements per skill and distinct remaining columns. These structural checks do not establish assessment validity.

All four families have actual local coefficient-fitting pipelines. Optimizer seeds, regularization and evaluation thresholds are reported policies, not supposedly fitted coefficients. No production calibration artifacts are bundled. Synthetic test fixtures never become user defaults.

Reports persist convergence, exact evidence IDs/revisions, split policy, sample counts, held-out log loss against a constant baseline, Brier score and reliability bins/calibration error. BKT/DAS3H/Rasch use chronological prequential validation; DINA holds out learners. Current target outcomes are scored before updating state. Duplicate attempts, double-counted correction revisions, leaking splits, unknown assistance and unsupported designs are rejected. Numerical eligibility allows explicit provenance/task review; it does not establish learning superiority. Imported reports are declarations, not cryptographically authenticated evidence.

See [local fitting workflow](LEARNER-MODEL-FITTING.md).

## Switching and study integration

Schema-versioned configuration has a monotonic revision. Preferred selections are FSRS, DAS3H, BKT alternative, dynamic Rasch and DINA. Optional purposes default **Off**, recording defaults disabled, and existing settings/consent remain untouched.

`StudyService` accepts optional scoped learner-store/account dependencies. Existing callers retain their behavior. Backend APIs cover opt-in collection, reviewed questions, durable captures, measured metadata, fitting/import/review, practice controls, catalog readiness, predictions and switching. The UI shell now injects a stable scoped store and exposes native notebook overrides/app defaults, fitting/readiness controls, observed dashboard and separate understanding sessions. See [integrated workflow](UNDERSTANDING-PRACTICE.md).

- Off preserves evidence/archive state and provides no predictive practice influence.
- Observe exposes prepared predictions while preserving practice order.
- Active skill predictions can order independent application questions using an explicit target-probability heuristic. It is not claimed optimal. Rasch/DINA expose difficulty/diagnosis; neither changes FSRS scheduling.

Replacement models replay their own compatible history before activation between attempts/sessions. No latent scores are transferred. Deactivation is immediate. Corrections/new evidence invalidate stale state; eligible same-model replay can refresh at a safe boundary, otherwise Active falls to Observe. Corrected fitting-source revisions invalidate the candidate and require refitting/review. Unavailable catalog models are informational.

The observing repository reconciles registered durable captures with committed accepted reviews. A learner-write failure does not roll back a successful FSRS commit; cold restart recovers the same attempt. Historical reviews are not automatically backfilled. Manual ratings/missing grading provenance are not fabricated binary outcomes. Account/library context is checked around asynchronous work.

Independent fixed/generated application attempts require reviewed content and current source evidence. Assessment JSON must match the attempt and pass existing `LocalAnswerEvidence.validate`. Corrections retain attempt identity. Application answers have no scheduling mutation/equivalence path. Source/task validation and queued deeper assessment use existing authorized selected providers and preferences. No live calls were executed during development. Provisional feedback is preference-gated and cannot train models or reset cards; its Laya runtime adapter is unavailable. Deeper assessment still requires task reliability validation and correction.

## Dashboard and credible follow-ups

Observed projections cover delayed recall, explicitly unfamiliar application performance, confirmed recurring skill errors and measured active study time with coverage. Grading wall time is not study time. Missing/unsupported comparisons report insufficient evidence. Predictions have typed model/artifact/evidence/mode metadata; Rasch has conditional ability quantiles and DINA requires assessment/session identity.

Credible learning comparisons need baseline and prespecified delayed-recall/novel-transfer follow-ups, reviewed comparable assessment forms/anchors, validated scoring, prior exposure dates, known assistance/exposure, measured duration, configuration/policy identity, corrections, counts, uncertainty and missingness/attrition. Treatment comparisons additionally require randomized allocation and logged assignment/adherence/crossover rules, or explicit observational labeling. Raw averages from self-selected adaptive policies cannot establish superiority.

Explicitly permitted supplied cohorts can be fitted locally. No community collection/upload, new consent, deployment or best-model leaderboard is enabled.

## Validation and remaining limits

`scripts/Test-LearnerModels.ps1` reuses `.build` and installed Swift/MSVC tooling. Final run passed production LearningCore/StudyApplication and learner-persistence module checks, all four synthetic fitting pipelines, analytical inference/uncertainty, unsupported designs/leakage/duplicate rejection, durable reload/isolation, correction replay, preparation/switching/fallback, Q corrections/error labels, provisional/final deduplication, generated grading without FSRS mutation, real vendored FSRS scheduling equality, undo and cold-restart recovery after learner-write failure.

The separate headless fitting command passed with synthetic data and produced an eligible BKT candidate with 24 held-out attempts without activation. These checks verify implementation, not user-specific calibration or learning benefit. The controller is additionally typechecked in Swift 6 against compile-only platform boundary signatures; SwiftUI source is syntax-checked. Full existing SwiftPM regressions and Apple builds/device validation still require Mac connectivity and canonical caches/simulators. Actual permitted outcomes, reviewed mappings, valid assessment forms and scientifically reviewed calibration remain prerequisites for production activation. Apple UI validation remains deferred.

Known disposable compiler outputs/test data are removed; reusable caches and app data are preserved. No substantial temporary storage was created.

Primary references: [DAS3H](https://arxiv.org/pdf/1905.06873), [dynamic item response modeling](https://arxiv.org/abs/1304.4441), [DINA identifiability](https://www3.stat.sinica.edu.tw/statistica/oldpdf/A31n118.pdf). These support model families/assumptions, not Engram-specific learning benefit.
