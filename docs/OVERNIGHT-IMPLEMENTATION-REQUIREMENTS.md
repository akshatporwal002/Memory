# Engram: consolidated implementation requirements

Recorded: 4 October 2026, Australia/Sydney.

Status: agreed requirements and implementation plan, not a claim that these features have been implemented. This document consolidates the latest UI, accounts, voice, billing, test-deck, tutor and maths requests. Later explicit user instructions take precedence.

## 1. Goal and delivery order

Preserve Engram's clean, minimalist quiz aesthetic while improving account usability, voice review and advanced mathematical input. Design for both iPhone and iPad landscape. Minimalism means coherent, purposeful controls and readable content, not removing useful functionality.

Delivery order:

1. UI shape audit, direct sign-in and account/connection fixes.
2. Shared AI providers, cloud voice and durable review processing.
3. Billing foundations with production charging disabled.
4. Testing decks available to the user.
5. Early maths-input implementation and tutor-feature specification.
6. Add ordering questions: learners rearrange shuffled steps into the correct sequence.

Keep implementation on a review branch; preserve unrelated changes from other tasks. Validate and commit stages independently, push changes for review, and record actual completion and remaining limitations. Avoid repeated reviews that produce no meaningful improvement.

## 2. Minimalist UI requirements

- Remove the disliked outlined rounded-rectangle action style exemplified by **Connect another account**. Audit its use app-wide, including sign-in, settings and other actions.
- Replace actions with restrained pill-shaped controls, similar to **Reconnect**, or simple text/icon actions where appropriate.
- Replace unnecessary enclosing settings cards with flat rows, subtle separators and clear spacing. Avoid boxes inside boxes and crowded explanatory text.
- Preserve the currently approved glass chat bubble. It is explicitly exempt from the shape cleanup.
- Retain theme compatibility, semantic colours, readable contrast, accessibility labels, minimum 44-point touch targets and reduced-motion behaviour.
- Preserve the approved iPhone quiz layout except for changes required by newly requested input types.
- iPhone: compact, readable single-column screens. iPad landscape: make deliberate use of sidebars and wider content panes, without stretching phone controls across the screen. Share styles and behaviours, not rigid layout dimensions.

## 3. Unified sign-in and account management

- Put sign-in choices directly inside **AI & Connections**, replacing the current nested account entry and large ChatGPT connection component. Signing in should not require opening another settings screen first.
- Offer ChatGPT, Google, Apple and email on this screen.
- When ChatGPT is connected, replace **Continue with ChatGPT** with a compact **Manage ChatGPT** entry. Move reconnect, disconnect, connection switching and usage/access management into that submenu.
- Continue offering additional login methods after sign-in so the user can connect Google, Apple or email to the same app account.
- Distinguish **link a login method** from **switch app account**. Linking must preserve the Supabase user ID and its libraries. Do not silently merge distinct existing accounts, including accounts with similar email addresses.
- Keep app identity and AI-provider permissions technically separate while presenting them in one coherent screen. Do not imply ChatGPT OAuth is a Supabase session when it is not.
- For an existing ChatGPT-only local profile, establishing a cloud account through a supported login method must offer an explicit local-library transfer while preserving the AI connection. Retain the local data until transfer is verified.
- Apple authentication must have its signing entitlement and provider configuration before being offered as functional. Unsupported preview builds should display a concise setup explanation rather than the raw authorization error shown in the user's screenshot.
- Errors and connection status should be concise and actionable, without large distracting panels.

### Duplicate ChatGPT connections

- Signing out and signing back in must not accumulate obsolete connections.
- Reuse/update registrations by verified identity, using issuer and subject rather than email alone. Preserve legitimate distinct accounts.
- Remove disconnected local entries and superseded credentials; distinguish local disconnection from successful remote revocation.
- Migrate the already accumulated entries, retaining the active usable connection and its consent state. Keep internal registration IDs out of the main UI.
- Serialize sign-in, sign-out and refresh so interrupted or concurrent operations cannot restore removed credentials.

## 4. AI providers and voice

Use [VOICE-TRANSCRIPTION-AND-BILLING-PLAN.md](VOICE-TRANSCRIPTION-AND-BILLING-PLAN.md) as the detailed baseline for transcription, answer jobs and payment behaviour. These newer requirements extend it with Google BYOK, optional cloud speech output and an optional combined audio mode; they supersede its conflicting deferrals of those capabilities.

### Provider architecture and keys

- Retain ChatGPT and add Google Gemini API and OpenAI API connections through the shared provider-neutral transport.
- Use the same retrieval, evidence validation and application-action system across chat, grading and PDF generation.
- Support Google and OpenAI bring-your-own-key configuration: masked entry, validation, replacement and deletion. Keep keys in device-only Keychain, excluded from logs, backups, library synchronization and the managed backend.
- Make model selection capability-aware. Allow separate conversation, grading, transcription and speech-output choices; never silently substitute an unavailable provider or billing path.
- Prepare Vertex/GCP integration code and deployment/configuration instructions without requiring credentials overnight. Service-account credentials must remain server-side.

### Speech experiences

- Support both separate speech services and a combined listening/speaking experience where feasible. Prioritize **transcription → grounded grading → speech playback** as the reliable initial implementation.
- Follow the voice document's default managed transcription selection: GPT-4o Mini Transcribe. Retain its other provider/model choices and readiness/usage comparisons.
- Keep local Parakeet transcription and Kokoro/system speech available under the agreed entitlement rules.
- Add optional Google/OpenAI cloud-generated speech. Disclose the provider, audio destination and usage cost; retain local output as the default unless the user selects cloud output.
- Prepare a feature-flagged Gemini Live adapter for combined audio interaction. It must use the same independent grading and scheduling boundaries rather than allowing spoken model output to directly award a grade.
- Interrupt playback as soon as the user starts speaking. Cancel stale queued speech and prevent the microphone from treating generated playback as the user's answer.
- Preserve negations, self-corrections and mistakes. Context may help recognition, but must not invent a more correct answer than the user gave.
- Missing credentials or unsupported capabilities should show **Not configured** or an actionable equivalent. Do not claim live provider validation from fixtures alone.

### Durable review processing

- Implement **Continue while processing** and **Wait for feedback**, defaulting to Continue, as specified in the voice document.
- Persist the original answer and question/content versions before advancing. Preserve original submission time, provider, billing path and grading identity.
- Limit unresolved submissions to ten, with at most two transcription workers and one marking worker. Pending cards cannot immediately recur in the queue.
- Results do not steal focus or speak over the next answer. Provide a compact pending indicator and a review summary for incorrect, partial and unresolved attempts.
- Preserve work across review exit, app suspension and restart. Do not promise continuous background execution on iOS.
- Commit supported assessments exactly once. Preserve the existing correct/partial/incorrect/unclear grading mappings; ambiguity, provider failure or insufficient evidence produces no automatic grade.
- Transcript correction invalidates the previous assessment and reconciles its scheduling effect. Superseded jobs cannot commit late results.
- Keep raw audio in protected, backup-excluded storage until transcription succeeds. Delete successful recordings; retain failed recordings for retry for up to seven days or until the user deletes them. Do not synchronize raw audio.

## 5. Billing foundations and release boundaries

The user explicitly chose to retain the existing voice document's billing rules:

| Voice access path | Planned production payment |
|---|---|
| Managed cloud voice | Prepaid app credits |
| Personal API key or local voice | US$2/month voice entitlement; no app-credit deduction |

- Prepare StoreKit 2 purchase/restore handling and server interfaces for verified purchases, entitlements, wallets, usage reservations and settlement.
- Keep sandbox and production ledgers separate. Production charging remains disabled until deliberately configured and validated.
- Use unique transaction/job IDs and authoritative backend accounting to prevent duplicate purchases, reservations and charges. Client preferences and backups cannot mint credit.
- Personal-key usage is billed by the provider and must never deduct app credits.
- Managed transcription and optional cloud speech have separately disclosed usage rates. Failed jobs/internal retries must not create duplicate customer charges. Successful transcription remains chargeable if later grading fails; grading-only retries do not retranscribe or recharge.
- Purchased credits do not expire. Cover refunds/revocations, pending purchases, subscription expiry, cross-device access and insufficient credit.
- Simulated development balances are for fixtures, not unlimited managed-provider access. Real BYOK testing may still incur the user's provider charges.
- Prepare configuration placeholders for products, secrets, rates and limits; do not present illustrative prices as verified launch settlement rates.

## 6. Testing decks and account import

- Provide a **Testing** folder containing an AWS multiple-choice deck, an AWS short-answer deck for voice marking, and maths-input examples.
- Use original AWS questions checked against official AWS documentation, with reference answers, explanations and evidence links. Do not copy protected exam dumps.
- Include long questions/options, paraphrases, partial responses, negations and deliberately incorrect responses so workflows can be exercised beyond the happy path.
- Randomize MCQ presentation while retaining canonical choice identities and correct letter mapping.
- Give sample content stable IDs. Repeated imports must not duplicate it or overwrite the user's edits without an explicit choice.
- Make samples immediately usable locally. Add a one-time import into the authenticated user's account when available, through the normal versioned application/sync operations.
- Planning-time inspection found no registered users in the configured Supabase project. Recheck before importing; do not assume an arbitrary first user is the owner, create a placeholder account or bypass authentication/RLS to seed someone else's library.

## 7. Full mathematical equation-entry keyboard

**The user wants a full CAS-style input kit inspired by Symbolab's phone keyboard, not a CAS solver.** This requirement is broader than fractions, powers and roots.

Latest clarification: provide the full range of mathematical input controls, including integrals and probability/binomial expressions. “CAS-style” describes the keyboard's notation and editing experience; it does not authorize adding a symbolic solver. Equations should remain easy to enter, edit and read on both iPhone and iPad.

- Provide organized palettes/templates for arithmetic, fractions, powers, roots, algebra, inequalities, brackets, Greek symbols, trigonometry and logarithms.
- Include advanced notation: derivatives, definite/indefinite integrals, limits, summations/products, matrices/vectors, sets, piecewise expressions and probability/statistics.
- Probability input must include factorials, permutations/combinations, binomial notation/distributions and other common distribution notation, including normal and Poisson expressions.
- Use structured templates with editable placeholders, sensible cursor movement, nested editing and a readable mathematical preview. Avoid making users type raw LaTeX for routine entry; preserve a portable source representation.
- Organize the full palette into compact categories; do not crowd every symbol onto one screen. Support touch input on iPhone and touch/hardware keyboard input on iPad.
- Equation entry does **not** solve or evaluate an answer and does not itself count as calculator assistance.
- Keep optional evaluative calculators separate. Deck settings select **Off / Basic / Scientific**, with input appropriate to each question's level.
- The user explicitly chose **normal grades when calculator use is allowed by the deck**. Record tool use; AI answer reveals remain assisted.
- Begin with backward-compatible numeric response metadata, explicit tolerances and deterministic grading of supported numeric responses. Retain equation submissions for manual/evidence-backed feedback when automatic equivalence is unsupported.
- Do not implement or promise a Symbolab/CAS solving engine or unrestricted expression execution. Full symbolic-equivalence grading is not required by this goal.

## 8. Tutor feature: plan before full implementation

- Plan a paid tutor tier around **A$3 per tutor per month total**, initially allowing **five active students**. This is a provisional commercial target, not an activated product.
- Tutors can invite students, assign decks, set due dates and monitor assigned-work progress.
- AI can flag supported misconceptions and concerning progress patterns, citing the underlying assigned-work evidence. Treat flags as suggestions, not diagnoses or automatic interventions.
- Tutors see **assigned work only**. Personal libraries, chats and unrelated learning history remain private.
- Plan invitation acceptance, permissions, student removal, revocation, retention, and age/guardian-consent handling.
- Define a capped AI-insight allowance and assess hosting/provider costs before activating the price. A provisional weekly insight cadence is preferable to unlimited automatic analysis.
- Deliver a clear specification and architectural boundaries first; a complete tutor platform is not required in the initial implementation.

## 9. Verification, screenshots and configuration handoff

- Test repeated OAuth sign-in/out, connection migration, identity linking, cancellation and account/library isolation.
- Test voice interruption, echo, noisy recordings, concurrent/out-of-order jobs, restart, corrections, stale evidence and exactly-once grading.
- Test API-key isolation, provider errors, purchase replay/refunds, reservation concurrency and sandbox/production separation.
- Test repeated sample imports, MCQ randomization, numeric tolerances, full keyboard templates and calculator policy.
- Review all changed screens on iPhone and iPad landscape across themes, keyboard states, accessibility text sizes and reduced motion.
- Capture before/after screenshots grouped by view under `current_ui`; retain only the current and one previous capture per view. Mark fixture screenshots and untested live features accurately.
- Validate stages on the Mac, push reviewable commits, and install a validated phone preview. Explicitly disclose signing/provider limitations rather than treating a successful build as proof of live authentication or audio quality.
- Morning setup may require GCP project/region/server credentials, managed OpenAI secrets, Apple sign-in provisioning/provider configuration, StoreKit product IDs/sandbox setup, and the user's first successful cloud-account sign-in.

## 10. Temporary PC stay-awake authorization and mandatory cleanup

The user explicitly authorizes launching a temporary PowerShell stay-awake helper when needed to prevent the PC sleeping during implementation.

- Keep the computer awake only for active authorized work. Prefer a process-scoped Windows execution-state request; do not permanently change power settings.
- Track the helper's PID/session and ownership so cleanup targets only the helper launched for this work.
- Use a hidden background window if a background helper is needed. Keeping the display permanently on is not required.
- **Stop the helper and release the wake request before ending the implementation response, on success, failure, cancellation or an input-dependent stop.** Treat cleanup as a required final acceptance item, not an optional reminder.
- Verify cleanup and report any failure to stop it. Do not claim cleanup merely because a stop command was attempted.
- If a goal is created for implementation, include stay-awake startup/cleanup explicitly in the objective/checklist.
- This document authorizes the helper but does not claim one is running. Creating requirements alone does not need a stay-awake process.

## 11. Ordering questions (additional user requirement)

- Add a question type with a jumbled sequence of steps that the learner rearranges into the correct order.
- Store canonical step identities and the expected order separately from the shuffled presentation. Retain that presentation during an attempt so it does not reshuffle while editing.
- Provide drag reordering plus accessible move-up/move-down controls and an explicit submit action on iPhone and iPad landscape.
- Grade the submitted sequence locally against the canonical order; show corrections/explanation after submission. A complete correct order maps to Good, an incorrect order to Again; incomplete or invalid submissions receive no automatic grade.
- Support creation/editing and testing examples, including AWS process steps. Preserve old cards and backups through optional backward-compatible metadata.
- Allow equivalent valid sequences and partially ordered steps when the subject permits them; do not mark a valid alternative wrong merely because it differs from one sample sequence. Exact-order grading remains the initial implementation.

## 12. Expanded question-type catalogue and learning-platform direction

### User direction and delivery boundaries

- Support a broad range of learning activities across subjects. The user prefers extensible feature support that can later be hidden or removed if unused.
- Explicitly add **select multiple answers**, **spot/debug incorrect code**, and the equivalent **identify/correct English grammar errors** to the roadmap, alongside ordering questions.
- The catalogue below records proposed types and examples. It does not claim they already work or require every advanced activity to ship in the first overnight implementation. Build reusable foundations, then deliver and validate types in stages.
- Keep authoring and study screens minimal: show only controls relevant to the current question. Offer advanced question types through a categorized picker rather than adding permanent controls everywhere.

### Recall, selection and relationships

| Question type | Learner interaction and examples | Assessment approach |
|---|---|---|
| Single-choice | Select one answer; existing MCQ | Canonical choice ID, local pass/fail |
| Multiple-select | Select every applicable answer; AWS services, symptoms, valid statements | Explicit submit; expected set, with optional diagnostic partial credit |
| True/false with correction | Judge a statement and correct it if false | Local judgement plus supported correction rubric |
| Short answer | Type or speak a definition, explanation or translation | Reference/evidence-backed rubric; manual fallback |
| Cloze and multiple blanks | Complete missing words, numbers or expressions in context | Per-blank accepted answers and normalization rules |
| Word-bank completion | Place supplied terms into blanks, optionally with distractors | Stable term/slot IDs; allow reuse only when specified |
| Matching | Pair terms/definitions, countries/capitals, equations/graphs | Canonical pairs; accessible alternatives to dragging |
| Classification | Sort examples into categories; diseases, grammar, algorithms | Item-to-category mappings; optional multi-category membership |
| Odd one out | Identify the exception and optionally explain why | Accepted exceptions and rationale rubric |
| Ordering | Rearrange shuffled steps, events, sentences or code blocks | Exact sequence first; equivalent/partial orders later |
| Ranking | Rank by magnitude, priority, likelihood or importance | Expected ranks, ties or evidence-backed criteria |
| Relationship matrix | Mark which features apply to each item in a grid | Canonical row/column relationships |
| Free recall list | Name examples, stages or properties without seeing options | Required concepts, accepted synonyms and duplicate handling |

### Mathematics, science and data

| Question type | Learner interaction and examples | Assessment approach |
|---|---|---|
| Numeric response | Enter an integer, decimal, fraction or percentage | Explicit precision/tolerance; equivalent numeric forms |
| Quantity with units | Enter value and unit; physics, chemistry, medicine | Unit conversion, dimension checks and tolerance |
| Equation/expression entry | Enter algebra, integrals, probability or matrices using the full maths keyboard | Supported comparison rules; manual/rubric fallback, no implied CAS solver |
| Worked solution | Submit intermediate steps rather than only the final result | Step rubrics and supported error feedback |
| Missing derivation step | Complete a gap in a proof or calculation | Accepted step alternatives or rubric |
| Find the mathematical error | Select the first invalid step and correct it | Stable step IDs plus justification |
| Estimation | Approximate a value or order of magnitude | Author-defined range and reasoning criteria |
| Graph interpretation | Read values, slopes, trends, intersections or uncertainty | Chart data and answer rubric |
| Graph construction | Plot points, sketch a curve or position a line | Defined geometric constraints; tolerant comparison |
| Table completion | Fill spreadsheet-like cells, truth tables or data summaries | Per-cell values, formulas or permitted alternatives |
| Chemical notation | Enter formulas, balance equations or identify structures | Structured notation; dedicated validation where supported |
| Proof/argument construction | Arrange or write a logical argument and justify transitions | Dependency rules and rubric; no unsupported correctness claims |
| Experiment design | Choose controls, variables, measurements and predicted outcomes | Explicit scientific-method rubric |

### Programming, language and critical reading

| Question type | Learner interaction and examples | Assessment approach |
|---|---|---|
| Spot the error | Select incorrect tokens, lines or phrases in code/grammar | Stable source spans; distinguish required errors from acceptable alternatives |
| Repair the error | Edit faulty code, punctuation, grammar or reasoning | Reference fixes plus accepted alternatives/rubric |
| Predict the output | Give program output, variable state or execution trace | Deterministic expected result; ambiguity checks |
| Code completion | Fill expressions, statements or missing implementation | Static checks or explicitly configured sandboxed tests |
| Code-writing task | Implement a small function or SQL query | Isolated tests plus rubric; no unrestricted execution |
| Parsons problem | Rearrange code blocks into a working program, optionally discarding distractors | Valid block order/dependencies and tests |
| Trace a process | Step through an algorithm, circuit, protocol or calculation | Expected state transitions |
| Translate | Translate text or audio between languages | Accepted meaning/grammar rubric; alternatives allowed |
| Dictation | Hear audio and transcribe it | Normalized reference plus spelling/punctuation policy |
| Pronunciation | Speak a word or sentence | Dedicated audio assessment when available; transcription alone is insufficient |
| Reading comprehension | Answer from a passage, source or document | Passage-grounded evidence and rubric |
| Annotate evidence | Highlight text supporting a claim | Accepted evidence spans and rationale |
| Rewrite/edit | Improve clarity, tone, style or grammatical correctness | Explicit criteria; preserve legitimate stylistic alternatives |
| Essay/argument | Explain, compare, critique or defend a position | Visible rubric and feedback; distinguish judgement from factual correctness |

### Visual, spatial, listening and applied learning

| Question type | Learner interaction and examples | Assessment approach |
|---|---|---|
| Image occlusion | Recall labels hidden on an anatomy map, schematic or diagram | Stable hidden regions and accepted labels |
| Diagram labeling | Place labels on structures, maps, circuits or apparatus | Stable targets; non-drag accessible input |
| Hotspot identification | Tap a relevant region, fault, landmark or component | Defined regions with touch tolerance |
| Drawing/sketch response | Draw a structure, flowchart, force diagram or concept | Rubric/manual feedback; constrained geometric checks where feasible |
| Map/spatial task | Locate places or arrange components spatially | Coordinates/relations with explicit tolerances |
| Audio identification | Identify a sound, spoken word, interval, rhythm or instrument | Author-provided reference; replay policy |
| Music notation | Enter/read notes, chords, rhythms or intervals | Structured musical representation and accepted variants |
| Scenario decision | Choose and justify an action in a clinical, legal, business or technical case | Source-grounded decision rubric and alternatives |
| Branching scenario | Decisions lead to new information and follow-up questions | Authored branches; assess decisions separately from navigation |
| Compare and contrast | Identify similarities/differences using text or a structured table | Required concepts and permitted interpretations |
| Concept map | Connect ideas with labeled relationships | Expected/valid relationships; rubric for open maps |
| Teach-back | Explain a concept to a novice, by text or voice | Coverage, accuracy and clarity against evidence |
| Practical checklist | Record completion of a lab procedure, skill or observation | Explicit self/teacher assessment; no claim of verified physical performance |
| Portfolio submission | Submit an image, recording, file or longer piece of work | Teacher/manual or supported rubric assessment |
| Confidence/reflection | Record confidence, uncertainty or what was learned | Unscored metadata; not evidence of correct recall |

### Shared implementation requirements

- Separate **response format**, **grading method**, **learning workflow** and **scheduling policy**. A passage, diagram or branching case can contain several response formats without creating a separate engine for every combination.
- Use a versioned question definition containing prompt/media/evidence, response schema, accepted answers or rubric, interaction settings and assistance policy. Persist an attempt against its exact question version.
- Keep choice, step, slot, region and source-span identities stable while shuffling the visible presentation. Never use shuffled letters/positions as stored answer identity.
- For multiple-select, allow deselection and explicit submission. State whether the required answer count is disclosed. Do not auto-submit after the first selection or silently penalize a hidden rule.
- Keep correctness grading local where answer rules are deterministic. Use grounded AI for open responses, with uncertainty and manual review rather than invented grades. AI feedback must accept legitimate alternative solutions.
- Diagnostic partial credit is separate from FSRS scheduling. Initially, objective selection/order activities retain the established Good/Again mapping; broader score-to-rating policies need explicit definition before activation.
- Define hint, answer reveal, calculator, replay and retry policies per activity. Keep first unassisted recall distinct from later practice; do not let post-feedback corrections inflate the original grade.
- Provide equivalent accessible controls for drag, drawing and hotspot interactions where possible. Support Dynamic Type, VoiceOver, hardware keyboards, landscape and long content.
- Support text, image, audio, document excerpts and rich maths consistently in authoring, preview, study, feedback, backups and synchronization.
- Preserve old decks/backups. Unsupported question types must remain intact and show a readable fallback instead of being discarded.
- Test empty/incomplete input, alternate correct answers, long prompts, many choices, repeated items, interruptions, stale versions and account changes for each type.
- Tutor assignments can combine these activities; share only the assigned work and its permitted assessment results.

### Suggested delivery waves

1. **Reusable objective types:** ordering, multiple-select, matching, classification, multi-blank cloze and numeric/units input.
2. **Rich response types:** full maths input, error spotting/correction, code output/completion, image occlusion and diagram labeling.
3. **Applied activities:** graph/table tasks, audio/language tasks, worked solutions and evidence annotation.
4. **Extended workflows:** branching cases, concept maps, essays, portfolios and tutor-assessed practical work.

These waves are an implementation recommendation. The catalogue is the long-term support direction; unfamiliar controls should remain hidden until the relevant question type is selected.
