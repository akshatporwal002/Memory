# Independent shared-core reliability review

> Archived on 5 October 2026 from main `381c917`. This is historical context, not current implementation guidance. Outstanding work is tracked in [the backlog](../../BACKLOG.md); newer requirements take precedence.

Reviewed against `ENGRAM-FIRST-BUILD.md` sections 3, 6A and 8, plus the goal objective's scheduling, persistence, undo, invalid-input, cloze and modularity requirements. Scope: LearningCore, StudyApplication, PersistenceAdapters, SchedulingAdapters and their shared Swift tests. The reviewer wrote tests only; production fixes were made separately by the implementing agent.

## Result

On 3 September 2026 at 03:44:57 Australia/Sydney, the shared-core suite compiled and executed on Windows x64 with official Swift 6.3.3: **17 tests passed, 0 failures**, command exit 0. This includes 8 independent reliability tests, 4 queue/mutation tests and 5 workflow/adapter tests. Incremental build: 4.80 seconds; test execution: 0.333 seconds. Anki adapter sources and test target compiled as part of the package, but the `EngramTests` filter did not execute Anki tests.

The independent 8-test reliability subset also passed before the hierarchy fixes were applied (clean scratch build 42.77 seconds; test execution 0.092 seconds). No new production defect was exposed by that subset. The broader rerun independently verified the two hierarchy defects reported during source review after their implementation fixes.

## Evidence and reproducibility

From the repository root on this configured Windows host:

```powershell
. .\scripts\Enter-SwiftEnvironment.ps1
swift test --filter EngramTests
swift test --filter ReliabilityTests
```

The review used an isolated build directory to avoid concurrent compiler state:

```powershell
. 'C:\Users\aoswa\OneDrive\Documents\ChatGPT\Memory\staging\scripts\Enter-SwiftEnvironment.ps1'
swift test --package-path 'C:\Users\aoswa\OneDrive\Documents\ChatGPT\Memory\staging' --scratch-path 'C:\Users\aoswa\OneDrive\Documents\ChatGPT\Memory\tooling\reliability-build' --filter EngramTests
```

Local logs: `C:\Users\aoswa\OneDrive\Documents\ChatGPT\Memory\tooling\core-review-tests.log` and `reliability-tests.log`. Test source: `Tests/EngramTests/ReliabilityTests.swift`, SHA-256 `7B995C2F18E6051E33CA78B3CE8A064851BF8D07FA13B35C8A074DE35F17BF03` at verification. Source continues to evolve; rerun these commands after later changes.

SwiftPM emitted the known `.build/debug` convenience-symlink warning (I/O code 512). It linked and ran the target-specific executable successfully. This warning was not treated as a test failure or suppressed. See `TOOLCHAIN.md` for installation evidence and sandbox access details.

## Requirement verdicts

| Requirement | Verdict | Concrete evidence and boundary |
| --- | --- | --- |
| Real FSRS new → learning → review → relearning → review | Pass | `testLearningGraduationLapseAndRelearningThroughApplication` performs five grades using the real adapter and application service, advances to persisted due times, compares preview/commit outcomes, and verifies event history and queue entry on the due boundary. |
| All four grades; reveal before grade; duplicate presentation prevention | Pass | `QueueAndMutationTests.testFourGradesAndDuplicatePresentation` exercises each real FSRS grade and two concurrent calls with different mutation IDs; one event remains. |
| Durable create → study → reopen → undo | Pass | `WorkflowTests.testCreateStudyReopenAndUndo` uses the production file adapter and a separately opened repository, with preserved review evidence and explicit correction. |
| Reopen an in-progress revealed session | Pass | `testReopenResumesExactRevealedPresentationAndRetainsPriorGrade` retains session/presentation IDs, reveal time, preview outcomes, completion count and prior grade, then grades the reopened presentation. |
| Real production filesystem failure and retry | Pass | `testProductionWriteFailureLeavesGradeAndScheduleUntouchedAndCanRetry` replaces a unique test-owned parent directory with a regular file, causing Foundation's actual write path to fail. It compares the entire cached snapshot and preserved file bytes, removes the obstruction, retries the same mutation ID, and reopens the result to confirm one event and one revision increment. |
| Corrupted local data must not be overwritten | Pass | `testCorruptDiskFileIsNeverOverwrittenByOpenOrStaleCommit` checks a failing reopen and a stale existing repository commit, with byte-for-byte preservation of the corrupt file and unchanged cached state. |
| Reject unsupported scheduler state; preserve existing evidence | Pass | Version/identifier tests reject unknown scheduler, schema and implementation values. The application-level reveal test checks the complete stored snapshot remains identical rather than silently resetting a card. |
| Backward clock protection | Pass | A state with a recorded review rejects an outcome request one second before that review. This is a backward-last-review check, not an exhaustive clock/timezone test. |
| Cloze siblings, retirement, editing and moving | Pass | Tests cover hints and hidden answers, independent cards/suspension, removal and reintroduction of a reviewed deletion with the same ID/schedule, deck moves, and unchanged historical events. |
| Stale presentation after editing/deletion | Pass | `testEditingThenDeletingPresentedNoteRejectsStaleGradesWithoutLosingHistory` checks both stale-grade paths, retained schedules after ordinary text editing, preserved review evidence after deletion, and exclusion of retired cards from due queues. |
| Repository replaceability and transaction failure | Pass | Workflow contract tests exercise production file and memory adapters, stale revision rejection and invalid schema rejection. Injected memory failure and actual production IO failure are both covered. |
| Scheduler replaceability | Pass | The workflow runs through a deterministic test adapter, while lifecycle/review tests run through the FSRS adapter. No SwiftUI dependency is needed. |
| Parent deck includes descendant learning return times | Pass | Independently reran `testParentDeckReportsChildLearningWait` after the fix; it checks the waiting timestamp and reappearance after the one-minute step. |
| Rename a hierarchy safely | Pass | Independently reran `testRenameHierarchyNoOpAndCaseInsensitiveConflict` after the fix; unchanged names succeed and case-insensitive descendant collisions preserve the original tree. |
| Daily new-card limit, undo restoration and Sydney DST boundary | Pass for tested cases | `testDayBoundaryUsesPinnedZoneAndDailyLimitsUndo` exercises a one-new-card budget, restores it on undo, and checks the configured 4am boundary on the Sydney DST transition. Exhaustive zones and review-budget policy are not established by this single case. |
| Native backup/restore, media and Anki data fidelity | Unverified by this review | Separate interoperability work owns these cases; compilation alone is insufficient. |
| Apple builds, actual SwiftUI flow, accessibility, theme/motion persistence | Unverified | Windows cannot execute the Apple application or simulators. All requested iPhone/iPad/Mac runtime checks remain separate gates. |

## Defects found and disposition

1. **P2 — Parent-deck learning wait omitted descendants.** Initial `nextLearningDue` selected only the exact deck while the due queue selected a hierarchy. Reproduction: create parent `Science` and child `Science::Cells`, study the parent, grade a child card Again; the session reported no next learning time although the card returned in one minute. The implementation now shares eligibility selection with queue policy; the regression test passed in the independent rerun.
2. **P2 — Hierarchy rename treated its own descendants as collisions and used inconsistent case matching.** Reproduction: create `Science` and `Science::Cells`, rename the parent to its unchanged name; it threw. A rename into another tree could also create differently cased duplicate descendant names. The implementation now calculates mappings before mutation, excludes affected IDs and compares names case-insensitively; the regression test passed in the independent rerun.

No unresolved defect was exposed in this bounded reliability run. That statement is narrower than full product acceptance.

## Limits and next gates

The disk test proves ordinary failure rollback and retry; it does not simulate abrupt process termination, power loss, a full disk during rename, file-provider races, or simultaneous independent app processes. The design currently requires one shared repository actor and one library window; cross-process locking is not verified. Tests use bounded small libraries, so large-library performance and memory pressure remain unmeasured. No code coverage percentage was measured, and no exhaustive scheduler-conformance claim is made.

Recommendation: accept the tested shared-core changes with these documented limits. Do not treat this review as approval of complete native application correctness or Anki compatibility; those require their respective runtime and fixture gates.
