# Deadline learning prototype — implementation decisions

7 October 2026

## Available in the app source

Open a notebook overview → Analytics → Deadline learning · plan & data (also available inside the existing Analytics page).

- A local goal freezes eligible card content, question versions/types, deadline, target performance and daily minutes.
- An independent exponential-memory baseline uses accepted unaided graded evidence, reconciles corrections and preserves exact content matches across scheduling revisions.
- A deterministic daily greedy rollout ranks hypothetical deadline-performance gain per measured/assumed study second. It never rewrites FSRS due dates to manufacture a plan.
- Explicit planned study opens eligible recommended cards, including cards not yet due under FSRS. Existing answer grading schedules completed cards normally. Typed, deferred and voice queue advancement preserve the finite planned set.
- The minimal row-based notebook surface shows planned/no-further-practice forecasts, target shortfall, study dates, observed outcomes, measured time, question-type coverage, saved forecast history and a JSON metrics/plan export.
- Goals and up to 100 explicitly saved forecast snapshots are kept in the existing account/library-scoped device-local learner store. Reading analytics recalculates without storing snapshots; saving/recalculating/start-study are explicit snapshot actions.
- Existing local learner recording is optional and library-wide. No research opt-in is inferred and no new Supabase upload is enabled.
- Changed, removed or suspended target cards block planning until an explicit target refresh. Targets stay fixed until that refresh; refresh replaces forecast history with a new goal.

## Critical research choices

This first prototype uses the simple greedy baseline from the research plan, not a trained DAS3H action-effect model or beam-search optimiser. DAS3H/IRT calibration requirements remain intact. It does not fabricate fitted artifacts or treat uncalibrated forecasts as observed mastery.

Provisional constants are engineering hypotheses, not estimates extracted from the cited experiments: unknown-item knowledge 35%; initial half-life one day; observed unaided success resets probability to 95% and increases half-life, while failure resets it to 45% and reduces half-life. Delayed success and measured duration affect subsequent estimates. Simulated practice effects use expected recall to increase memory strength. These assumptions need fitting and controlled validation. Displayed percentages are experimental estimates, not reliable individual exam probabilities.

V1 supports 1–500 fixed target cards, a horizon up to 366 days, daily budgets of 1–120 minutes, at most 100 planned cards per day and 2,000 simulated actions. Target shortfall can reflect these search limits; it is not proof that a student's goal is impossible.

Existing Understanding practice's harder-progression controls remain available, but this baseline plans the notebook's fixed recall-card blueprint. Automatic prerequisite discovery, calibrated difficulty progression within the deadline queue, action-effect training, randomised study assignment and long-term validation are later research stages. Generated same-level variants are not silently labelled harder cards.

Manual/self-reported grades, unknown assistance, partial/unclear outcomes and unverified content versions do not supply binary correctness observations. Evidence can be sparse even when ordinary review counts are high; the UI reports accepted observations explicitly.

## Validation and device limits

Production core/application modules and a standalone end-to-end test suite are checked through scripts/Test-LearnerModels.ps1 using the existing .build location. Tests cover daily budgets, retractions, future-data exclusion, stale blueprints, persistence/backward compatibility, account isolation, independent planned practice and finite queue advancement. SwiftUI syntax is included in the existing validation script; full Apple-platform compilation and visual validation require the Mac.

The initial Mac connection attempt failed because mac.modem could not be resolved. No phone installation or simulator captures have been performed for this change. No extra caches, simulator devices or runtimes were created. The existing validation script cleans only its known disposable outputs and retains other build storage.

Final local validation: PASS. The existing suite successfully compiled LearningCore and StudyApplication module boundaries, parsed the SwiftUI deadline screen, and ran the deadline unit/integration checks alongside existing learner, understanding and FSRS regression checks. Full SwiftUI type-checking, simulator rendering and physical-phone installation remain unverified because the Mac is unreachable. Temporary compiler/test outputs were cleaned by the existing script; reusable caches were preserved. No substantial permanent build storage was added.

Phone installation — 7 October 2026: complete. The Mac became reachable with approved network access; current source and App assets were transferred into the existing Memory-overnight checkout. Full iOS compilation passed. SSH signing hit errSecInternalComponent; the documented desktop Terminal fallback succeeded without changing keychain permissions. Signature verification, installation to the paired iPhone 17 and launch of dev.engram.study all succeeded. Existing app data and /tmp/engram-account-libraries-build were preserved. Known source-transfer and rollback archives were removed; concise validation evidence remains on the Mac. Full Apple UI compilation is now confirmed; simulator visual captures were not performed during this installation.

## Notebook visualisations — 7 October 2026

The earlier learner analytics charts are integrated with the deadline prototype. Notebook Analytics shows recorded activity/outcomes, an FSRS no-further-review curve, question-level performance, BKT/DINA skill estimates and dynamic Rasch ability with conditional intervals. Disabled or unsupported models show an honest empty state rather than fabricated values.

Deadline learning adds a common-scale comparison of the target, planned performance and no-practice baseline; daily planned minutes and card counts; observed correct/incorrect counts; question-type coverage; and saved forecast/baseline curves with a dashed target. Daily details remain expandable. Forecast history compares estimates for the same deadline and is not a measured learning curve.

Library → Add learning analytics sample creates an idempotent, clearly marked Learning lab notebook. Its synthetic history exercises all available learner adapters and the actual deadline planner with illustrative parameters. Deadline targets and budgets can be explored in a read-only sample preview. Demo predictions, goals and forecast snapshots do not enter the personal learner store, and suspended sample cards stay outside the ordinary review queue.
