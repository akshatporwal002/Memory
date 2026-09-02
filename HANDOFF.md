# Engram first-build requirement audit

Audit date: 3 September 2026. Scope: the user goal attachment and authoritative `ENGRAM-FIRST-BUILD.md`, not a reduced subset selected to match passing tests. This is an implementation handoff with outstanding acceptance gates; **the complete native first-build objective is not yet verified**.

The working environment is Windows. Swift 6.3.3/MSVC can compile and run the shared logic and format-adapter tests. No Mac, Xcode, Apple SDK, iPhone/iPad simulator or native Mac runtime was available. Native syntax-only parsing cannot establish Apple API type correctness, successful app launch, platform layout, accessibility or performance.

Latest inspected full-suite evidence: `validation/persistence-optimized-tests.log`, **04:28:29 Australia/Sydney, 62 XCTest cases, 0 failures**. This includes six remediated import-review regressions, eight import transaction tests, four startup recovery tests, twelve markup tests, core workflows and Anki/archive tests. The pinned FSRS upstream run separately passed **98 tests in 23 suites**. Four official Anki backend roundtrip results report `passed: true` in `validation/anki-roundtrip-results.json`. Later native feature refinements passed syntax-only parsing; native API typechecking remains pending.

Status terms below: **backend evidence** means a named executed test/fixture covers the stated behavior; **source implemented** means current source provides the behavior but Apple runtime verification is absent; **pending** means missing or insufficient evidence; **unsupported** means a disclosed compatibility boundary, not silent success.

## Deliverables and architecture

| Requirement | Current artifact/evidence | Audit status |
| --- | --- | --- |
| Read authoritative brief, plan, roles and supplied references | Preserved briefs; source review; design handoff records all seven viewed PNGs | Documented. Research context does not override standalone/native first-build direction |
| Separate official Anki reference checkout, pinned revision and stable release | `ANKI-SOURCE-REVIEW.md`; reference commit `39e4b0b48c5bb22e9c22ad87c64ff14e6a24dc20`; official 26.08.1 backend fixtures | Source reconnaissance and backend compatibility evidence |
| Architecture map, concrete code/test references, feature matrix and licensing | `ANKI-SOURCE-REVIEW.md`; C target provenance; `Vendor/FSRS` | Delivered; broader Anki parity is not claimed |
| Native iPhone/iPad/Mac source and reproducible project | `App`, `Sources/Features`, `Sources/DesignSystem`, `project.yml`, `Package.swift` | Source implemented; XcodeGen generation and both Apple builds pending |
| Shared logic with separate platform navigation/file handling | Features → StudyApplication → LearningCore; App composes concrete adapters | Source implemented; no web-product substitution |
| Central semantic theme system, Warm/Neutral light/dark | `EngramTheme`, tokens, typography, reusable components | 72 opaque contrast pairs passed; minimum ordinary text 5.289:1; rendered app pairings pending |
| Replaceable scheduler and provider-neutral history | `Scheduler`, `ScheduleState`, `ReviewEvent`, `ReviewCorrection`; real FSRS adapter and test adapter | Shared workflow tests cover injected deterministic scheduler; scheduler migration requires explicit future conversion, not an unchecked switch |
| Persistence behind domain repository contract | `LibraryRepository`, MemoryRepository, AtomicFileRepository | Backend read/CAS/validation/reopen/failure tests; large libraries and cross-process writers remain limits |
| Isolated Anki parsing/format version boundary | `AnkiAdapters`, validated candidate, ImportService | Adapter/source separation delivered; current legacy subset only |
| Versioned schema and explicit migration policy | Snapshot/backup/scheduler versions; unknown-version rejection; ARCHITECTURE.md | v1 delivered; no invented historical migration claimed |
| Future AI/voice/MCP/sync/billing seams | ARCHITECTURE.md documents boundaries without inactive services | Delivered as architectural planning; deferred functionality is not implemented |
| README, build commands, tests, previews and handoff | README.md, README-APPLE.md, TEST-RESULTS.md, this file, design/previews | Delivered; checks explicitly separated from commands not yet executed |

## Required study workflow

| Requirement | Current evidence | Audit status / remaining check |
| --- | --- | --- |
| Empty launch, real Today counts and meaningful activity | Today/Activity views consume snapshot and QueuePolicy; empty-state actions create decks | Source implemented; no fabricated mastery/streak data. Clean native launch pending |
| Create/rename/delete decks, hierarchy and consequences | StudyService; native deck form/delete confirmation; hierarchy regression | Backend tests cover hierarchy rename and queue subtree behavior; native dialogs/actions pending |
| Basic/cloze creation/editing/preview/validation | Core renderer/validation, EditorView; workflow and markup tests | Backend evidence for rejection and sibling generation; full native editor save/cancel pending |
| Separate note content and independently scheduled generated cards | Note/StudyCard, ordinal mapping, cloze edit/retirement tests | Backend evidence; source card identity conflicts under repeat import have separate regression gate below |
| Tags/search/move/source field/delete/suspend/resume | StudyService and LibraryView/EditorView | Source implemented; core move/schedule/stale-grade tests. Full native search/tag/suspension workflow pending |
| Ordinary edits preserve progress | saveNote increments versions and preserves schedule; reliability tests | Backend evidence, including move, retirement/reintroduction and stale grades |
| Question hidden until reveal | CardRenderer and ReviewView; persisted revealed presentation | Backend renderer/session evidence; native accessibility announcement pending |
| Again/Hard/Good/Easy with real interval previews | FSRSScheduler outcomes saved on reveal and consumed by grade | Four real grades and transition tests passed; native button labels/keyboard pending |
| Save before advance, duplicate-grade prevention | Atomic transaction, presentation token, mutation ID, UI busy guard | Backend concurrent duplicate/stale input tests; rapid native input/animation overlap pending |
| Undo without erasing history | Correction record and prior schedule restoration | Backend evidence; native Command-Z/focus pending |
| Exit/resume, completion and newly due learning cards | Persisted StudySession; refresh policy; parent-deck wait regression | Backend resume/learning-wait evidence; native exit/relaunch/completion pending |
| New/learning/review/relearning/suspended states | FSRS-6 adapter, independent suspension, QueuePolicy | Backend transition and exclusion coverage; no arbitrary/random fallback algorithm |
| Daily limits, day boundaries and timezone behavior | 20 new / 200 review defaults; persisted IANA zone; 04:00 rollover | Backend daily-limit/undo/DST tests. Learning repetitions uncapped; automatic sibling burying deferred |
| Durable offline library and history | Whole validated snapshot atomically saved to app-container file | Real filesystem create/study/reopen/undo and write-failure/retry tests. Native container/lifecycle checks pending |
| Restart keeps exact revealed session and prior grades | Reliability test reopens production repository | Backend evidence; force quit/relaunch on all Apple platforms pending |

## Portability and media

| Requirement | Current evidence | Audit status / remaining check |
| --- | --- | --- |
| APKG import/export and COLPKG import | Official Anki26.08.1 legacy schema11 fixtures, Swift adapters | Backend evidence for the legacy-compatible path; modern Latest zstd/protobuf packages unsupported |
| Basic/reverse/multi-cloze/nested decks/Unicode/tags/media/history/suspension | Fixture provenance + adapter assertions + official backend roundtrip results | Covered by small real fixtures; not exhaustive historical Anki versions or huge collections |
| Preserve source IDs, note types/fields/templates and distinct source history | Namespaced IDs, ImportOrigin, sourceSchedule, ImportedReview; personal roundtrip comparison; explicit source-name field | Backend evidence for supported fixtures; source-name/reimport workflow needs native verification |
| Supported scheduling continuity with informed alternatives | preserveSource for new/supported FSRS review; content-only requires explicit choice | Source/UI implemented and fixture-tested mapping. No exact legacy SM-2/learning/buried/filtered continuity; no claim of identical future Anki intervals |
| Choose → inspect counts/findings → destination/treatment → confirm → transactional import | PortabilityView/Model plus mergeImport/replaceLibrary | Source implemented; Apple file picker/confirmation/end-to-end transaction flow pending |
| Duplicate keep/update/skip and structural/source-history safety | Original import tests + independent six-case regression suite | All six independently reproduced RED cases now GREEN in the 62-test full run; exact-ID precedence, tombstones, conflict rejection and sibling reactivation covered |
| Collection import never silently replaces | Explicit replacement toggle/confirmation, pre-import backup callback, revision guard | Source implemented; merge backup failure, stale/concurrent mutation, cancellation and commit failure tests pass. Full native collection replacement remains pending |
| Import shows results and actionable compatibility findings | Inspection report, source-name/destination/treatment choices, actual ImportSummary displayed on success | Source implemented; native flow and assistive-technology presentation pending |
| Complete native backup including originals/media/events/corrections/settings | Manifest+payload ZIP; restoration equality and missing-payload tests; four startup recovery tests | Backend evidence including original preservation, conflicts and failure safety. Native export/share/restore and damaged-startup recovery remain runtime gates |
| Safe archives and no imported script execution | Archive bounds/path/CRC validation; isolated SQLite; SafeCardMarkup; native renderer | Unsafe/modern/malformed-template tests and 12 markup tests pass. Broader fuzzing/resource-load tests pending |
| Image display/audio playback for supported cards | CardContentView uses SwiftUI/ImageIO/AVAudioPlayer with local bytes | Source implemented; parser tested. Image decoding, audible playback, interruption, VoiceOver and Apple memory use unverified |
| Anki → Engram → Anki roundtrip in disposable environment | `validation/anki-roundtrip-results.json`: four Swift-produced variants, each passed in fresh official Anki backend collection | Executed backend evidence; no desktop Anki GUI or Apple UI migration claimed |
| No source mutation on export; selected scope and personal/sharing modes | Adapter tests compare source snapshot; official backend comparisons include cleared sharing history and retained personal/new Engram history | Backend evidence for supported cases; full UI chooser/write-cancellation pending |

### Current import regression gate

`IMPORT-REVIEW.md` and `Tests/EngramTests/ImportReviewRegressionTests.swift` record pre-fix evidence: source-card ID recreation duplicated an active note/ordinal; conflicting review IDs were silently skipped; keep-existing dropped new sibling history; restored cloze ordinals stayed retired; name matching overrode exact/deleted source deck identity. The parent remediated these after the RED checkpoint. The current implementation was inspected and all six tests pass in `validation/persistence-optimized-tests.log`; review evidence was not weakened to obtain GREEN.

The review also established that Anki collection creation metadata is a study-day timestamp, not a unique identity. The current import UI now exposes a persistent source-name choice; external unnamed packages use exact-file identity and changed exports intentionally become separate sources. Engram direct exports carry their own identifier. Users must reuse a profile's source name for stable matching across changed Anki exports; arbitrary Anki re-exports are not assumed to preserve Engram metadata.

## Native design, adaptation and accessibility

| Requirement | Current source/artifact | Audit status |
| --- | --- | --- |
| Warm ivory/olive/amber/taupe, editorial headings, opaque reading surfaces | Native tokens/components and six-screen mockup contact sheet | Implemented design intent; native visual acceptance pending |
| Liquid Glass navigation with platform adaptation and fallback | Native TabView/NavigationSplitView/toolbars; system availability; opaque accessibility policy | Source implemented using standard components, no copied Music chrome. Actual OS26 optics and older-OS fallback unverified |
| Phone tabs, iPad/Mac sidebar, responsive width, safe areas | Root branch at 600pt; model state above branch; mobile sheet sizing follows OS | Source implemented; portrait/landscape/narrow window/final-row/keyboard checks pending |
| Wide library list and selected-card detail; wide editor preview | Library splits into note/card list + selected detail at adequate width; selection is model-owned; editor splits when wide | Source implemented; compact/accessibility reflow and resize retention remain native checks |
| Theme switches preserve draft and revealed review | Model-owned draft/session; persisted theme/appearance; menus inside editor/review | Source implemented; switching/reflow survival must be exercised natively |
| Flowing interruptible press/reveal/grade/navigation/sheet/completion motion | Shared tokens; press/reveal/grade; native sheets/navigation; once-per-session completion and numeric transitions | Source implemented; reduced motion removes spatial/scaling changes and uses short fades. Native interruption/focus/frame behavior pending; no frame-rate claim |
| Dynamic Type, VoiceOver, keyboard, reduced motion/transparency, contrast | System text styles, reflowing grades, labels/intervals, reveal focus, external focus rings | Token contrast executed; all actual Apple assistive-technology/focus/input checks pending |
| Today/Library/Q&A/Editor/Completion across phone/tablet/Mac and dark/accessibility states | `design/previews/design-preview.html`, theme/layout/text selectors | MOCKUPS only. Browser inspection found and corrected mockup tab overlap; this does not prove native geometry |

## Concrete remaining acceptance checklist

Performance follow-up: PERFORMANCE.md records release-mode Windows save/reopen/backup measurements at 1,000 and 10,000 cards with 0/16 MiB of attachments. The observed multi-second commit slowdown was fixed without weakening external-change detection. Apple timing, peak memory, large review histories, frame behavior and upper-cap libraries remain unverified. A new Windows sharing-mode test reaches a genuine atomic replacement failure and proves retry; this does not substitute for Apple filesystem fault testing.

1. Generate `Engram.xcodeproj`, build both documented schemes with stable Xcode, fix compile/type/link errors, and record Xcode/SDK/device versions. Windows syntax-only parsing is insufficient.
2. Preserve the **62-test full-suite GREEN evidence** for the audited backend revision and rerun tests only when subsequent backend changes warrant it. Retain RED evidence and regression intent; do not weaken assertions. Native build commands still need to be executed separately.
3. Exercise the import result summary and source-identity choices through native UI. Verify duplicate choices, recreated IDs, cloze structural updates, media collisions, stale inspections and failed/cancelled operations. Backend failure/cancellation/concurrency regressions pass; expand production-adapter import failure coverage where needed.
4. Exercise the wide Library selected-card detail and completion/count motion. Verify selection and scroll behavior through resize/theme changes; motion must remain interruptible and never determine persistence.
5. On iPhone and iPad simulator/device and native Mac: empty launch → create deck → basic/cloze → preview → save → study all grades → undo → exit/resume → relaunch. Compare actual stored counts/history/schedules and independent sibling state.
6. Exercise search/tags/suspension/move/edit/delete, long titles, dense libraries, multi-paragraph answers, invalid/visually empty content, missing media, deleted presented cards and corrupt-startup recovery. Preserve original files and drafts on every failure.
7. Switch all theme/appearance variants while editing and after reveal; rotate and resize phone/iPad/Mac. Check compact safe areas, the last list row, keyboard-visible Save, readable maximum text width and fixed grade controls.
8. Exercise VoiceOver order, answer announcement/focus, grade label+interval, Full Keyboard Access, Space/1–4/Undo/Escape with appropriate input focus, largest Dynamic Type, Reduce Motion, Reduce Transparency and Increase Contrast. Capture actual runtime screenshots for all six required screens and platform families.
9. Exercise native document pickers/open-save panels, confirmed APKG/COLPKG migration into nonempty libraries, complete backup→restore including media/history/source originals, and audible local playback on all platforms. Current official-backend roundtrips do not replace this UI path.
10. Measure large-library import/export cancellation, memory, atomic-write throughput, scrolling and sustained rapid reviews. Validate baseline device responsiveness before claiming frame performance or raising current limits.

## Disclosed boundaries

Direct same-library APKG reimport is explicitly refused using immutable export provenance, independent of user namespace overrides. A failing regression first demonstrated duplicate native identities; the current guard rejects before backup or mutation. This also avoids adding imported copies of native review evidence over its originals. Complete `.engram` backup restore is the supported recovery route; transfers to a different library retain stable repeated-import behavior. The final clean delivered-source run covers this contract.

Legacy schema11 compatibility is the validated support boundary. Modern package codecs and exact legacy/learning/buried/filtered scheduler-state continuation are explicitly unsupported variants. The brief requires supported versions and limitations to be reported; it does not establish universal package or scheduler parity. Clear rejection/content-only choices are the delivered behavior. Custom scripts/CSS/image occlusion/unsupported markup are blocked rather than flattened. Whole-collection Anki export is not required and is absent. Native backups remain the complete Engram portability format.

AI generation/tutoring/grading, cumulative assessments, transcription/voice tutoring, MCP, cloud sync, subscriptions/billing and speculative provider infrastructure remain deferred. Core study and portability remain local and independent of those services. No publication, deployment, paid-provider configuration or service purchase was performed.

The user-authorized work has produced native source and meaningful backend evidence. The remaining items above are acceptance gates, not a redefinition of the goal as source-only delivery.



