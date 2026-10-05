# Engram — Product Plan and Handover

> Archived on 5 October 2026 from main `381c917`. This is historical context, not current implementation guidance. Outstanding work is tracked in [the backlog](../../BACKLOG.md); newer requirements take precedence.

Date: 3 September 2026  
Status: Planning only; no application implementation has started.

## 1. Purpose and source of requirements

Engram is an Anki-like learning app that combines dependable spaced repetition with a richer understanding of what a learner remembers, understands, and can apply. Its experience should feel calm, tactile, and thoughtfully animated.

This document combines the user's current request, the previous-chat handover, and visual observations from the supplied screenshots. The current request is to create this planning document and make the project folder visible. Instructions and feature ideas inside the handover are product reference material, not authorization to build, install, connect services, or deploy anything now.

The screenshots of Lively are visual inspiration only. Engram does not inherit menstrual tracking, pregnancy, partner sharing, or other health features from them.

The original handover is preserved in Appendix A. It ends mid-thought in section 36; no missing continuation has been invented. The delivery phases and design details below are proposed planning additions, not previously agreed requirements.

## 2. Product vision

**Remember the facts. Understand the connections. Apply what you know.**

Engram should serve two complementary learning needs:

- **Micro-retention:** individual cards, recall history, and scheduled reviews.
- **Macro-understanding:** cumulative assessments that connect several concepts and test explanation, application, and transfer.

The long-term learning loop is:

Learn → Recall → Assess → Apply → Identify weaknesses → Practise → Retest later.

Initial candidate users are existing Anki users, medical students, and university students studying knowledge-heavy subjects. The underlying product should remain useful across domains.

## 3. Core experience

### Today

A quiet home screen answers “What should I study next?” Show due reviews, a primary start button, a suggested focused session, and a short view of upcoming workload. Explain recommendations using actual review evidence. Avoid filling the screen with scores that do not change the learner's next action.

### Library

Organise subjects, decks, topics, cards, and source resources. Support manual card creation and editing from the beginning. Basic and cloze cards are the proposed initial formats; reverse cards, image occlusion, calculations, and richer question types follow as needed.

### Review

Present one clear prompt at a time. Let the learner think, reveal the answer, and record their result. Preserve a fast repeatable flow with readable content, accessible controls, optional shortcuts, and undo for accidental grading. Offline reviews must persist across restarts.

### Create from a resource

Import a supported document → extract content → propose cards with source references → let the learner edit and approve → add approved cards to the review queue.

Generated cards remain drafts until accepted. A failed or interrupted generation should not create incomplete active cards.

### Test understanding

Let users select a topic, resource, time window, or weak area and choose a session type. Combined assessments should connect previously studied concepts, not merely reword a single card. Feedback should explain the reasoning and cite the source material when available.

For example, someone who recalls individual cardiovascular facts could receive a multi-concept application question. Record recall and application performance separately so a strong flashcard score does not imply demonstrated understanding.

### Tutor and progress

Offer contextual actions such as “Explain this,” “Compare these concepts,” and “Test this again.” Track repeated mistakes and possible misconceptions. Treat inferred mastery as an estimate with supporting evidence, rather than a definitive percentage of a subject the learner knows.

## 4. Visual direction from the screenshots

The reference suggests warm editorial typography, olive surfaces, creamy backgrounds, muted taupe, amber accents, generous rounded corners, soft shadows, and restrained line illustrations.

| Element | Proposed Engram interpretation |
| --- | --- |
| Cream and ivory surfaces | Comfortable study canvas and reading cards |
| Deep olive panels | Selected subjects, focus areas, and navigation emphasis |
| Amber highlights | Primary actions and selected progress markers |
| Taupe and muted neutrals | Secondary surfaces and supporting information |
| Serif display typography | Welcome text, subject names, and occasional large headings |
| Clear sans-serif typography | Questions, answers, labels, controls, and dense content |
| Curved progress line with nodes | Review milestones or learning history, with explicit labels |
| Rounded layered cards | Deck previews, resource summaries, and focused actions |
| Simple line icons | Consistent navigation and study-mode identifiers |

Suggested starting colour tokens, to validate for contrast during design: ivory `#F7F3E8`, olive `#434833`, amber `#D79B42`, taupe `#A4947B`, and dark text `#25281F`.

The screenshots contain promotional layouts with tilted, overlapping panels. Translate their warmth and depth into practical screens; use orderly layouts during study so long questions and answers remain easy to read. Create Engram's own identity and assets.

Use a responsive layout: compact navigation on iPhone, expanded library and study panes on larger screens. Dark appearance can use deep olive or charcoal with warm light text. Final fonts, palette, icon set, and screen compositions remain design decisions.

## 5. Animation and interaction plan

Motion should clarify what changed and make review feel responsive without slowing repeated study actions.

| Interaction | Proposed motion | Purpose |
| --- | --- | --- |
| Open a deck | Shared card expansion into deck detail | Maintain spatial continuity |
| Reveal an answer | Gentle content reveal or short flip | Make the question-to-answer transition clear |
| Grade a card | Small directional exit and next-card arrival | Confirm the review was recorded |
| Change tabs or filters | Short fade and subtle movement | Explain the new context |
| Update progress | Brief marker movement along a labelled path | Reflect a real recorded change |
| Finish a session | Restrained completion animation | Mark the end of the session |
| Generate cards | Honest processing state with staged progress when known | Show that work is underway |

Initial timing proposal: approximately 120–200 ms for small feedback and 200–350 ms for screen transitions, subject to device testing. Motion must be interruptible; rapid reviewing should never queue long animations. Provide reduced-motion alternatives using immediate changes or fades. Preserve VoiceOver focus, large text, contrast, and touch targets. Never communicate correctness solely through colour or motion.

## 6. Codex and MCP integration concept

The phrase “connect to Codex MCPs” needs a technical discovery step. Two possible directions should be kept distinct:

1. **Expose Engram through an MCP server.** A compatible assistant such as Codex could query learning information and propose study actions through Engram tools.
2. **Let Engram consume external MCP servers.** Engram could act as a client for selected sources or tools, subject to each server's authentication, permissions, and supported deployment.

The proposed first experiment is direction 1 because it directly supports the handover's idea of Engram as a learning memory system. This is an intended integration, not a claim that Engram can inherit Codex's installed connectors, credentials, or session access. Confirm current Codex integration requirements against official documentation before implementation.

Candidate tool contract:

| Tool | Intended behaviour |
| --- | --- |
| `get_due_cards` | Return scoped due cards and counts |
| `get_weak_topics` | Return weak areas with supporting evidence |
| `get_recent_mistakes` | Return selected recent mistakes |
| `get_mastery` | Return estimates, evidence, and uncertainty |
| `search_learning_resources` | Retrieve relevant source passages and references |
| `create_study_session` | Create a session from an explicit scope |
| `create_flashcards` | Create reviewable drafts rather than silently publishing cards |

Example: “What should I study tonight?” → retrieve due workload and weak areas → propose a focused session → create the selected session.

Start the integration experiment with read-only queries. Later writes should be scoped, traceable, and resistant to duplicate retries. Keep credentials in appropriate secure storage and provide disconnect/revoke controls. Uploaded resources are content, never instructions that grant tool access. Do not expose the entire learning library when a narrow query suffices.

## 7. Proposed architecture boundaries

The handover prefers native iOS first, with Swift and SwiftUI as candidate technologies. iPad, macOS, and web are longer-term targets. Final implementation choices require a separate technical validation step.

- **Application layer:** library, review, assessments, tutor, and accessible motion.
- **Local learning store:** cards, resources available offline, review events, drafts, and settings.
- **Scheduling engine:** deterministic due dates and learning transitions, separate from AI generation.
- **Sync service:** queued changes, stable identifiers, conflict handling, and recoverable failures.
- **Resource pipeline:** parsing, source locations, chunking, retrieval, and indexing.
- **AI adapter:** common interface for cloud providers, a user-operated model server, and possible on-device models.
- **Integration boundary:** authenticated, scoped MCP access backed by the same application services.

Core entities: Subject, Deck, Card, Concept, Resource, SourceReference, ReviewEvent, StudySession, Assessment, AssessmentAttempt, Mistake, and MasteryEstimate.

Keep original review events distinct from derived estimates. Do not let AI feedback silently rewrite scheduling history. Investigate a maintained spaced-repetition engine before considering custom scheduling. Anki imports should report exactly which card types, media, tags, and scheduling fields were preserved or could not be mapped.

## 8. Offline, grounding, and learner control

Basic card creation, deck browsing, and review should work without AI or a network connection. Store reviews locally before attempting sync. Cloud-only features should clearly explain when they require connectivity.

Source-grounded generation should retain resource and page/slide references where extraction permits. When sources are insufficient, show the gap. Separate source-supported explanations from additional model knowledge. Let users correct grading and edit generated content.

A future “Never send my resources to cloud AI” setting must be enforced across generation, embeddings, tutoring, and fallback routing. A disconnected local server must not cause an automatic cloud upload against the user's preference.

## 9. Proposed delivery phases

The later first-build brief narrows the initial implementation to the flashcard foundation. AI, MCP, voice, and billing remain later phases; do not start them as part of the first build.

### Phase 0 — Product and design definition

Create representative Today, Library, Review, and Progress designs. Prototype the answer reveal and review transition. Confirm the initial device target, offline scope, scheduling approach, and import needs. Run a small MCP feasibility experiment independently of the main app.

Exit: agreed core flow and a tested technical direction for persistence and scheduling.

### Phase 1 — Reliable study foundation

Deliver manual basic/cloze cards, decks and tags, due reviews, review history, undo, local persistence, and essential accessibility. Establish a portable export or backup path. Assess Anki import early if existing Anki users remain the first audience.

Exit: a learner can complete repeated offline sessions without losing cards or review history.

### Phase 2 — Source-grounded assistance

Add a limited set of resource formats, generated card drafts, source references, and contextual explanations. Add sync if required for the chosen launch scope.

Exit: users can inspect a generated card's supporting material and approve or reject it before study.

### Phase 3 — Understanding and integration

Add cumulative tests, concept links, mistake tracking, and separate evidence for recall versus application. Expand the MCP experiment into scoped learning queries and draft/session creation.

Exit: a multi-concept assessment produces useful, inspectable feedback and external assistant actions remain controllable.

### Phase 4 — Expanded learning platform

Explore adaptive tutoring, voice/oral examination, hybrid AI routing, local servers, semantic search, richer Anki migration, knowledge graphs, and additional platforms.

Exit criteria should be defined per feature before implementation. These are roadmap candidates, not launch promises.

## 10. Validation and open decisions

Validate outcomes as well as polish: reliable review persistence, understandable next-study recommendations, source citation accuracy, usefulness of generated questions, and delayed recall/application performance. Evaluate the educational benefit of cumulative tests instead of assuming it from engagement metrics.

Before development, resolve:

- Is iPhone the first usable release, or is a desktop/web prototype needed first?
- Which parts of existing Anki libraries must import in the first release?
- Which scheduling implementation and retention controls will be used?
- Is cross-device sync required at launch?
- Does the first Codex integration only query Engram, or also create drafts and sessions?
- Which source formats and AI provider are supported initially?
- How will grading uncertainty and contested AI feedback affect mastery estimates?
- What exact prices, usage allowances, and provider cost limits implement the cost-based pricing model in section 11?

These decisions do not prevent this planning document from serving as the project starting point.

---

## 11. Updated product direction — voice, AI access, and pricing

User-requested addition, 3 September 2026. These requirements guide later phases. The first implementation remains the Anki-style foundation described in `ENGRAM-FIRST-BUILD.md`; voice, AI, and billing are not added to that first-build scope.

### Cost-based access model

The guiding principle is that features which do not create ongoing service costs for Engram should be free. Features consuming services paid for by Engram should have recurring or usage-based payment that covers those costs. The explicit exception requested by the user is a one-time paid unlock for easy bring-your-own-key AI integration.

| Offering | Intended access | Cost boundary |
| --- | --- | --- |
| Core flashcards, local storage, scheduling, manual editing, local backup | Free | Runs locally without Engram-funded per-use services |
| Supported on-device transcription and system speech playback | Free | No Engram-funded cloud transcription or voice calls |
| Other local-only features with no ongoing service expense | Free by default | Assess actual dependencies before promising availability |
| Managed AI assistant/tutor | Paid recurring allowance or usage credits | Engram pays for model usage and supporting infrastructure |
| Premium hosted natural-sounding voice | Paid allowance or usage credits | Engram pays the speech provider |
| Hosted resource processing, retrieval/storage, or sync | Paid where these incur ongoing costs | Include compute, storage, and transfer in costing |
| Bring your own AI API keys | One-time integration unlock | User pays their provider directly for usage |

Exact prices are undecided. Avoid an unlimited lifetime promise for services that incur recurring costs. Define included usage, visible balances, and clear behaviour when an allowance runs out; never create surprise paid overages. General maintenance and distribution costs still exist even when a feature has no per-use cloud bill.

The one-time key unlock buys configuration convenience and supported integrations, not lifetime model credits. If a BYOK feature also needs Engram-hosted storage or processing, disclose and separate that expense rather than implying the user's model key pays for everything.

### Managed AI for people who want no setup

Offer an integrated assistant with simple onboarding: select source materials and start learning, without configuring a model server or obtaining API keys. It should support the later source-grounded card generation, explanations, answer marking, and tutoring roadmap. Show what data is sent and which usage allowance applies.

Use provider adapters so managed AI and user-funded AI can support the same learning workflow. Apply the same source-grounding and abstention requirements to every provider; BYOK must not weaken the reliability rules.

### Easy bring-your-own-key setup

Provide a guided provider selector, secure key entry, connection test, model selection, and understandable error messages. Clearly explain that provider usage is charged separately. Let users replace or remove keys and select which supported tasks use each provider.

Store keys in platform-appropriate secure storage. Never put keys in logs, analytics, exported decks, or source code. Validate each provider's suitability for direct client access; do not assume an arbitrary browser app can safely use every provider's secret key. If a relay is necessary, document its security and operating costs before promising a one-time-only service.

Do not silently fall back from a user's key or local model to an Engram-billed service, or from a private local workflow to cloud processing.

### Speech input and speech output are separate

Speech-to-text captures the learner's answer. Text-to-speech reads questions and feedback aloud. Neither component independently determines whether an answer is correct; marking requires the source-grounded assessment layer.

Apple's SpeechAnalyzer/SpeechTranscriber is a candidate for native on-device speech input. Apple introduced this API in iOS 26 and describes local processing, downloadable model assets, and hardware/language requirements. On-device processing avoids an Engram-funded per-minute cloud transcription service; this is not a promise that every device or language is supported. Check runtime availability and downloaded assets. Native APIs are not automatically available to the planned web prototype. Source: [Apple SpeechAnalyzer overview](https://developer.apple.com/videos/play/wwdc2025/277/).

For basic spoken output, evaluate the platform's speech synthesis through [Apple AVSpeechSynthesizer](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer). Offer a paid hosted voice option later if its naturalness and latency justify the recurring expense. No premium voice provider has been selected.

The user mentioned “whisperflow,” possibly meaning Wispr Flow. Confirm the intended product before committing to it. [Wispr Flow's API](https://api-docs.wisprflow.ai/introduction) is a speech-to-text/dictation service with editing capabilities, not a text-to-speech voice for the bot. For assessment, avoid a dictation service rewriting the substance of a learner's response.

Reliability is an acceptance criterion, not an assumed property of any vendor. Test Australian English, other target accents, technical and medical vocabulary, abbreviations, numbers, negation, quiet speech, car/background noise, and microphone changes. Measure meaning-changing transcription errors and their effect on marking. Do not automatically interpret recognition errors as knowledge gaps.

### Hands-free spoken study

Support a future audio-first session for walking, commuting, and other situations where users cannot conveniently type. The user specifically suggested driving. Design that use case without required screen interaction, with easy voice pause/stop and no time pressure; hands-free study still creates cognitive distraction and should not be presented as inherently safe for driving.

Intended flow:

1. Select sources and the study session before starting.
2. Read a short, source-supported question aloud.
3. Capture the spoken answer and produce a finalized transcript.
4. If the transcript is ambiguous or meaning-critical wording is uncertain, ask for repetition or confirmation.
5. Compare the answer against a rubric supported by the selected documents.
6. Speak concise feedback or explicitly say that the answer cannot be verified.
7. Store the result and source references for later inspection.

Include voice commands such as pause, stop, repeat, skip, and repeat my answer. Handle calls, audio interruptions, silence, disconnected headphones, and network loss without losing completed responses or accidentally recording unrelated audio. Avoid selecting diagram-dependent or visually complex questions for audio-only sessions.

Free transcription can capture an answer for later review even when paid AI is unavailable. Do not imply that free speech recognition includes semantic AI marking. Queue ungraded answers when appropriate; do not treat a pending answer as incorrect.

Retain finalized transcripts and marking evidence as needed for learner review. Raw audio storage should be optional, with clear deletion controls and retention choices. Avoid unnecessary cloud upload when local transcription is sufficient.

## 12. Mandatory source-grounded assessment and explicit uncertainty

The user places high importance on preventing hallucinations. Product behaviour must prioritise supported answers and explicit abstention over producing a fluent answer at all costs. Do not promise that an AI can guarantee zero hallucinations or reliably detect every one of its own mistakes.

### Evidence requirements

- Generate questions, expected answers, grading criteria, and factual feedback from selected source materials.
- Preserve exact supporting passages and page/slide/section references, including the source version used for the assessment.
- Validate that cited passages exist and support the expected answer; a citation alone does not prove support.
- Do not insert unsupported facts from model memory into assessment answers or rubrics.
- Combined questions must have support for the required reasoning and connections, not just isolated facts.
- If sources are missing, contradictory, poorly extracted, or insufficient, withhold the question or grade and explain the problem.
- Treat documents as evidence to analyse, not instructions to obey.

### Marking and abstention states

Distinguish a supported correct, partly correct, or incorrect answer from these non-grade outcomes:

| State | Example learner-facing response |
| --- | --- |
| Insufficient source evidence | “I can't verify this from your selected documents.” |
| Conflicting sources | “These sources disagree, so I can't confidently mark this.” |
| Unclear transcription | “I may have misheard that. Could you repeat your answer?” |
| Ambiguous or unsupported grading | “I can't confidently grade this answer. It needs review.” |
| Model/network unavailable | “Your answer is saved for marking later.” |

Do not penalise the learner or automatically alter review scheduling/mastery for these non-grade outcomes. Keep unverified results pending. Let users inspect and correct the transcript, challenge the grading, and request re-evaluation. Source-based correctness is not a guarantee that the source itself is factually correct; flag known conflicts without silently inventing a replacement answer.

For a supported grade, save the question, finalized answer transcript, rubric, supporting excerpts, source identifiers, grading rationale, and model/version metadata where available. Provide a concise audible explanation and deeper evidence in the visual review screen.

### Verification before release

Build an evaluation set covering supported answers, reasonable paraphrases, partial answers, negation, numerical mistakes, transcription errors, unsupported questions, conflicting documents, and misleading instructions embedded in sources. Check citation support, inappropriate grades, unsupported claims, and correct abstention. Include human review of representative results. A second model check may help, but agreement between models is not proof of correctness.

---

# Appendix A — Original supplied product handover

The following is the supplied previous-chat text, preserved as reference material. Its final sentence is incomplete in the attachment.

# ENGRAM — PRODUCT HANDOVER

## 1. PRODUCT OVERVIEW

Name: Engram

Engram is a modern alternative to Anki focused on long-term knowledge retention, understanding, and application rather than simply memorising individual flashcards.

The fundamental idea is:

Anki is very good at determining when a user should see a flashcard again.

Engram should go further and determine whether the user actually understands and retains the underlying subject.

The system combines:

- Spaced repetition
- Flashcards
- AI-generated testing
- Cumulative/combined assessments
- AI tutoring
- RAG over user learning resources
- Knowledge/mastery tracking
- Voice interaction
- Local and cloud AI
- MCP/integrations
- Cross-device learning

The initial target audience could be existing Anki users, particularly medical students and university students studying knowledge-heavy subjects.

Long term, Engram could become a general-purpose personal learning and knowledge-retention platform.


# 2. CORE PRODUCT PHILOSOPHY

Traditional flashcard systems largely operate like:

Card
→ User answers
→ User rates difficulty
→ Algorithm schedules card again

Engram should instead develop toward:

Learn
→ Recall
→ Assess
→ Apply
→ Identify weaknesses
→ Adapt learning
→ Retest
→ Verify long-term retention

There should therefore be TWO levels of learning.

### Micro-retention

Traditional spaced repetition.

Used for:

- Definitions
- Formulas
- Terminology
- Facts
- Processes
- Small concepts

The system determines when individual knowledge should be reviewed.

### Macro-understanding

Engram periodically combines previously learned information into larger assessments.

This determines whether users can:

- connect concepts;
- apply knowledge;
- solve unfamiliar problems;
- explain concepts;
- transfer knowledge to different contexts.

This is one of the major differentiators from Anki.


# 3. FLASHCARDS

Engram should retain the useful parts of Anki rather than abandoning flashcards.

Possible card types:

- Basic question/answer
- Reverse cards
- Cloze deletion
- Image-based cards
- Multiple choice
- Short answer
- Calculation/problem-solving
- AI-generated questions
- Potentially diagram/image occlusion

Cards should belong to:

- decks;
- subjects;
- topics;
- subtopics;
- resources;
- potentially concepts rather than only folders.

Users should be able to create cards manually or have AI assist with their creation.


# 4. SPACED REPETITION

Engram needs a proper spaced-repetition engine.

The scheduling system should manage:

- new material;
- learning;
- review;
- forgotten material;
- difficult material;
- mature knowledge.

Users should have more control over testing and scheduling than they currently get from traditional flashcard applications.

The system should optimise for LONG-TERM retention rather than simply preparing for the next examination.

Possible tracked information includes:

- last reviewed;
- next review;
- recall history;
- difficulty;
- confidence;
- response time;
- repeated mistakes;
- mastery;
- stability/retention probability.

The scheduling engine should ultimately use more information than simply:

Again / Hard / Good / Easy.


# 5. COMBINED REVIEW SESSIONS

This was one of the most important original Engram ideas.

Traditional spaced repetition repeatedly tests individual cards.

Engram should periodically create COMBINED TESTS from information the learner has already studied.

Example:

A medical student learns 100 individual cardiovascular cards.

Instead of indefinitely testing those 100 cards independently, Engram could periodically generate:

- clinical scenarios;
- integrated questions;
- explanations;
- multiple-step questions;
- cumulative quizzes.

These assessments require knowledge from several cards simultaneously.

This determines whether the learner can actually USE the information.

Example:

Individual card:

"What effect does receptor X have?"

Combined assessment:

A patient presents with symptoms A, B and C. Based on the underlying physiology and pharmacology, explain what is occurring and which receptor/pathway is involved.

The assessment could draw on five or ten pieces of previously learned information.

This creates a hierarchy:

Facts
→ Concepts
→ Topics
→ Integrated understanding.


# 6. TEST SESSION SYSTEM

Users should have substantially more control over testing than in Anki.

Potential options:

Test me on:

- today's due material;
- one deck;
- one subject;
- several subjects;
- everything learned this week;
- everything learned this month;
- weak topics;
- material from one lecture;
- material from one uploaded resource;
- random previously learned material;
- material likely to be forgotten soon;
- cumulative knowledge.

Potential assessment modes:

- Flashcard review
- Quick quiz
- Exam mode
- Cumulative test
- Application test
- Oral examination
- AI tutor session
- Weakness-focused session

A user could therefore say:

"Test me on everything I've learned about renal physiology this month."

Engram generates an appropriate assessment rather than simply displaying every renal flashcard.


# 7. KNOWLEDGE / MASTERY MODEL

Long term, Engram should understand knowledge at a CONCEPT level rather than treating every card as completely independent.

For example:

Card 1 ─┐
Card 2 ─┼→ Concept A
Card 3 ─┘

Concept A + Concept B
        ↓
      Topic X

This could allow Engram to track:

- card mastery;
- concept mastery;
- topic mastery;
- subject mastery.

A user could therefore see:

Cardiology — 81%
Renal — 64%
Respiratory — 89%

And within Renal:

Filtration — Strong
Electrolytes — Moderate
Acid/base — Weak

This could eventually become a knowledge/mastery graph.


# 8. AI-GENERATED FLASHCARDS

Users should be able to upload resources and generate cards.

Potential sources:

- Lecture slides
- PDFs
- Notes
- Textbooks
- Documents
- Existing flashcards
- Potentially lecture transcripts

Example workflow:

Upload lecture
→ Engram extracts concepts
→ AI proposes flashcards
→ User reviews cards
→ Approved cards enter spaced repetition

IMPORTANT:

AI-generated cards should ideally remain grounded in the supplied source rather than freely generated from model knowledge.

The user should remain able to edit and approve generated content.


# 9. RAG

Retrieval-Augmented Generation is a major part of the proposed architecture.

Users provide their learning resources.

Resources are:

Ingested
→ Parsed
→ Chunked
→ Embedded
→ Stored/indexed

When AI is asked a question:

User request
→ Search relevant learning resources
→ Retrieve supporting information
→ Provide retrieved context to LLM
→ Generate answer/question/explanation

This allows Engram to generate content grounded in what the learner is actually studying.

This is particularly important for areas such as medicine where hallucinated information could be problematic.


# 10. SOURCE-GROUNDED AI

Ideally AI responses should distinguish between:

- information supported by uploaded resources;
- general model knowledge.

Where possible, generated material should provide references back to the source.

For example:

Explanation

[Lecture 7, Slide 23]

This allows users to verify AI-generated educational content.

Potential future feature:

Click the citation and Engram opens the exact page/slide where the information came from.


# 11. AI TUTOR

Engram should eventually contain an AI tutor that understands:

- what the learner has studied;
- their flashcards;
- uploaded resources;
- review history;
- weak concepts;
- mastery.

Users could ask:

"Explain this card."

"Why did I get this wrong?"

"Explain this more simply."

"Give me another example."

"Test me on this concept."

"Show me what I'm misunderstanding."

"Compare these two concepts."

The tutor should ideally use RAG over the learner's resources before responding.


# 12. ADAPTIVE AI TESTING

The AI tutor should be able to dynamically change questions.

Example:

AI asks Question 1.

User answers incorrectly.

Instead of simply saying "wrong", Engram determines what misconception may have caused the error.

It asks Question 2 targeting that misconception.

If the learner continues struggling, it can:

- simplify the question;
- explain the prerequisite;
- provide an example;
- test the prerequisite;
- return to the original concept.

This produces adaptive tutoring rather than static flashcard review.


# 13. VOICE LEARNING

Voice interaction was another potential major feature.

A learner could start a voice session and say:

"Quiz me on cardiology."

Engram could conduct an oral examination.

AI:
"What is cardiac output?"

User answers verbally.

AI evaluates the response and asks a follow-up.

This could become particularly useful for:

- walking;
- commuting;
- oral exams;
- medical learning;
- interview preparation;
- language learning.

The voice system should integrate with the same mastery system.

If a learner demonstrates strong knowledge verbally, that should potentially influence their learning record.


# 14. LEARNING FEEDBACK LOOP

The ideal Engram loop is:

User studies
      ↓
Spaced repetition
      ↓
Combined assessment
      ↓
AI evaluates performance
      ↓
Weak concepts identified
      ↓
Review schedule adjusted
      ↓
Targeted questions generated
      ↓
Learner improves
      ↓
Cumulative assessment later verifies retention

This feedback loop is potentially the core intelligence of Engram.


# 15. AI-GENERATED QUESTIONS

Engram could generate questions based on:

- weak concepts;
- existing flashcards;
- uploaded resources;
- previous mistakes;
- upcoming reviews;
- related concepts.

Difficulty could adapt.

Example progression:

Level 1:
Recall

Level 2:
Explain

Level 3:
Compare

Level 4:
Apply

Level 5:
Integrate several concepts

The same knowledge can therefore be tested in multiple ways.

This helps prevent users from simply memorising the wording of a flashcard.


# 16. MISTAKE TRACKING

Engram should remember what users get wrong.

Potential data:

- incorrect answer;
- expected answer;
- concept;
- date;
- confidence;
- response time;
- type of error.

Repeated mistakes could become identifiable patterns.

Example:

The user repeatedly confuses:

Sympathetic vs parasympathetic pathways.

Engram identifies this and generates a targeted comparison session.

This information could also affect future review scheduling.


# 17. CONFIDENCE

Potential future enhancement:

Ask users how confident they are before/after answering.

Example:

Correct + high confidence
→ strong knowledge

Correct + low confidence
→ uncertain knowledge

Incorrect + low confidence
→ normal learning gap

Incorrect + high confidence
→ misconception

The last category is particularly valuable because confident incorrect knowledge may require more intervention.


# 18. EXISTING ANKI USERS

Existing Anki users should ideally not have to abandon years of work.

Engram should eventually support importing:

- decks;
- cards;
- tags;
- scheduling information where possible;
- media.

Anki migration could be important for adoption.

The value proposition should therefore be:

"Keep your flashcards, but gain a more intelligent learning system around them."

Not:

"Throw away Anki and start again."


# 19. TARGET USERS

Initial strongest audience:

- Medical students
- Existing Anki power users

Other potential users:

- University students
- Engineering students
- Law students
- Language learners
- Certification students
- High-school students
- Professionals maintaining technical knowledge

Potential certification examples:

- AWS
- Azure
- Cisco
- Medical examinations
- Professional accreditation

The underlying system should remain domain-independent.


# 20. MEDICAL USE CASE

Medicine was discussed as a particularly compelling initial use case because:

- medical students already heavily use Anki;
- there is enormous material volume;
- long-term retention matters;
- concepts need to be integrated;
- students already have lecture/textbook resources;
- users frequently need cumulative testing.

However, medical AI also increases the importance of:

- grounding;
- citations;
- reliable retrieval;
- source verification;
- hallucination controls.

Medical-specific models such as MedGemma were considered as possible components, particularly for local inference.

However, RAG and source grounding remain important even when using a medical-specific model.


# 21. LOCAL AI

A local AI mode was considered.

Potential architecture:

Engram
   ↓
AI abstraction layer
   ↓
┌────────────────┬─────────────────┐
│ Local model    │ Cloud model     │
│                │                 │
│ User hardware  │ API/provider    │
└────────────────┴─────────────────┘

Potential benefits:

- privacy;
- offline use;
- potentially lower long-term inference costs;
- control over user data.

Potential users with powerful PCs or home servers could run larger models themselves.


# 22. LOCAL LLM SERVER

One idea was allowing Engram to connect to a model running on another machine.

Example:

iPhone
   ↓
Engram
   ↓
Home network / secure connection
   ↓
User's PC/server
   ↓
Local LLM

This would allow the mobile application to access a much larger model than could realistically run directly on the phone.

Potential hardware:

NVIDIA GPU-equipped PC/server.

Considerations discussed:

- GPU memory;
- model size;
- inference speed;
- cold starts;
- power consumption;
- server availability.


# 23. ON-DEVICE AI

Smaller models could potentially run directly on the device for certain tasks.

Potential uses:

- basic card generation;
- classification;
- simple explanations;
- embeddings;
- offline assistance.

Large reasoning/generation tasks could still use:

- local server;
- cloud model.

Engram does not need one model to perform every task.


# 24. CLOUD AI

For ordinary users, cloud LLMs are likely the easiest option.

Potential architecture:

Engram
→ Engram backend
→ AI provider

Possible providers could include hosted commercial APIs or cloud-hosted open models.

Cloud models provide:

- better performance;
- no local hardware requirement;
- simpler setup.

Potential disadvantages:

- inference cost;
- privacy;
- internet requirement.

Engram could potentially support several providers rather than becoming dependent on one.


# 25. HYBRID AI

The ideal long-term design may therefore be hybrid.

Small/local tasks:
→ on-device model

Private/local generation:
→ user's PC/server

High-quality reasoning:
→ cloud model

The AI layer should abstract the model provider so Engram features are not tightly coupled to one LLM.


# 26. MCP

MCP support was another feature discussed.

Engram could expose a user's learning information to compatible AI systems through MCP.

Potential tools:

get_due_cards()

get_weak_topics()

get_recent_mistakes()

get_mastery()

create_study_session()

search_learning_resources()

create_flashcards()

External AI assistants could therefore interact with Engram.

Example:

User:
"What should I study tonight?"

AI:
Queries Engram.

Engram reports:

Renal physiology: weak
15 overdue cards
Cardiovascular: strong
Pharmacology assessment tomorrow

AI then creates an appropriate study plan.


# 27. ENGRAM AS A LEARNING MEMORY SYSTEM

This leads to the larger long-term idea.

Engram could evolve beyond being a flashcard application.

It could become the structured memory system behind a person's learning.

It knows:

- what the user has learned;
- when they learned it;
- what they remember;
- what they are forgetting;
- what they misunderstand;
- what resources they learned it from;
- what concepts are connected.

An external AI assistant could then interact with this information.

This is considerably more ambitious than "AI Anki."


# 28. PLATFORM STRATEGY

Initial focus discussed:

iOS native application.

Longer-term:

- iPhone
- iPad
- macOS
- Web

Native Apple applications were preferred where practical rather than simply creating a website wrapper.

Possible Apple stack:

Swift
SwiftUI

The web application could use a modern web framework.

The backend could provide:

- authentication;
- synchronisation;
- AI orchestration;
- RAG;
- resource processing;
- model routing.


# 29. OFFLINE-FIRST / LOCAL DATA

Because flashcards are frequently reviewed while travelling or commuting, basic learning functionality should ideally work offline.

Users should still be able to:

- view cards;
- complete reviews;
- browse decks;
- potentially access downloaded resources.

Changes synchronise when connectivity returns.

Cloud AI features may naturally require internet unless a local/on-device model is configured.


# 30. PRIVACY

Privacy could become a differentiating feature.

Potential privacy options:

Cloud AI

Local AI

Potentially:

"Never send my resources to cloud AI."

Users could choose their desired level of privacy.

This is particularly useful for:

- proprietary workplace learning;
- research;
- private notes;
- potentially sensitive educational resources.


# 31. DASHBOARD

Potential dashboard:

Today's Reviews
42 cards

Retention
91%

Weakest Topics
1. Acid/Base
2. Renal Pharmacology
3. ECG Interpretation

Upcoming Reviews

Recent Mistakes

Mastery by Subject

Recommended Session

Engram could proactively recommend:

"You've repeatedly struggled with acid-base compensation. Take a 10-minute targeted session."


# 32. ANALYTICS

Potential analytics:

- retention over time;
- cards learned;
- reviews completed;
- average response time;
- mastery;
- weak topics;
- strongest topics;
- forgotten concepts;
- review workload;
- study consistency.

More advanced analytics could include:

- predicted retention;
- knowledge decay;
- misconception frequency;
- transfer/application performance.

The important principle is that analytics should help the learner make decisions rather than simply provide vanity statistics.


# 33. SEARCH

Users should eventually be able to search across:

- cards;
- decks;
- notes;
- uploaded resources;
- concepts;
- previous AI explanations.

Semantic search could allow:

"Find everything I've learned about insulin resistance."

rather than requiring exact keywords.


# 34. POTENTIAL KNOWLEDGE GRAPH

A future feature could represent relationships between concepts.

Example:

Cardiac Output
├── Heart Rate
├── Stroke Volume
│   ├── Preload
│   ├── Afterload
│   └── Contractility
└── Blood Pressure

Engram could use this graph to determine prerequisite relationships.

If a learner struggles with Cardiac Output because they don't understand Stroke Volume, the system could identify the underlying prerequisite.

This could significantly improve adaptive testing.


# 35. USER-CONTROLLED AI

AI should assist rather than silently rewrite the learner's knowledge base.

Where appropriate:

AI proposes
→ User reviews
→ User accepts

Particularly for:

- generated cards;
- major changes;
- generated summaries;
- imported material.

Users should be able to edit AI-generated content.


# 36. POSSIBLE STUDY WORKFLOW

Example:

1. User uploads Lecture 6.

2. Engram identifies major concepts.

3. AI proposes flashcards.

4. User approves/edit cards.

5. Cards enter spaced repetition.

6. User reviews normally.

7. Engram identifies weak concepts.

8. Several days later, Engram creates a cumulative test.

9. User performs well on recall questions but poorly on application questions.

10. Engram records that the user remembers the facts but has weak application
