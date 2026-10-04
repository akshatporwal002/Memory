# Review UI, deferred grading, maths input and tutor workspace

Recorded: 5 October 2026, Australia/Sydney.

**Status: approved requirements and historical planning record.** Implementation began after the user's later approval. Actual completion, validation, unattended decisions and remaining hosted dependencies are recorded in [the implementation log](UNATTENDED-REVIEW-IMPLEMENTATION-DECISIONS.md). Recommendations and unresolved decisions below are distinguished from approved behaviour.

## Confirmed follow-up decisions

1. **Batch interval:** customizable in the UI. Five answers is a proposed default, not a confirmed fixed interval.
2. **Reference answer after submission:** enabled by default; the learner can disable it.
3. **Grading:** supported AI grades apply automatically; unclear assessments require manual review. Disputes are available in the summary. Show the summary only when its marking is finished, never as a compulsory waiting screen. A small, dismissible top notification announces readiness. If ignored, retain the unseen results and include them in the next ready summary, even across sessions/restarts. Viewing or dismissing a notification must not apply the grades a second time.
4. **Voice:** confirm every transcript. Highlight uncertain words in red while speaking where the transcription service provides a defensible uncertainty signal. Offer a context-informed guess for unclear words, clearly marked as suggested and confirmed by the learner. Context may clarify recognition; it must not rewrite an incorrect answer into a correct one. Preserve the original transcription and accepted edits. Do not manufacture word-level confidence when a provider does not supply it.
5. **Maths:** default Off; enable in notebook settings. Retain Basic/Advanced choices and question-level applicability.
6. **Tutor structure:** Tutor → Subjects → Assigned decks → Students, plus an All students overview. Students must be searchable.
7. **Tutor access:** explore/create drafts freely; require payment when inviting students. Publishing is not an additional independently chosen paywall. Exact entitlement checks for invitations/active capacity follow the approved billing plan.
8. **Automatic workspace:** activating Tutor creates or reopens one account-owned Tutor workspace automatically and reveals it in Library. Use an idempotent operation so repeats, retries and device synchronization cannot create duplicates. Do not require a separate workspace-creation form.
9. **Research instrumentation:** plan broad structured database collection covering AI latency/usage, learning outcomes, time spent, feedback and related product/research measures. Consent, raw-content scope, research access and retention remain decisions to settle below.
10. **Question-type tracking:** record the canonical question type and its schema version for every question and attempt, across all supported types. Include subject/domain (for example maths), subtype and actual input modality separately so a maths MCQ is distinguishable from an equation answer or a spoken short answer. Snapshot these values at submission; later edits to a question must not relabel historical attempts.

These decisions supersede conflicting recommendations/open questions in the original sections below.

This document extends [the overnight requirements](OVERNIGHT-IMPLEMENTATION-REQUIREMENTS.md), [the voice processing plan](VOICE-TRANSCRIPTION-AND-BILLING-PLAN.md) and [the tutor plan](TUTOR-ASSIGNMENTS-PLAN.md). These latest visual and workflow requirements take precedence where they differ. It does not claim that the planned tutor sharing or grading workflows are already implemented.

## 1. Design direction and screenshot references

The approved Library, Activity and MCQ screens establish the visual baseline: a coherent canvas, generous but purposeful spacing, readable typography, subtle separators and restrained controls. Newly added features must feel like part of that same app.

| Reference | What it establishes |
| --- | --- |
| Photo 1 | Approved MCQ question typography, unboxed content and faint answer separators |
| Photos 2 and 10 | Disliked enclosing short-answer card, nested input box and unnecessary Equation entry on a non-maths question |
| Photo 3 | Existing grading feedback is too boxed and interrupts the review flow |
| Photo 4 | Supporting evidence currently exposes long unrelated passages, internal identifiers, raw Markdown and unwieldy links |
| Photos 5–8 | Symbolab-style mathematical input categories, templates and editing controls; inspiration for input only |
| Photo 9 | Cleaner settings hierarchy, aligned rows, icons, muted section labels and restrained actions |

Original references are the ten user-supplied photos in `C:/Users/aoswa/.codex/codex-remote-attachments/01a0f0df-7424-7393-8887-517621ac1746/467545D9-FDD6-4FB7-AB58-71BCECB84E41/`.

## 2. Typed-answer screen

### Requested

- Make typed-answer review visually consistent with MCQ review.
- Remove the large enclosing card, nested answer box, decorative outlines and heavy shadows.
- Present the question directly on the screen with the existing question typography.
- Present a borderless answer area, optionally using faint lines like the MCQ separators.
- Show a placeholder such as **Type your response here**; hide it when the field is tapped/focused and while it contains an answer. Restore it when empty and unfocused.
- Keep the existing **Review answer** button appearance: the user explicitly likes it.
- Preserve comfortable question/answer placement, long-answer scrolling and accessible text sizes without adding enclosing boxes.
- Apply the same visual language to other newly introduced question/input types. Keep their required interactions understandable rather than making every type use an identical layout.

## 3. Deferred AI marking and uninterrupted review

### Problem and requested direction

AI marking currently takes long enough to interrupt study. The user wants answers collected into a durable stack/queue and marked after every configurable number of questions, allowing study to continue while marking happens.

- Extend deferred processing to typed answers as well as voice answers.
- Save each original attempt before advancing, including question/presentation version, expected answer, evidence versions, submission time and relevant model/provider information.
- Submit batches after a chosen question count; flush any remaining attempts when the review ends.
- Make the batching interval configurable. The exact default remains undecided.
- Avoid resending identical shared context unnecessarily, while retaining the question-specific references needed to grade accurately.
- Show unobtrusive pending/failed marking status. Results must not interrupt another question or unexpectedly change the current screen.
- Preserve pending work across closing a session, restart, network loss and interrupted requests. Explain when processing is waiting for the app/network rather than promising unrestricted iOS background execution.
- Keep question-to-answer/result matching explicit. A failed or malformed result for one question must not shift the results for the others.
- Preserve existing outcome mappings: **correct → Good**, **partial → Hard**, **incorrect → Again**, **unclear → no automatic grade**. AI must not infer Easy.
- Prevent duplicate scheduling commits and stale results. Preserve the original attempt time when delayed marking is committed.

### Optional answer reveal

- Add a setting to show the reference answer after submission while marking continues in the background.
- This reveal must happen after the original attempt is saved. It must not improve the grade of the original attempt or be mistaken for pre-answer assistance.
- The user should have useful material to read without waiting for the AI response.
- The reveal preference is confirmed **On by default**.

### Voice flow: recommendation to evaluate

The user leaves the exact voice behaviour open and considers confirmation useful.

- Use the same durable marking queue for confirmed spoken attempts.
- Offer a quick confirmation/correction of the recognized transcript before submission; an optional hands-free confirmation flow can be considered.
- Prefer brief local acknowledgement and optional reference-answer playback over waiting for AI grading narration after every answer.
- Do not read delayed feedback over the next question or while the learner is speaking. Respect interruption and the existing speech controls.
- If immediate feedback is offered, make it an explicit mode and evaluate its real latency separately.

### Architectural cautions and open decisions

- Batching may reduce repeated context and request overhead; it does not guarantee faster total marking or fewer billed tokens. Measure latency, cost and grading quality before claiming an improvement.
- Reuse shared context only where appropriate; preserve separate evidence and assessment validation for every attempt.
- Decide the batch default, maximum batch size, submission timing and whether **Wait for feedback** remains an alternative.
- Supported grades commit automatically as validated results arrive. Unclear results require manual review. Summary viewing does not control or repeat the scheduling commit; disputes create recorded corrections with scheduling reconciliation.
- Do not use an ungraded answer as a successful review. Pending questions need a defined scheduling policy and must not immediately recur during the same session.

## 4. End-of-review feedback

### Requested layout

- Present a minimal summary screen once AI feedback is available.
- Show a compact rating/outcome summary with counts and a scrollable list of attempts.
- Use the actual FSRS vocabulary **Again / Hard / Good / Easy**, alongside plain assessment labels where useful. Keep **Pending / Unclear / Failed** distinct from grades; the user's easy/medium/hard example expresses a simple summary rather than a new grading algorithm.
- Each attempt shows, in order: **question → annotated original answer → concise explanation**.
- Show supported/correct answer spans in green.
- Strike incorrect spans in red; distinguish irrelevant material when applicable.
- Show missed information as clearly labeled additions in red, separate from the learner's exact original wording.
- Include labels or other cues so colour is not the only way to understand feedback.
- Use native rich rendering for explanations and mathematical content, without raw Markdown or internal payloads.
- Retain the ability to discuss/dispute feedback and use manual rating. Any accepted correction must preserve the original attempt and assessment history.
- If work is still pending when study ends, let the learner leave. Announce the completed summary through a small top notification when ready. Do not automatically navigate to it or open a partial summary as a waiting screen.
- Persist unseen feedback and merge it into the next completed summary if the notification is ignored. Group it by session/date and keep new versus previously viewed results clear. Never repeatedly duplicate results when merging.

### Evidence and citations

- Embed small citations such as **[1]** beside the specific claims they support.
- Tapping a citation reveals the exact relevant sentences from the source, with a readable source title and page/section when available.
- Show quoted source text rather than a paraphrase presented as evidence.
- Do not dump a whole retrieval chunk, unrelated questions, internal passage IDs or long raw URLs into the review screen.
- Preserve stable, versioned evidence references. A citation must actually support its associated claim.
- If exact supporting excerpts are unavailable or contradictory, show the limitation and avoid inventing evidence or assigning an unsupported grade.

## 5. Maths input on the question screen

### Requested

- Mathematical input is a **notebook/deck setting**, not an Equation action displayed on every card.
- Show it only for relevant mathematical questions; enabling maths for a notebook must not automatically turn every question into a maths question.
- Use an in-app mathematical keyboard rather than opening a separate equation-editor page or defaulting to the system text keyboard for equation entry.
- Keep the learner on the original review screen. Edits must update the answer there immediately.
- Render the entered expression clearly, retaining editable structured/source content and cursor position.
- Follow Symbolab's input experience with category switching, templates and editing/navigation controls, while matching Engram's restrained theme and typography.
- Give keys more comfortable space than the referenced Symbolab keyboard where the device allows it. Avoid shrinking the question to an unreadable area.
- Support the previously requested full mathematical input vocabulary: arithmetic, fractions, powers, roots, variables, brackets, logarithms, trigonometry, derivatives, integrals, limits, sums/products, probability/binomial/combinatorics notation, sets, inequalities, matrices and related templates.
- This is an expression-input tool. **Do not add a CAS solver or automatic symbolic solving.**
- Preserve relevant existing question-type approval boundaries; this design does not authorize additional question types.

### Decisions to specify before implementation

- How a question declares that it accepts mathematical input, and how notebook defaults interact with question-level overrides.
- Basic versus advanced keyboard defaults, category organisation and optional switching to normal text for explanations.
- Cursor movement within templates, selection, deletion, undo/redo and incomplete-expression handling.
- How mixed text/math answers and symbolic equivalence are assessed, without silently introducing solver functionality.

## 6. Settings visual consistency

- Adapt the clean organisation shown in the ChatGPT settings reference: clear sections, aligned icon/text rows, restrained dividers, concise secondary text and compact actions.
- Avoid large nested panels, oversized explanatory blocks and multiple competing button styles.
- Preserve Engram's existing themes and approved controls; the reference is an organisational/style guide, not an instruction to reproduce every rounded container.
- Keep tutor activation and tutor management accessible from Settings.
- Place deferred grading, reveal-after-answer, voice confirmation and maths defaults in coherent locations without overcrowding the main settings screen.

## 7. Tutor extension

### Requested navigation

1. The user discovers/enables tutoring through a tucked-away **Tutor** entry in Settings; activation automatically creates or reopens their account-owned workspace.
2. After activation, a dedicated **Tutor** workspace appears as a folder-like destination in Library.
3. That destination contains the tutor overview and subject/deck assignment hierarchy.
4. Opening an assigned deck exposes its participating students and their progress.
5. Opening a student shows a detail screen using the same visual language as current notebook/deck detail.

Activation is a product entry point; it does not itself grant paid entitlement or student-data access. Existing account, purchase and consent rules still apply.

### Keep teaching content separate from personal study

- Tutor assignment decks must not automatically appear in the tutor's own due queue, Today review totals or review sessions.
- Distinguish tutor-owned teaching assignments from the tutor's personal study library in the data model as well as the UI.
- A tutor may deliberately choose to study a personal copy; that choice must be explicit and use an independent personal schedule.
- Student reviews remain personal learning events associated with the assignment's permitted progress projection.

### Tutor overview

- Provide a clean summary page inside the Tutor folder.
- Show students in readable rows with restrained progress bars beside their names.
- Allow grouping/filtering by subject and assignment where useful.
- Make students searchable by their permitted display name and relevant subject/assignment, within the tutor's authorized memberships only.
- Make the meaning of each bar explicit: for example assignment completion, not an unlabeled blend of completion and recall.
- Surface recent activity, reviews completed/due/overdue and evidence-supported concerns without a crowded dashboard of cards.
- Distinguish lack of data from poor progress. Avoid ranking students by an unexplained composite score.

### Assignment and student details

- Each shared-deck folder/destination contains its relevant students.
- Use the current notebook/deck detail aesthetic for each student's assignment progress.
- Show relevant measures: estimated recall where supported, review completion, overdue work, last activity, topic-level difficulties and shared misconception summaries.
- Keep summaries scoped to the selected assignment and timeframe; explain estimates and incomplete data.
- Provide clear routes between the overview, subject, deck and student without exposing internal record identifiers.
- AI concern summaries need evidence, uncertainty and appropriate attribution; they must not silently change grades or send messages to students.

### Privacy inherited from the approved tutor plan

- Tutors see authorized progress and explicitly shared misconception summaries only.
- Do not expose raw student answers, recordings, private chats, private memory or unrelated library content.
- Assignment evidence and progress access require current membership/consent and server-side authorization.
- Retain invitation, revocation, entitlement and age/guardian requirements already recorded in the tutor plan. The Library folder does not bypass them.

### Design assessment and recommendation

This extension fits the app: Library becomes the home for learning and teaching material, while Settings contains tutor activation and account controls. The strongest approach is a dedicated Tutor workspace that resembles the Library hierarchy but opens purpose-built progress views. Treating tutor assignments as ordinary personal decks would blur study totals and permissions, so keep their roles explicit underneath the shared aesthetic.

## 8. iPhone, iPad landscape and Mac

- iPhone: retain the approved MCQ layout; use a borderless typed-answer area, an inline maths keyboard and a vertically readable feedback summary. Tutor views use rows and drill-down navigation.
- iPad landscape/Mac: use the available width for question/answer placement and optional adjacent feedback/evidence panes. Maths input stays associated with the active answer, without a separate editor page.
- Tutor landscape layout can use a Library-style sidebar for subjects/assignments, a student list and one focused progress-detail pane.
- Larger-device layouts must not change the phone layout unintentionally. Validate shared components at compact widths, large text sizes and with the keyboard visible.
- All themes, accessibility labels, meaningful touch targets and reduced-motion alternatives must remain supported.

## 9. Future implementation checks

These are acceptance criteria for a later authorized implementation, not work to begin now.

- Capture changed screens before/after on iPhone and iPad landscape, following the existing `current_ui` evidence convention.
- Verify short, long, empty and multiline typed responses, keyboard transitions and large accessibility text.
- Verify no Equation action on non-maths questions; test notebook/question overrides and full mathematical templates inline.
- Test batching across session end, partial failures, restart, account changes, stale content and retries; confirm each accepted grade commits once.
- Measure per-answer waiting, batch completion time, token usage and assessment quality with realistic evidence.
- Test optional post-attempt answer reveal and transcript confirmation without changing the original recall result.
- Validate exact citation excerpts and annotation offsets, including Unicode and mixed text/math.
- Test tutor activation, Library navigation, subject grouping and personal-study exclusion.
- Verify progress/misconception-only access and revocation with owner, student and outsider accounts.

## 10. Advanced database instrumentation for research

### Purpose and collection design

The user requests comprehensive research instrumentation. Collect structured events and reproducible measures across the learning lifecycle, rather than an unbounded dump of every screen, text field or AI payload. Keep operational/account records, consented research data and tutor-visible projections separate. Research access must not expand tutor access.

Record a versioned event vocabulary and metric definitions before implementing collection. Every measure must identify whether it is observed, calculated or estimated. Preserve enough scheduling/model/content context to interpret results after an algorithm or prompt changes.

| Area | Planned measurements |
| --- | --- |
| AI performance | Workflow, provider/model, request/batch ID, answer count, queue delay, request start, first visible text, first tool event, completion, validation and grade-commit timings; cancellation, timeouts, sanitized error categories, retries, connection class and cache usage |
| AI resource use | Input/output/cached/reasoning tokens when reported; usage availability; word/character counts; model-specific tokenizer estimates where supported; estimate method/version/confidence; audio duration and provider billing units; price version and separately labeled estimated versus settled cost |
| Retrieval/grounding | Retrieval duration, candidate/selected evidence counts, relevance measures where available, question/evidence versions, citation validity, contradictory/insufficient evidence flags, context size and reference coverage |
| Study sessions | Session start/end, foreground active time, question dwell time, input/editing time, interruptions, question/input type, session exit/completion, pending marking backlog, reveal/hint use and assisted status |
| Learning outcomes | Original attempt outcome, automatic/manual/disputed grade, assessment revisions, correctness where objectively available, due-versus-actual review time, review count, stability/difficulty and estimated recall snapshots, scheduler/settings versions, future outcomes and spaced follow-up intervals |
| Voice | Recording/transcription latency, duration, input language, provider confidence if available, uncertain-token counts, confirmation time, learner correction counts, playback interruption and failure categories; no raw recording collection by default |
| Maths and question types | Keyboard/category/template use counts, answer modality, editing duration, expression-validity categories, abandonment and outcome by question type; no continuous keystroke log |
| Feedback and quality | User feedback category, optional consented comments, disputes/reasons, resolution, grade-change frequency, citation complaints, rubric-validation failures and model/content version attribution |
| Tutor assignments | Consented assignment completion, overdue reviews, shared misconception categories, insight usefulness/dismissal, assignment revisions and aggregate progress, scoped to authorized research participation |
| Product reliability | App/build/OS versions, broad device class, theme/accessibility configuration where relevant and consented, crashes/sanitized error signatures, sync latency/conflicts, offline duration and event upload loss/duplicates |

### Token and cost accuracy

- Preserve provider-reported usage as reported; never replace it with a rough estimate.
- When usage is absent, prefer a suitable local tokenizer; otherwise store word/character counts and a labeled approximation. A word-count heuristic is not an exact token measurement and varies with language, maths and code.
- Distinguish truly zero usage from missing/unknown usage.
- Measure batch usage at the actual request level. Per-answer allocation is an estimate; record its allocation method and do not pretend the provider reported individual usage.
- Separate queue delay, model request time and perceived learner wait. Batching success is judged on all three, plus accuracy and cost.
- Track external-provider estimates separately from authoritative app-credit debits. Telemetry never grants credit or becomes the billing ledger.

### Retention and research validity

- Record question type for every attempt, including MCQ, multiple-select, short answer, cloze, ordering, matching, classification, multiple blanks, numeric, number-with-units, equation, spot-errors and correct-errors wherever supported. Future types must register a stable identifier and schema version before use; this catalogue does not authorize new implementations.
- Keep question type, subject/domain, presentation (including reversed/cloze variants), input modality and grading method as distinct fields. Analyse later correctness, latency, disputes and time spent by each of these dimensions rather than blending all questions together. Preserve original MCQ choice IDs despite randomized displayed letters.
- Keep **estimated recall** separate from **observed later correctness**. FSRS forecasts do not establish that a learner actually retained the material.
- Record elapsed time, prior reviews, difficulty, assistance, question changes and input modality alongside outcomes.
- Distinguish a learner returning to the app from memory retention. Define daily/weekly engagement metrics separately.
- Record missing follow-ups, withdrawals and interrupted sessions; avoid treating absent data as failure or excluding it invisibly.
- Compare estimated recall with later unassisted outcomes for calibration, with uncertainty and sample size.
- Distinguish objectively graded MCQs from AI-assessed answers. Track grading disputes and confirmed revisions to study grader reliability.
- Use foreground/activity signals with idle thresholds to measure active study time; wall-clock session length alone is misleading. Store the definition/version and support offline timestamps plus server receipt time.

### Proposed database architecture

- Add an account-scoped durable local event outbox so offline study does not lose events. Upload in bounded batches; telemetry failures must not block answering or grading.
- Ingest through an authenticated, schema-validating server operation with rate/size limits and idempotent event IDs. Actor/account identities come from the authenticated session.
- Use append-only structured event records, separate AI request/usage records, attempt/assessment links, consent records and derived daily aggregates. Keep content-bearing research records in a separately restricted collection.
- Include event/schema version, session/attempt/request/batch/assignment correlation IDs, client occurrence time, server receipt time and app revision. Detect clock skew and out-of-order delivery.
- Use pseudonymous research participant IDs and a restricted mapping to operational accounts. Pseudonymous linked longitudinal data is not claimed to be anonymous.
- Deduplicate retries and rebuild aggregates reproducibly. Preserve original grading events and correction events rather than overwriting the historical result.
- Give ordinary clients no ability to read other participants' events or arbitrary research tables. Enforce membership, consent and resource access server-side; do not ship a privileged database key.
- Use restricted research views/exports, audited researcher access, suppression of identifying small groups where applicable and explicit dataset versions.
- Define retention/deletion jobs and indexing/partitioning from expected volume. Sample high-frequency interaction events if needed while retaining required outcome records. Do not create an event per animation frame or every keystroke.
- Attach consent purpose/version to research collection and define how withdrawal affects future collection, identifiable historical data and already released aggregates/exports.

### Content, privacy and scope to decide

- Recommended baseline: operational metrics plus separately opt-in, pseudonymous learning research; raw answers/transcripts require an additional explicit choice.
- Do not collect API keys, OAuth tokens, passwords, payment secrets, clipboard contents, precise location, unrelated files or other apps' activity.
- Do not copy entire chats, PDFs, notes or raw audio into telemetry by default. Content necessary for normal app functionality is not automatically authorized for secondary research use.
- Redact identifiers from errors and feedback exports. Optional free-text feedback can still contain identifying information and needs appropriate handling.
- Research participation does not authorize a tutor to inspect raw answers or private material.
- Since the existing pilot includes all ages, define age-appropriate research consent/guardian handling before collecting research data from participants requiring it. Do not infer consent from account creation or a tutor invitation.

### Decisions requiring user direction

1. Should research participation be opt-in separately from ordinary app usage? Recommended: yes; declining preserves study functionality.
2. Is the initial research dataset metrics/outcomes only, or does it include separately consented raw answers and transcripts? Recommended: metrics/outcomes first, with a separate content opt-in for later grading-quality research.
3. What retention period and researcher access are intended? Proposed starting point: 12 months for individual-level research events, reviewed aggregate retention thereafter, access restricted to the project owner initially. These are proposed defaults, not a claim of anonymity or a settled policy.

### Additional acceptance checks

- Validate event schemas, units, absent usage, batching attribution, retries and deduplication.
- Test offline/restart behaviour, account switching, clock skew and backpressure without disrupting study.
- Verify consent denial/withdrawal, retention/deletion and participant export workflows.
- Test owner/researcher/tutor/student/outsider access separately, including joins and exports.
- Ensure secrets and unapproved raw content never appear in captured events or logs.
- Compare computed aggregates against known session/attempt fixtures and measure instrumentation overhead.

## 11. Scope boundary

This step updates the planning document and discusses research instrumentation. No UI, database migration, collection switch, phone installation, hosted tutor access or billing change has been performed. The user has requested eventual telemetry implementation; settle the research collection choices before enabling it for real participants.
