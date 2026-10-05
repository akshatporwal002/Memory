# Independent import transaction review

> Archived on 5 October 2026 from main `381c917`. This is historical context, not current implementation guidance. Outstanding work is tracked in [the backlog](../../BACKLOG.md); newer requirements take precedence.

**Remediation update (parent, 3 September 2026 04:06 Sydney):** all six independent regressions below now pass. Stable deck IDs precede names; deleted source decks require a destination decision; recreated card IDs conflict; changed history payloads conflict; accepted source siblings reactivate without resetting progress; keep-existing rejects new source siblings with update/skip guidance. The default external package namespace is now SHA-256 of exact bytes, while user-named sources and embedded Engram library IDs support deliberate continuity. The UI exposes the source name. Seven transaction tests additionally pass, including cancellation after backup, concurrent writes during backup, failed final commit and rejection of native-event merge. `mergeImport` now accepts source history only; complete native evidence requires restore. Pre-commit cancellation leaves data unchanged; once the atomic commit begins, success is treated as saved. This historical review remains below as the original RED evidence, not a list of unresolved defects. Full integration: 56 XCTest cases passed; see TEST-RESULTS.md.

Reviewer: design/features specialist, independent of the author of `StudyApplication/ImportService.swift`. This review does not approve the reviewer's own UI work.

Scope: `ImportService.swift`, `ImportTransactionTests.swift`, the relevant core validation/repository contracts and Anki candidate construction, against the first-build brief's data fidelity, duplicate import, transaction, backup and scheduling requirements. Reviewed source state: 3 September 2026, `mergeImport` lines 25–96 and `replaceLibrary` lines 98–107 (before remediation). No implementation files were modified by this reviewer. After the initial source review, the parent authorized an independent regression file, `Tests/EngramTests/ImportReviewRegressionTests.swift`. Its six tests reproduce the findings below against the original implementation. Earlier passing core tests do not establish these edge cases.

## Material findings

### P1 — Recreated source card IDs create duplicate live cards for the same note/ordinal

**Location:** `Sources/StudyApplication/ImportService.swift:61`, append branch at line 69, retirement at line 76.

**Trigger:** Import basic note GUID `N` with source card `A`, ordinal 0; study `A`; later import the same note GUID with a recreated source card ID `B`, also ordinal 0, using `updateContent`. The Anki adapter uses a stable GUID-based note ID and a source-ID-based card ID, so these identities can diverge independently.

**Current result:** `A` is not matched because matching uses card ID only. `B` is appended. The retirement pass retains both because both ordinal values remain valid. `LibraryValidation` checks unique card IDs but not unique live `(noteID, ordinal)` relationships, so the transaction commits two live basic cards for the same note. Both can enter study; scheduling/history now describe two copies of one generated card.

**Required fix:** Reconcile source identity changes against the existing note/ordinal while preserving prior schedules/history, or refuse the structural update with an explicit compatibility finding before backup/commit. Do not silently append a second active sibling. Add a regression with distinct source IDs and the same note/ordinal, plus preserved history assertions.

### P1 — Conflicting review records with the same ID are silently discarded

**Location:** `Sources/StudyApplication/ImportService.swift:81–83`.

**Trigger:** Reimport a source review ID already present, with a different `cardID`, `origin` or `values` payload. An edited review record or a reused source namespace can expose this path.

**Current result:** The set-membership test treats all equal IDs as harmless duplicates. No payload comparison occurs, and the incoming evidence is neither preserved nor reported. The user sees a successful import even though the inspected source history differs from stored evidence.

**Required fix:** Skip only byte/semantic-equivalent source records. For conflicting equal IDs, fail before commit or implement an explicit provenance-preserving resolution and report it. Add equality tests for unchanged repeats and separate collision tests for different card references and values; assert the pre-import library remains unchanged on rejection.

### P2 — Keep-existing mode silently drops new sibling history

**Location:** `Sources/StudyApplication/ImportService.swift:8`, lines 51, 69–71 and 80–83.

**Trigger:** Import cloze note with c1, then reimport the same note GUID after Anki adds c2 and reviews it, selecting “Keep my content and progress; add source history.”

**Current result:** The unchanged note is accepted for history, but the c2 source card is skipped because this is an existing note and the policy is not `updateContent`. Its review records fail the retained-card-ID filter and disappear from the transaction without a compatibility finding. `ImportSummary` has only `addedHistory`; it does not disclose unrepresentable history. The label promises history import that the operation cannot fully deliver.

**Required fix:** Preflight structural differences and disclose exactly which cards/history cannot attach to unchanged content. Either preserve them as explicit source-only evidence with safe references, or refuse/require a different choice. Do not count this as an ordinary unchanged duplicate. Test a new ordinal plus review records under all three duplicate policies.

### P2 — Reintroduced cloze siblings remain retired despite a content update

**Location:** `Sources/StudyApplication/ImportService.swift:63–67`, lines 74–78.

**Trigger:** Import a note with c1 and c2; update its content to c1 only so the local c2 card retires; later update it back to c1+c2 with the same source card ID for c2 and an active candidate card.

**Current result:** The card-ID match preserves the local `retired` flag. The ordinal pass only sets retirement to true for removed ordinals; it never clears retirement for valid restored ordinals. c2 stays absent from ordinary study even though the updated text and source card both include it. Ordinary local `saveNote` handles reintroduced ordinals differently.

**Required fix:** Explicitly reconcile generated-card retirement for accepted content updates while preserving local scheduling/suspension. If some retirement is intentionally protected, distinguish it from retirement caused by a removed cloze ordinal. Test remove/reintroduce with both stable and recreated source card IDs.

### Additional P2 — Name fallback overrides exact or deleted source deck identity

**Location:** `Sources/StudyApplication/ImportService.swift:36–38`.

**Trigger A:** Import source deck ID `D` named `Imported`; rename it locally to `Z renamed locally`; create another unrelated local deck named `Imported`; reimport source `D`. **Result:** `liveDecks` is alphabetically sorted, so the unrelated `Imported` deck satisfies the combined ID-or-name predicate before exact ID `D` does. The imported note/cards are silently moved to the unrelated deck.

**Trigger B:** Delete imported source deck `D`, recreate its name as an unrelated local deck, then import new source notes from `D`. **Result:** The active name match bypasses the deleted-ID guard and imports the new notes into the unrelated replacement without an explicit destination decision.

**Required fix:** Check exact existing IDs first, honor a tombstoned exact ID before considering implicit names, and only then apply documented name fallback. An explicitly selected destination may override identity because it is a user choice. Both paths have independent failing regressions.

## Verified strengths from source inspection

- Candidate validation runs before mutation. All changes are assembled in a value snapshot; there is one repository commit after merge validation.
- Pre-import backup receives the original complete snapshot, and a throwing backup closure prevents commit. Cancellation is checked before and after backup.
- Expected revision is checked at inspection consumption and again by repository commit. Actor reentrancy while awaiting backup does not itself lose concurrent changes: a later commit at the stale revision should fail.
- Existing card schedule, suspension and Engram review/correction collections are retained for ordinary duplicate-content updates. Source scheduling metadata is kept separately.
- Local note tombstones are respected. Removed cloze ordinals retain their records as retired cards rather than erasing history.
- Equal media names with different bytes or case are rejected before commit; existing media is not overwritten. Equal names/bytes deduplicate.
- Replacement is separate from merge, invokes backup, and commits through the restore boundary rather than silently replacing during collection merge.

These are source-level observations. Durable adapter failure/cancellation behavior still needs executed tests for this operation.

## Tests present versus needed

| Requirement | Current evidence | Remaining regression |
| --- | --- | --- |
| Backup before import | Test injects backup failure and compares whole snapshot | Assert backup receives exact original including media/source metadata/history; durable adapter path |
| Repeated import | Basic note repeat/update test checks one note/card/history/media, local schedule and Engram reviews | Structural source-ID changes, cloze ordinal changes, source origin and imported review payload conflicts |
| Media collision | Different bytes rejection and unchanged snapshot assertion | Case-only collision; multiple accepted/skipped notes sharing media; media completeness after backup restoration |
| Stale inspection | Test reuses old revision and asserts unchanged snapshot | Mutate service/repository during suspended backup closure, then assert stale import fails without overwriting new review/deck |
| Cancellation | Two source cancellation checkpoints | Cancel before backup and while backup suspended; assert no commit, consistent originals; define result if cancellation arrives after commit begins |
| Commit failure | Repository contract exists | Inject final commit failure after successful backup and compare library; run against AtomicFileRepository, not only MemoryRepository |
| Collection replacement | Source invokes backup then restore | Existing nonempty library, failed backup, cancellation, stale expected revision, full media/history restore, previous active session cleared intentionally |
| Duplicate policies | Update and skip demonstrated for one basic note | Keep-existing changed structural content and source history; deleted local notes; destination mapping and nested decks |

## Executed independent regression evidence

On Windows Swift 6.3.3, with the installed Swift/MSVC environment initialized:

```powershell
. ./tooling/Enter-SwiftEnvironment.ps1
swift test --package-path staging --scratch-path tooling/import-review-build --filter ImportReviewRegressionTests
```

Latest run: **3 September 2026, 03:57:15 Australia/Sydney; build successful; 6 XCTest cases executed, all six failed at intended behavioral assertions, 12 failing assertions, 0 unexpected failures.** Full output: workspace `tooling/import-review-red.log`. The first four cases also ran separately and failed before the deck cases were added. No test failure was caused by missing tooling or a compiler error. The scratch-directory symlink warning did not prevent execution.

| Test | RED outcome |
| --- | --- |
| `testRecreatedSourceCardIDForSameOrdinalIsExplicitConflict` | Import succeeded and appended second active card instead of rejecting; original snapshot changed |
| `testChangedHistoricalPayloadWithSameIDIsExplicitConflict` | Import succeeded while silently retaining old source payload; snapshot revision/card version changed |
| `testKeepExistingRejectsNewSourceSiblingInsteadOfDroppingItsHistory` | Import succeeded while dropping sibling history, without actionable update/skip error |
| `testUpdateReactivatesReintroducedSourceSiblingAndPreservesProgress` | Reintroduced sibling remained retired; schedule and Engram review preservation assertions passed |
| `testExactSourceDeckIDTakesPrecedenceOverAnotherDeckWithTheOldName` | Note and card moved to unrelated matching-name deck |
| `testDeletedSourceDeckCannotSilentlyMapToUnrelatedRecreatedName` | Import succeeded into replacement-name deck instead of requiring a destination decision |

These are pre-fix RED tests. The parent owns remediation and the subsequent GREEN execution; this report does not claim fixes are verified.

## Additional contract decisions / suggestions

**Source-namespace collision risk, verified against Anki source:** `AnkiAdapters/AnkiImport.swift:85` uses `anki-` plus `col.crt` when no explicit namespace is supplied. At inspected Anki revision `39e4b0b48c5bb22e9c22ad87c64ff14e6a24dc20`, `rslib/src/storage/sqlite.rs:514` initializes `crt` with `v1_creation_date()`, and `rslib/src/scheduler/timing.rs:102–113` rounds it to the local 04:00 study-day boundary. It is therefore not a unique collection identity: independent profiles created in the same zone/study day share it. Shared/imported GUIDs and source card IDs in those profiles then enter the same duplicate namespace. The existing explicit `namespace` parameter can support a user-managed stable source identity; the import UI must expose/document an appropriate disambiguation policy rather than claiming the automatic timestamp prevents source collisions. This is a cross-adapter contract risk supported by source inspection; no package-level namespace regression was executed in this bounded review.

1. Selecting `destinationDeckID` maps every imported source deck to the same destination (lines 34–35). If the UI labels this simply as a destination, it should explicitly explain that the hierarchy will flatten; preserving a selected parent with imported descendants would better satisfy the brief's hierarchy-fidelity goal. This is a product/flow contract to resolve before claiming hierarchy preservation for every destination choice.
2. `mergeImport` accepts a general `LibrarySnapshot` but does not merge its `reviews` or `corrections`. The current Anki factory places source logs in `importedReviews`, so the intended Anki path is unaffected. Guard against nonempty native-event collections or document a narrower import-candidate type so future native-backup merge cannot silently lose evidence.
3. All package media is considered even when notes are skipped. This preserves supplied files but can reject an otherwise no-op skip due to unrelated media collisions. State this behavior or explicitly scope accepted media, with safe shared-reference handling.
4. The comment saying cancellation leaves the active library unchanged needs a defined commit point. The pre-commit checks are useful; cancellation after an atomic commit starts may still result in a committed import and should be surfaced as such rather than reported as an uncommitted cancellation.

## Review conclusion

Do not describe duplicate import fidelity as complete until the five material findings are remediated and all six independent regressions pass. The snapshot/backup/optimistic-commit structure is appropriate, but the original three import tests cover only unchanged basic card relationships and do not exercise the history and generated-card edge cases above.
