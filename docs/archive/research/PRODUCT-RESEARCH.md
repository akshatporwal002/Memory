# Memory Product Research: Anki, RemNote, and the Learning-System Opportunity

> Archived on 5 October 2026 from main `381c917`. This is historical context, not current implementation guidance. Outstanding work is tracked in [the backlog](../../BACKLOG.md); newer requirements take precedence.

*Research date: 26 August 2026 | Product stage: pre-discovery | Evidence confidence: medium*

## Decision in one sentence

Memory should not launch as another flashcard app or one-click AI card generator. It should launch for medical students as an **Anki-compatible, source-grounded mastery planner** that helps learners create trustworthy retrieval tasks, forecast and control review load, and progress from recall to application without discarding their existing decks.

## Executive summary

The category is crowded at every obvious layer:

- Anki is highly flexible, handles very large decks, has mature cross-platform clients, supports FSRS, and has an add-on and shared-deck ecosystem. Its weakness is not capability; it is the expertise and maintenance required to use that capability well. [Anki product page](https://apps.ankiweb.net/), [Anki manual](https://docs.ankiweb.net/getting-started.html), [FSRS FAQ](https://faqs.ankiweb.net/what-spaced-repetition-algorithm.html)
- RemNote already combines notes, PDFs, linked sources, image occlusion, AI-generated cards, tutoring, exam prioritization, offline access, and spaced repetition. A clone with a cleaner interface would not be enough. [RemNote Reader](https://help.remnote.com/en/articles/6690975-learning-from-pdfs-and-files-with-the-remnote-reader), [RemNote spaced-repetition guide](https://help.remnote.com/en/articles/6022755-getting-started-with-spaced-repetition), [RemNote pricing](https://www.remnote.com/pricing)
- Quizlet and Knowt make creation, shared content, test modes, and short-horizon studying easy. Mochi offers a polished local-first, Markdown-oriented alternative, while Brainscape combines a simpler confidence-based system with collaboration and curated content. [Quizlet study modes](https://help.quizlet.com/hc/en-us/articles/360030841732-Studying-on-Quizlet), [Knowt flashcards](https://knowt.com/flashcards), [Mochi](https://mochi.cards/), [Brainscape](https://www.brainscape.com/)

The underserved problem is orchestration and judgment: **What is worth learning, how should it be tested, what can fit before the exam, and when is the learner genuinely ready?** Current products are good at storing cards, scheduling isolated items, or generating more material. They are weaker at preventing low-quality cards, explaining workload consequences, linking recall to application, and helping a learner decide what *not* to study.

Medical students are the strongest launch segment. Their pain is frequent and high stakes, their existing spaced-repetition behavior is proven, and their workflows expose the full problem: lecture materials, question banks, shared decks, image-heavy content, board resources, and hundreds of daily reviews. However, AnKing/AnkiHub is a formidable ecosystem and switching barrier: the AnKing Step Deck claims more than 30,000 cards and over 100,000 medical-student users, with collaborative updates and school-specific tags. [AnKing Step Deck](https://www.ankihub.net/step-deck)

The correct entry strategy is therefore **companion first, replacement later if earned**.

## Research question and method

### Falsifiable question

Can Memory reduce preparation and review-management cost for serious learners without reducing card accuracy, durable recall, or the beneficial effort involved in generating knowledge?

### Evidence used

- Current official product pages, manuals, help centers, pricing, and app listings
- Peer-reviewed and preprint learning-science research
- Medical-student usage studies
- Recent Reddit, product-forum, and App Store reports as directional qualitative evidence
- Developer tools and workflows as adoption signals

Community posts and reviews are self-selected anecdotes, not prevalence estimates. Competitor marketing establishes product capability and positioning, not independent effectiveness. Pricing and features are a point-in-time snapshot and should be rechecked before public use.

## Competitive reality

| Product | What it is best at | Product reality | Structural opening for Memory | Switching barrier |
|---|---|---|---|---|
| **Anki** | Maximum control, mature scheduling, large decks, extensibility, ownership | Free desktop and web sync; official iOS app is a US$24.99 one-time purchase; supports media, scientific markup, custom templates, add-ons, shared decks, and FSRS. [Official site](https://apps.ankiweb.net/), [App Store](https://apps.apple.com/us/app/ankimobile-flashcards/id373493387) | The novice must understand notes, cards, note types, templates, decks, tags, scheduler choices, and sync behavior before feeling in control. Capture and source context remain external. | Very high for established users: review history, custom templates, add-ons, tags, and shared-deck workflows |
| **AnKing + AnkiHub** | Medical-school content ecosystem and collaborative maintenance | Updated medical decks, school-specific tags, suggestions/moderation, and direct updates into Anki; plans start around US$5-6/month depending on offer. [AnkiHub](https://courses.ankihub.net/main-lp), [AnKing](https://www.theanking.com/step-deck) | Helps maintain content, but learners still need to align the large corpus to local lectures, personal misses, available time, and application practice. | Extremely high in medicine because peers, resources, and tutorials assume this ecosystem |
| **RemNote** | Integrated source, notes, cards, and review workflow | Notes, PDF/web annotation, source pins, AI cards, tutoring, image occlusion, exam prioritization, offline apps, Anki export, and custom schedulers. Pro is listed at US$8/month billed yearly and Pro+AI at US$18/month billed yearly. [Pricing](https://www.remnote.com/pricing), [Reader](https://help.remnote.com/en/articles/6690975-learning-from-pdfs-and-files-with-the-remnote-reader), [Export](https://help.remnote.com/en/articles/7898019-exporting-notes) | Breadth creates performance, complexity, and trust pressure. Current users still report iPad/performance friction, while AI cards still require editing and judgment. [Recent performance discussion](https://www.reddit.com/r/remNote/comments/1qmsbde/remnote_is_a_genius_idea_but_performance_is_a/) | High once the user's knowledge base, annotations, and cards are interlinked |
| **Quizlet** | Low-friction creation, shared sets, familiar study modes, classroom distribution | Flashcards, Learn, Test, games, AI practice tests, study guides, PDF summaries, and tutoring; meaningful usage limits vary by paid tier. [Study modes](https://help.quizlet.com/hc/en-us/articles/360030841732-Studying-on-Quizlet), [AI tools](https://quizlet.com/features/ai-study-tools), [pricing](https://quizlet.com/upgrade) | Long-term mastery, provenance, workload forecasting, and evidence-based self-regulation are not the center of the product promise. | Familiarity, huge content supply, classmates, and teachers |
| **Knowt** | A free/low-friction Quizlet alternative, exam hubs, AI generation | Free creation and study modes, Quizlet import, shared content, spaced repetition, and PDF/PPT/notes-to-cards. It claims 3M+ students and teachers and 320M+ cards. [Product page](https://knowt.com/flashcards), [pricing](https://knowt.com/plans) | Generic AI generation is easy to copy; source trust, card quality, and durable mastery remain open questions. | Existing shared content and school/exam hubs |
| **Mochi** | Modern, local-first SRS for technical and privacy-conscious users | Unlimited offline use without signup; US$5/month Pro adds sync, publishing, dynamic fields, and AI. Markdown, LaTeX, backlinks, and full local backups appeal to power users. [Product page](https://mochi.cards/), [backup/export docs](https://www.mochi.cards/docs/getting-started/backing-up/) | Smaller content/community ecosystem and less guided, exam-oriented orchestration | Moderate; local ownership reduces lock-in |
| **Brainscape** | Simpler confidence-based repetition, collaboration, curated content | Free self-created/shared cards and spaced repetition; Pro is listed from US$7.99/month and adds unlimited AI, certified content, richer media, and privacy controls. [Pricing](https://api.brainscape.com/pricing), [product page](https://www.brainscape.com/) | Proprietary scheduling and confidence ratings simplify operation but do not solve source-to-application workflow or workload trade-offs. | Curated/certified content and group collaboration |

### Competitive conclusion

A product differentiated only by any of the following is a no-go: a nicer Anki UI, FSRS, notes beside cards, PDF-to-flashcards, AI tutoring, image occlusion, exam dates, offline support, Markdown, shared decks, or gamified review. Every one of those is already available.

Memory needs to combine three less-complete capabilities into one coherent promise:

1. **Grounded co-creation:** AI assists the learner's generation process instead of replacing it.
2. **Workload-aware prioritization:** the product makes the future cost of new material visible and keeps the plan feasible.
3. **Mastery beyond recognition:** factual, explanatory, and application tasks are linked to the same concept and evidence source.

## User pain-point catalogue

### 1. Creating good cards is slow, but fully automating it can harm learning

This is the central tension, not merely a missing convenience feature.

- In a 2022 survey of 901 undergraduates at one US university, digital-flashcard users spent more time with premade than self-made cards. Among premade-card users, 81.3% cited easy availability and 70.2% cited lack of time to make their own cards; only 9.4% said premade sets were higher quality and 7.4% said they were more accurate. [College digital-flashcard survey](https://sc-pan.github.io/pdf/ZIP_2022.pdf)
- In six controlled experiments, user-generated cards produced better 48-hour delayed definition performance (estimated *d*=0.45) and application performance (*d*=0.29) than premade cards. [Pan et al., 2022](https://sc-pan.github.io/pdf/PZIZQ_2022.pdf)
- A 2025 medical-school preprint found AI-generated cards saved time for 74% of surveyed users, but the strongest tested generation pipeline still produced roughly one hallucination per 21 cards and reviewers recommended changing 21.5% of cards for information density. It did not produce a statistically significant exam-score improvement in the two studied blocks. [Medical AI flashcard preprint](https://www.medrxiv.org/content/10.1101/2025.05.13.25327518v1)
- A 2026 multi-university Jordanian medical-student study found card creation was the most frequently cited time-consuming Anki activity; less frequent users also struggled more with organization and review burden. The convenience sample and self-reported outcomes limit generalization. [BMC Medical Education](https://link.springer.com/article/10.1186/s12909-026-09040-x)

**Opportunity:** replace “generate 100 cards” with a short, interactive card workshop. Memory identifies candidate concepts and source passages, asks the learner to explain or choose the test angle, drafts an atomic card, and verifies every answer against the source. The user retains generative effort while avoiding formatting and extraction work.

### 2. Review debt is predictable but feels like an ambush

Spaced repetition converts every new card into future obligations. Anki exposes limits and scheduler controls, but learners must understand the consequences. A 2025 Anki forum response to a beginner estimated that a sustainable daily workload can become roughly 8-10 times the new-card limit; this is informed community guidance, not a controlled result. [Anki beginner settings discussion](https://forums.ankiweb.net/t/i-am-a-beginner-help-me-with-settings/67612)

Medical behavior illustrates the problem:

- In a recent first-year medical-student survey, 67.9% used Anki at least five days per week, yet 75% never or rarely continued daily reviews from completed modules. [Utilization-pattern study](https://pmc.ncbi.nlm.nih.gov/articles/PMC12662189/)
- In a 2026 Saudi cross-sectional study, 73.7% of Anki users selected “requires commitment,” 50.6% “time-consuming,” 29.5% “advanced settings,” and 24.4% “errors in cards” as disadvantages. [Frontiers in Medicine](https://www.frontiersin.org/journals/medicine/articles/10.3389/fmed.2026.1896043/full)
- Recent community posts repeatedly describe hundreds or thousands of due reviews competing with new content and question-bank practice. These are vivid but self-selected examples, not prevalence estimates. [Medical-school Anki community](https://www.reddit.com/r/medicalschoolanki/)

**Opportunity:** show a workload forecast before adding or activating content: expected reviews by day, time required, probability of completing the plan, and the trade-off between retention and workload. Let the user state exam dates and available minutes; Memory should then recommend what to learn, defer, or retire.

### 3. Learners optimize isolated recall while exams and work demand transfer

In the undergraduate survey, vocabulary appeared on 93.9% of respondents' cards, concepts on 70.2%, practice questions on 37.8%, and worked examples on only 8.4%. Only 6.8% reported spacing flashcard use throughout the academic term; most concentrated use in the exam week or the final day or two. [College digital-flashcard survey](https://sc-pan.github.io/pdf/ZIP_2022.pdf)

A medical student who switched from Anki to RemNote described the qualitative version of this problem: isolated facts were available, but short-answer, essay, and clinical application remained difficult. This is one person's report, but it aligns with the low use of worked examples in the larger survey. [Switching report](https://www.reddit.com/r/remNote/comments/1jwe41t)

**Opportunity:** treat a “memory” as a concept with multiple retrieval surfaces:

- atomic recall: definition, relationship, mechanism, threshold
- explanation: free recall or “teach this in 60 seconds”
- discrimination: distinguish confusable concepts
- application: clinical vignette, worked problem, or debugging scenario
- error repair: task generated from a missed practice question or real mistake

The scheduler should decide which surface is useful next, not repeatedly present the same front/back card.

### 4. Students do not reliably regulate their own learning

The same undergraduate survey found only 52.8% always checked the answer after retrieval. It concluded that students often use digital flashcards in ways that only partially reflect evidence-based learning principles and highlighted inaccurate fluency judgments, limited term-long spacing, and low use of higher-level content. The sample was one university during pandemic-era teaching and was dominated by Quizlet users, so it should guide hypotheses rather than define the whole market. [Zung, Imundo & Pan](https://sc-pan.github.io/pdf/ZIP_2022.pdf)

Mental effort itself is also aversive: a 2024 meta-analysis covering 170 studies, 358 tasks, and 4,670 participants found a strong positive association between mental effort and negative affect across varied populations and tasks. [PubMed](https://pubmed.ncbi.nlm.nih.gov/39101924/)

**Opportunity:** design for adherence without pretending effective retrieval is frictionless. Reduce administrative effort, provide short bounded sessions, make progress and stopping rules clear, and use variety where it supports learning. Do not optimize for effortless swiping or vanity streaks.

### 5. Source context and trust are fragile

Anki is intentionally card-centric. RemNote directly addresses this by keeping notes beside documents, linking highlights back to source passages, and attaching source pins to AI-generated cards. [RemNote Reader](https://help.remnote.com/en/articles/6690975-learning-from-pdfs-and-files-with-the-remnote-reader)

This means “show the source” is table stakes, not a durable moat. The remaining opportunity is to make provenance operational:

- flag an answer unsupported by its source
- show when a source or shared deck changed
- detect contradictions across lecture slides, textbook, guideline, and card
- trace a wrong answer to the concept and source passage that should be repaired
- let users audit what AI changed and why

For medicine, Memory must clearly state that it is a study tool, not clinical decision support, and must not silently resolve conflicts between local teaching material and current clinical guidance.

### 6. Reliability and portability are part of the learning experience

Anki's manual documents sync cases that require choosing a local or AnkiWeb copy, and some structural changes force a one-way sync. [Anki sync manual](https://docs.ankiweb.net/syncing.html) RemNote supports offline work and multiple export formats, including Anki, but its complete native export currently excludes images and PDFs; those remain on RemNote's servers. [RemNote offline mode](https://help.remnote.com/en/articles/6752029-offline-mode), [RemNote export](https://help.remnote.com/en/articles/7898019-exporting-notes)

Recent RemNote discussions still report iPad performance and restart friction, although the team says it is actively improving performance. [Performance discussion](https://www.reddit.com/r/remNote/comments/1qmsbde/remnote_is_a_genius_idea_but_performance_is_a/)

**Opportunity:** local-first review, transparent sync status, complete export, automatic versioned backups, and a plain-language recovery flow. For a product holding years of learning history, trust is a core feature rather than infrastructure polish.

### 7. Developers need retrieval connected to practice, not code trivia

Evidence for software engineers is mainly anecdotal and tool-based, so confidence is lower than for students. Developer discussions generally separate declarative knowledge worth remembering from procedural skill that should be practiced by writing code. Existing tools bridge Markdown or VS Code to Anki, but often require Anki plus AnkiConnect and custom conventions. [Anki for VS Code](https://github.com/jasonwilliams/anki), [developer discussion](https://www.reddit.com/r/Anki/comments/hxmcmg)

**Opportunity after the student wedge:** a keyboard-first IDE/browser capture flow that turns repeated lookups, code-review mistakes, incidents, and documentation into “predict, explain, debug, or implement” tasks. Executable snippets and source links to documentation or a commit matter more than decorative syntax highlighting.

## Segment priority

Scores below are product inferences on a 1-5 scale, not measured market facts.

| Segment | Pain severity | Frequency | Existing behavior | Reachable distribution | Willingness-to-pay signal | Overall launch fit |
|---|---:|---:|---:|---:|---:|---:|
| Medical students in content-heavy preclinical/board study | 5 | 5 | 5 | 5 | 4 | **24/25** |
| University students in high-stakes, content-heavy courses | 4 | 4 | 4 | 4 | 3 | **19/25** |
| High-school students preparing for standardized exams | 4 | 3 | 4 | 4 | 2 | **17/25** |
| Software engineers maintaining conceptual/operational knowledge | 3 | 3 | 2 | 2 | 4 | **14/25** |
| General lifelong learners | 2 | 2 | 2 | 2 | 2 | **10/25** |

### Recommended initial customer

A first- or second-year medical student in a lecture-heavy block curriculum who already uses Anki, AnKing, and at least one separate source tool such as a PDF reader, Goodnotes, Notion, or a question bank; regularly accumulates more cards than they can sustainably review; and worries that remembering card wording is not the same as being ready for an exam or clinical vignette.

This is narrower than “students” but still supports a general product architecture. Medicine supplies a strong initial behavior and distribution channel; the product can later generalize the same primitives—source, concept, retrieval task, schedule, evidence—to university, high-school, and engineering workflows.

## Product strategy

### Positioning

> **Memory turns what you need to learn—and the mistakes you make—into a trustworthy daily mastery plan that fits the time you actually have. Keep Anki; Memory makes it sustainable and complete.**

The emotional promise is not “never forget anything.” That sounds absolute and creates anxiety. The promise is: **know what matters, know why it matters, and know what to do today.**

### Memory-model architecture and retention analytics

Memory should support multiple scheduling and memory models, but model choice should be a progressive-control feature rather than a prominent onboarding decision. RemNote already supports custom Anki SM-2 or FSRS schedulers by document, and Anki already lets users configure desired retention, optimize parameters, simulate workload, and inspect stability, difficulty, retrievability, and true retention. A simple algorithm dropdown would therefore add complexity without creating a defensible advantage. [RemNote custom schedulers](https://help.remnote.com/en/articles/6958056-custom-schedulers), [Anki deck options](https://docs.ankiweb.net/deck-options), [Anki statistics](https://docs.ankiweb.net/stats.html)

The stronger product is a **model laboratory with safety rails**:

1. Preserve one canonical, append-only review history independent of the active scheduler.
2. Let scheduling engines consume that history through a versioned adapter interface.
3. Backtest compatible models against the learner's own outcomes before recommending one.
4. Simulate due dates, expected review minutes, predicted retention, and exam readiness before switching.
5. Pin the model and parameter version used for every scheduling decision.
6. Switch prospectively by default; never rewrite existing due dates or review history without an explicit, reversible migration.
7. Keep an automatic backup and one-click rollback whenever a model or target changes.

#### Candidate model families

| Model family | Useful role in Memory | Caveat |
|---|---|---|
| **Anki-compatible FSRS** | Default production scheduler for established Anki users; predicts difficulty, stability, and retrievability and supports a direct desired-retention control | Match the version and semantics of the user's imported ecosystem; model upgrades can materially change due dates |
| **FSRS-7 / recency-weighted variants** | Frontier practical candidate for opt-in evaluation and later production use. The open SRS benchmark currently reports better calibration and discrimination than older FSRS versions on its Anki-derived corpus. [Open SRS benchmark](https://github.com/open-spaced-repetition/srs-benchmark) | The benchmark is community-maintained rather than an independent clinical or educational trial; predictive fit does not automatically prove better learning outcomes |
| **Half-Life Regression (HLR)** | Interpretable option for language-like or feature-rich content; can incorporate item and learner features | Originally trained and evaluated for language learning, so transfer to medicine or engineering must be validated. [Duolingo HLR paper](https://research.duolingo.com/papers/settles.acl16.pdf) |
| **Ebisu-style Bayesian model** | Local-first, uncertainty-aware model that can update an item's recall distribution from relatively little data | Its assumptions are simpler and it benchmarks below recent FSRS variants on Anki review data. [Ebisu](https://github.com/fasiha/ebisu) |
| **ACT-R, DASH, and related cognitive models** | Research and interpretability baselines; potentially useful for concept relationships and richer learning histories | More complex does not mean more accurate for a given user's review data; do not expose until validated in Memory's target tasks |
| **MEMORIZE / optimal-control schedulers** | Inspiration for allocating a fixed study-time budget and optimizing review intensity around deadlines | Research implementation rather than a drop-in card scheduler; assumptions and operational constraints require careful translation. [PNAS paper](https://pmc.ncbi.nlm.nih.gov/articles/PMC6410796/) |
| **Neural sequence models** | Offline benchmark and future research candidate for predicting recall from richer histories and answer time | Current open benchmarks show strong prediction, but these models are data-hungry, opaque, expensive, and do not by themselves define a safe scheduling policy |

The latest proprietary SuperMemo algorithms should not be promised as supported unless they can be legally licensed and independently integrated. “Frontier” should mean an open or licensed model that Memory can reproduce, calibrate, version, explain, and roll back—not merely the highest number in a benchmark.

#### Customization levels

- **Routine learner:** chooses an outcome profile—Balanced, Lighter Workload, High Retention, or Exam Date—and sees the projected minutes and trade-offs. The model is automatic.
- **Advanced learner:** chooses a scheduler per course or deck, sets target retention and daily limits, and previews the impact before applying it.
- **Research/developer mode:** can install a signed model adapter, run a shadow backtest, and inspect calibration data. Experimental models cannot change live schedules until they pass minimum-data and safety checks.

Avoid arbitrary per-card model selection. Assign models at a coherent course, deck, or content-type level so forecasts and comparisons remain understandable.

#### Retention and model statistics

Memory should distinguish estimates from observations and show sample size wherever possible:

- **Observed retention:** first review of the day passed versus failed, over 7, 30, and 90 days
- **Predicted retention:** current probability of recall from the active model
- **Calibration:** whether cards predicted at 80%, 90%, or 95% recall are actually remembered at those rates; include calibration error or log loss in an advanced view
- **Memory state:** stability, difficulty, retrievability, and uncertainty where supported
- **Workload:** reviews and minutes due by day, new-card cost, overdue debt, and projected peak load
- **Efficiency:** review time per retained item and comparisons with the user's prior model or profile
- **Exam readiness:** objective coverage, predicted recall on the exam date, and performance on unseen application tasks
- **Model provenance:** scheduler name, version, parameters, last optimization date, amount of training history, and whether the model is still in a cold-start state

These are probabilistic estimates, not promises. Self-ratings are noisy, a high card-recall rate is not equivalent to exam or real-world performance, and narrow confidence intervals should not be shown when the learner has little history.

### Ten-star version

Memory understands the learner's syllabus, objectives, source material, current cards, exam dates, available study time, and practice-question mistakes. It maps them to concepts, identifies missing or weak coverage, co-creates source-backed retrieval tasks, forecasts workload, and schedules a balanced mix of recall and application. Every recommendation is explainable, every item is editable, the complete data set is portable, and the learner can see when a topic is likely ready.

### MVP thesis

Memory can win its first users if, within ten minutes of importing an Anki deck and one lecture, it provides a useful answer to all three questions:

1. What in this lecture is not adequately covered by my current cards?
2. What can I realistically learn before the exam given my available time?
3. Which concepts need recall, explanation, or application practice next?

### Companion-first user journey

1. Import an `.apkg` deck or connect a local Anki collection; preserve tags, cloze cards, media, and review history where technically possible.
2. Upload one lecture/PDF and optional learning objectives; enter exam date and daily time budget.
3. Memory maps existing cards to source concepts and shows coverage, duplicates, ambiguous prompts, unsupported answers, and forecast review cost.
4. The learner accepts, edits, or rejects a small set of suggested retrieval tasks. Suggestions cite exact source locations.
5. Memory creates a feasible daily plan and explains trade-offs: adding, deferring, suspending, or lowering target retention.
6. The learner reviews in Anki or Memory. Misses and uncertainty update the plan and can create application or error-repair tasks.

### MVP scope

Build:

- lossless-enough Anki import and export for the medical workflows under test
- a scheduler-neutral, append-only review event format and versioned model-adapter contract
- one Anki-compatible FSRS production adapter plus SM-2 import/continuity support
- PDF/PPT/text ingestion with page/slide-level provenance
- concept and learning-objective map
- interactive, source-grounded card creation with duplicate, ambiguity, density, and unsupported-claim checks
- exam date, daily time budget, review-load forecast, and clear prioritization controls
- three task types: atomic recall, free explanation, and case/application question
- local/offline review queue, visible sync status, backups, and complete export
- basic study evidence: observed versus predicted retention, completion, answer quality, delayed recall, and application performance

Defer:

- a full Notion/RemNote-class note editor
- a public deck marketplace
- open-ended generic AI chat
- social feeds, avatars, streak economies, and competitive leaderboards
- a proprietary replacement for FSRS
- live collaboration and institutional administration
- multiple experimental models changing live schedules; initially run them only in shadow/backtest mode
- a public scheduler-plugin marketplace or unrestricted model code
- executable code tasks and IDE plugins until the medical thesis is validated

### Prioritization

ICE uses impact × confidence ÷ effort, each scored 1-5. Scores are directional product judgments.

| Candidate | Impact | Confidence | Effort | ICE | Decision |
|---|---:|---:|---:|---:|---|
| Anki import/export and non-destructive companion workflow | 5 | 5 | 3 | **8.3** | Foundation |
| Scheduler-neutral history and model-adapter contract | 5 | 4 | 3 | **6.7** | Build into foundation while supporting one live model |
| Review-load forecast with exam/time budget | 5 | 4 | 3 | **6.7** | Build in MVP |
| Practice-miss to source-backed repair task | 5 | 4 | 3 | **6.7** | Build in MVP if question-bank capture is feasible |
| Grounded co-creation and card-quality checks | 5 | 5 | 4 | **6.3** | Core differentiator |
| Multi-level recall/explanation/application tasks | 5 | 4 | 4 | **5.0** | Build narrow version |
| User-facing multi-model comparison and switching | 4 | 3 | 4 | **3.0** | Shadow mode first; expose after sufficient review data |
| Full note-taking workspace | 3 | 3 | 5 | **1.8** | Defer |
| Social/gamification layer | 3 | 2 | 3 | **2.0** | Defer |
| Deck marketplace | 4 | 2 | 5 | **1.6** | Defer; ecosystem fight is premature |

## Anti-goals

- Do not make Memory “for everyone” at launch. Generality belongs in the data model, not the go-to-market message.
- Do not claim an AI-generated card is correct merely because it cites a source.
- Do not optimize the number of cards generated; optimize accepted, retained, useful knowledge per study hour.
- Do not hide review debt or silently discard due work to make the dashboard look calm.
- Do not remove all cognitive effort. Retrieval is effortful by design; administrative and coordination effort are the costs to eliminate.
- Do not position against Anki users' identity or expertise. Make their existing investment more valuable.
- Do not ask beginners to select algorithms or tune mathematical parameters. Ask for desired outcomes and show their workload consequences.
- Do not claim that a model with better retrospective prediction necessarily produces better learning; validate prospective scheduling outcomes.

## Metrics and validation

### North-star outcome

**The percentage of exam-relevant learning objectives that reach demonstrated delayed recall and application proficiency within the learner's declared weekly study budget.**

This is harder to measure than cards reviewed, but it reflects the actual promise. Early proxies should remain explicitly provisional.

### MVP leading indicators

- Time to first useful diagnosis: under 10 minutes from import to a credible coverage or workload insight
- First-source activation: learner verifies at least five retrieval tasks and schedules a plan
- Week-four retention: completes at least four planned sessions in week four
- Review sustainability: median overdue workload remains below one planned day
- Model calibration: observed recall remains close to predicted recall across adequately sampled probability bands
- Preparation efficiency: at least 30% less preparation time than the learner's baseline, without lower source accuracy or seven-day recall
- Card quality: unsupported-answer rate below 1%; every generated answer traceable to an exact source passage
- Transfer: improvement on unseen application questions, not just the generated cards
- Portability trust: successful export and restore in usability testing without loss of cards, media, or review history within the supported scope

### First validation experiments

1. **Problem interviews and workflow observation — 15 participants**
   - 5 medical Anki power users
   - 5 students with persistent backlog or recent Anki churn
   - 3 RemNote-first users
   - 2 students who avoid spaced repetition
   - Observe a real lecture-to-review workflow. Measure time, tool switches, card decisions, backlog, and how they choose practice questions.

2. **Concierge prototype — one three-week medical block, 20-30 students**
   - Import the learner's real deck and sources.
   - Human-review all AI suggestions behind the scenes.
   - Deliver coverage gaps, review forecast, and recall/application tasks through an Anki-compatible output.
   - Compare preparation time, completion, seven-day delayed recall, and unseen application questions with each learner's baseline. Do not present this as a causal trial.

3. **Willingness-to-pay test**
   - Offer a paid continuation after the concierge block rather than asking hypothetical price questions.
   - Test student pricing around a low monthly plan and a discounted annual plan; do not infer payment intent from feature enthusiasm.

### Falsification criteria

Pause or change direction if:

- fewer than one-third of interviewed target users experience card-quality, context, or workload-planning pain at least weekly
- users value generated volume more than verified quality and will not participate in co-creation
- the workflow cannot save at least 30% of preparation time without degrading accuracy or delayed performance
- fewer than 40% of pilot users are still following the plan in week three
- Anki import/export cannot preserve the medical workflows users consider non-negotiable
- application practice adds time but does not improve performance on unseen questions

If users refuse to leave Anki but repeatedly use the planning and quality layer, that validates the companion model rather than falsifying the product.

## Risks and counterarguments

1. **Anki's friction may be a power-user filter, not an opportunity.** Users who overcome it gain enormous flexibility and may distrust a simplified layer. Memory must expose control progressively and make every intervention reversible.
2. **RemNote already covers most of the proposed surface area.** Memory only has a wedge if workload feasibility, card-quality assurance, and cross-level mastery are materially better, not just differently arranged.
3. **AI generation can remove beneficial learning.** Research supporting user-generated cards means total automation may save time while weakening encoding. Co-creation is a learning design requirement, not a UX flourish.
4. **Review effort cannot be product-designed away.** Mental effort is inherently aversive and spaced repetition creates real obligations. Memory can improve adherence and prioritization, but “effortless mastery” would be a misleading promise.
5. **Medical evidence is encouraging but not causal.** The 2026 systematic review reports positive Step 1 associations in several studies but emphasizes observational designs, self-selection, heterogeneous definitions, and mixed results for institution-level exams. [Systematic review](https://link.springer.com/article/10.1007/s40670-026-02643-5)
6. **Medical content creates safety and rights risk.** Course materials and commercial question banks may be copyrighted; patient-related notes may contain sensitive data; generated explanations may be wrong. Source permissions, privacy, deletion, and clear study-only boundaries are launch requirements.
7. **The developer segment may not generalize from students.** Programming is partly procedural, existing usage is niche, and the strongest available evidence is anecdotal. Treat engineers as a later product-discovery track.

## Recommendation

**Go, with a narrow thesis.** The category does not need another card database, scheduler, or generic AI tutor. There is a credible opening for a system that makes serious learning *feasible and trustworthy* across sources, cards, deadlines, and application practice.

Start with medical students who already use Anki. Build the smallest companion workflow that can diagnose coverage and future workload, co-create verified tasks, and preserve the user's existing ecosystem. Earn the right to become the primary review platform through measured learning outcomes and reliability, not by requiring migration on day one.

The next product decision should be whether Memory's first prototype is:

- an Anki-connected desktop companion, which minimizes switching risk and reaches power users, or
- a standalone local-first reviewer with excellent `.apkg` round-tripping, which gives more control over the experience but raises implementation and trust risk.

The research favors the **Anki-connected companion** for the first validation cycle.

## Evidence-quality notes

| Evidence | Class | Confidence | Main limitation |
|---|---|---|---|
| Official product manuals and pricing | Product fact | High for current capability | Does not prove usability or effectiveness; changes over time |
| 901-undergraduate digital-flashcard survey | Self-reported behavioral study | Medium-high | One university, pandemic period, platform mix dominated by Quizlet |
| Six experiments on user- vs premade cards | Controlled learning study | High for tested tasks | Short 48-hour delay and constrained educational passages |
| 2025 AI medical-card study | Preprint, manually evaluated implementation | Medium | One school, two blocks, non-random usage, not peer reviewed at search time |
| Medical Anki cross-sectional studies | Observational/self-report | Medium | Selection bias, inconsistent definitions, limited causal inference |
| 2026 Anki systematic review | Systematic synthesis | Medium-high | Underlying studies remain observational and heterogeneous |
| Reddit, forums, App Store reviews | User report | Low individually; medium when triangulated | Self-selection, unknown user identity, extreme experiences overrepresented |
| Developer extensions and discussions | Adoption signal/anecdote | Low-medium | Does not establish market size or willingness to pay |
