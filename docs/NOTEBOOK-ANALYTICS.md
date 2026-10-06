# Notebook analytics

6 October 2026, `akshat/learning-models`.

Each notebook overview has an Analytics heading and a plain navigation row. The detail page uses the existing native grouped-list style, with observed outcomes first and separate algorithm sections. No charting dependency, model activation, fitting, downloads or inference calls are introduced by opening it.

- **FSRS:** mean predicted recall now with estimated/total card coverage, plus scheduled/ready counts. Uses the existing estimator, excludes unsupported/new card states, and points to the existing Memory outlook for time projections. It is a recall estimate, not topic mastery.
- **DAS3H:** predicted response success for current reviewed questions. This is skill-performance prediction, not a mastery percentage.
- **BKT:** conditional single-skill mastery estimates and separate response probabilities; slip/guess mean these numbers differ.
- **Dynamic Rasch:** calibrated item difficulty, predicted success and conditional ability interval for supported current questions. Difficulty is in the fitted anchored artifact's scale; scores across unrelated artifacts are not comparable.
- **DINA:** supported administration-scoped skill posterior and response prediction, only when the existing assessment identity/readiness boundary can provide it. General practice is not converted to a DINA form.

The page shows all algorithm descriptions and limitations. Unselected models are Off. Off/unready models show insufficient evidence rather than invented values. Analytics never switches a model or prepares a replacement state. Estimates retain artifact/evidence identity and use compatible library-wide history. The UI does not aggregate question response probabilities into a purported topic-mastery score.

Observed accepted attempts, delayed recall, explicitly unfamiliar outcomes, confirmed errors and measured duration are restricted to the notebook's card/question and saved understanding-attempt identities. Corrected outcomes use the latest logical attempt revision once. Historical unknowns remain unknown. Known saved attempt identities retain outcomes after replacing a variant family; unknown historical notebook ownership is not inferred. Account/library leases and evidence/configuration revisions are checked around asynchronous projection. Current-content matching excludes stale question predictions.

Validation on 6 October 2026: `scripts/Test-LearnerModels.ps1` PASS, including notebook/account isolation, empty evidence, Off/no fabricated predictions, measured-duration projection, read-only state, retired/suspended/new-card recall coverage and BKT mastery-versus-performance assertions. Existing fitting, persistence, replay, switching and actual FSRS preservation checks also passed. The new UI file is syntax-checked. Apple compilation and actual notebook layout remain unverified while the Mac is unavailable. Known compiler/test outputs were removed; reusable build cache and app data remain preserved, with no substantial temporary storage created. No live AI calls, downloads, commits or pushes.
