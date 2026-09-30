# Engram — First Build Brief

Date: 3 September 2026  
Status: Ready for a future implementation run. Documentation only today.

## Purpose and precedence

Build a usable Anki-style flashcard application first, then expand it in later iterations. The immediate goal is a polished, dependable study foundation with flowing animations and the visual warmth of the supplied references.

This brief records the user's latest scope and takes precedence over the broader roadmap in `ENGRAM-PLAN.md` for the first build. In particular, cumulative AI testing is deferred alongside all other AI features. The existing plan remains the long-term product reference.

Creating this document does not start implementation or schedule an overnight run. Begin development when the user subsequently asks to execute this brief.

Project location: `C:\Users\aoswa\Documents\project\Memory`.

## 1. Intended result

A learner can open Engram, create a deck, add and edit cards, study due material, reveal answers, grade recall, and return later with their cards and review progress intact.

The application should feel like a coherent product, not a collection of mock screens. Visible actions must work, empty states must guide the user, and the central review loop must be reliable. “Anki-style” means the essential flashcard and spaced-repetition workflow; full Anki feature parity is outside this first build.

## 2. Apple platforms from the first build

Updated direction: design and implement for iOS (iPhone), iPadOS, and macOS together from the beginning. This replaces the previous provisional web-first default. The goal is one recognisable Engram experience with platform-appropriate layouts, not three unrelated apps or an enlarged phone interface on Mac.

Use Swift and SwiftUI as the intended native approach, with shared learning models, scheduling, persistence services, design tokens, and reusable components. Keep platform-specific navigation, window management, menus, file handling, and input adapters at the edges. Apple supports a [multiplatform app configuration](https://developer.apple.com/documentation/xcode/configuring-a-multiplatform-app-target) and [shared SwiftUI interfaces](https://developer.apple.com/documentation/technologyoverviews/swiftui). Sharing code still requires platform-specific design and testing.

Inspect repository instructions and existing code before implementation. Select deployment minimums against required APIs and an available stable Xcode version; record them rather than silently depending on beta-only features. Assess scheduling dependencies for Apple compatibility before adopting them. A single target or shared packages with thin platform targets are both acceptable; choose the simplest structure that can actually build for all three platforms.

### Environment and overnight execution

The currently available environment is Windows. Native Apple UI builds, previews, simulators, and final verification need a compatible Mac and Xcode. Check access at the beginning of the later run. [Apple's Xcode requirements](https://developer.apple.com/xcode/system-requirements/) define supported hosts and SDKs.

If Mac tooling is available, build and exercise the application on all three platform families. If it is unavailable, continue useful work on native source, shared logic, documentation, and reviewable design assets, but clearly label Apple compilation and runtime checks as pending. Do not silently substitute a web app as the delivered product. An optional browser-based visual study may support design review but is not proof of native functionality. Do not mark the complete build as verified based on screenshots or static source inspection.

Designing the three platforms together reduces later redesign; it does not guarantee that a production-ready, fully tested release will fit into one overnight session. Leave completed work and precise remaining checks in the handoff. This brief does not itself start or schedule the run.

### Adaptive layout contract

| Area | iPhone | iPad | Mac |
| --- | --- | --- | --- |
| Navigation | Compact Today / Library / Activity tabs; settings in a consistent toolbar location | Collapsible sidebar with the same destinations | Persistent collapsible sidebar, window toolbar, native menus |
| Library | Deck list → cards → editor | Sidebar/list + detail when width allows | Sidebar + efficient card list + selected-card detail |
| Review | Single focused column; bottom actions above safe area | Centred reading surface; optional deck context outside focus mode | Centred reading surface; keyboard-first controls; optional collapsible context |
| Editor | Full-height sheet or pushed screen; preview as a separate mode | Editor and preview side by side when space permits | Resizable editor/detail with persistent preview when space permits |
| Actions | Touch, explicit buttons, optional gestures | Touch plus keyboard/trackpad | Keyboard, pointer, context menus, command menus |
| File operations | System document picker/share sheet | System document picker/share sheet | Native open/save panels |

Respond to available window width, not just device labels. An iPad in a narrow window uses the compact layout. Resizing must preserve the selected deck, draft, review answer state, and scroll position where practical. On larger displays, spend extra space on navigation and related context rather than widening reading text indefinitely.

Suggested layout bands for initial design studies: compact below 600 pt, intermediate 600–999 pt, expansive from 1000 pt. These are proposed content-driven design thresholds, not Apple platform constants. Validate them against actual content and system navigation behaviour.

Use a 220–280 pt sidebar, optional 280–360 pt library list, and approximately 560–720 pt maximum review content width as starting dimensions. Compact horizontal margins start at 20 pt, wider layouts at 28–40 pt. At accessibility text sizes, prioritise reflow over these preferred measurements.

Implement independent local persistence on each platform. Cross-device availability does not imply cross-device synchronisation; cloud sync remains deferred. Preserve stable identifiers, versioned export, and a shared schema so future sync can be added deliberately. If multiple windows are supported, prevent competing review sessions from double-grading the same card; otherwise explicitly limit review to one active session.

### Required Anki source reconnaissance before implementation

The user explicitly requests studying [Anki's official source](https://github.com/ankitects/anki) to understand its structure, mature workflows, and the features relevant to Engram. Clone `https://github.com/ankitects/anki.git` into a separate reference checkout, outside Engram's application source, and record the exact commit/tag inspected. Inspect a stable release for compatibility work and distinguish it from development `main`. Do not modify the reference checkout or accidentally vendor its entire history into Engram.

Start with the README, development documentation, directory map, and tests. The repository describes itself as the computer version of Anki; it is not the native AnkiMobile source. At the inspected repository root, `rslib`, `pylib`, `qt`, `ts`, and `proto` are useful exploration starting points. Verify responsibilities and trace actual code paths rather than assuming their contents from names.

Trace these areas with concrete source/test references:

- Collection storage, schema migrations, notes versus generated cards, note types, fields, tags, and deck hierarchy.
- Basic/reversed/cloze generation, template rendering, media, and unsupported-content handling.
- Review session construction, learning/relearning, rating, undo, suspension/burying, daily limits, sibling handling, and day-boundary logic.
- FSRS integration, parameters, due-date representation, review logs, and scheduler-version handling.
- `.apkg`/`.colpkg` import/export, media manifests, duplicate detection, ID mapping, history, package/schema variants, and migrations.
- Browsing/search/editing, bulk operations, backup/restore, statistics, and settings.
- Sync, filtered/custom study, add-ons, and other mature features as catalogue items even when deferred for Engram.

Produce `ANKI-SOURCE-REVIEW.md` containing: inspected revisions; architecture map; key code paths and tests; notes on data/format semantics; and a feature matrix with Anki behaviour, source reference, Engram status (Build now / Later / Unsupported / Needs decision), rationale, and verification approach. Distinguish code-observed behaviour from assumptions. Do not claim to understand every feature from a README or a directory listing.

Map the findings to this brief. Implement all agreed first-build features, use Anki to catch overlooked dependencies and edge cases, and record broader features for later. This research step does not automatically expand the first build into full Anki parity. Keep Engram's SwiftUI platform adaptation, themes, and modular boundaries rather than copying Anki's desktop presentation architecture wholesale. Research should lead promptly into a working vertical slice, with deeper investigation alongside the relevant subsystem work.

Anki's [root licence](https://github.com/ankitects/anki/blob/main/LICENSE) specifies AGPL-3.0-or-later with listed exceptions. Studying structure and behaviour is distinct from incorporating source. Before copying, translating, or linking implementation code, record its applicable licence and implications for Engram's intended distribution. Do not treat publicly visible code as unrestricted reuse or assume rewriting it in Swift removes licence considerations. Prefer independent implementations of documented behaviour and separately licensed dependencies when suitable; keep provenance and required notices for any incorporated material.

## 3. Required features

### Today / home

- Show real due and new-card counts from stored data.
- Provide a prominent start-review action.
- Show decks with meaningful counts and a clear create-deck action.
- Show a useful empty state before the user has created content.
- Display a simple session or daily summary from actual review events; avoid invented retention or mastery scores.

### Deck management

- Create, rename, and delete decks.
- Show a deck's cards, new cards, and due cards.
- Confirm destructive deletion and clearly describe its effect on cards and history.
- Allow users to start a review for one deck or all due decks.

### Card creation and editing

- Support basic question/answer cards.
- Support cloze deletion: hide marked text while retaining surrounding context, then reveal the missing content with the answer.
- Define and document cloze syntax, including how multiple cloze markers create reviewable cards.
- Keep a note's content separate from generated review cards where appropriate, so cloze siblings do not overwrite each other's schedules.
- Provide an editor preview, validation, save/cancel, and understandable error messages.
- Support tags, search, and moving a card or note between decks with clearly defined behaviour.
- Support editing, deleting, and suspending/resuming cards.
- Preserve scheduling when ordinary text edits are saved.
- Include an optional manual source/reference field to support later source-grounded learning.

### Review flow

- Present one prompt at a time without exposing the answer prematurely.
- Reveal the answer with an explicit button; support Space on desktop when focus is not in an input.
- Provide Again / Hard / Good / Easy grading after reveal, with keyboard equivalents 1–4.
- Show meaningful scheduling intervals when available from the scheduler.
- Persist each grade before advancing the session.
- Prevent repeated clicks or animation overlap from recording duplicate review events.
- Support undo of the most recent grade, restoring the relevant scheduling state.
- Offer an exit/resume flow that preserves already completed reviews.
- Show an honest completion state when the queue is finished or no cards are due.
- Define behaviour for cards becoming due during a session and learning cards that reappear after a short interval.

### Spaced repetition

- Use a maintained scheduling implementation where practical; evaluate an FSRS implementation as a candidate rather than inventing an algorithm casually.
- Keep scheduling logic separate from UI and animation state.
- Handle new, learning, review, relearning, and suspended material explicitly.
- Persist review timestamps, ratings, next due times, scheduler state, and the history needed for undo and basic statistics.
- Define daily limits and day boundaries, including timezone behaviour.
- If a simplified fallback is necessary, disclose exactly what it supports and what differs from the intended scheduler. Do not present random intervals as spaced repetition.

### Persistence and portability

- Persist decks, notes/cards, scheduling, preferences, and review events across reloads and restarts.
- Use durable native local persistence shared in design across the Apple targets; evaluate SwiftData or SQLite against deployment needs. Keep it behind a repository boundary and persist schema versions. Never keep the library only in view state.
- Make the core review flow work offline after the app has been loaded and made available locally; state the exact offline capability delivered.
- Provide Anki package import/export and a versioned complete native backup/restore path, including media, as specified below.
- Define duplicate-import behaviour. Invalid imports must leave existing data intact.
- Explain that each installation stores its own library until sync is implemented. Provide backup/export; app deletion or device loss can remove local data.
- Follow the Anki interoperability requirements below; unsupported package variants or content must be reported before import/export.

### Anki interoperability — required first-build scope

Latest user direction: Engram is a standalone study app. Users can migrate their existing Anki data into Engram and export it again. The companion-first recommendation in the research is background advice, not the approved implementation direction. Anki import/export is now part of the first build and supersedes previous deferral of packaged decks and scheduling migration.

Support Anki deck-package (`.apkg`) import and export, plus collection-package (`.colpkg`) import for whole-library migration. Provide complete Engram-native backup/export and restore as well. Whole-collection Anki export may be added where validated; the required Anki export path is `.apkg` for selected decks or the supported library content. Do not describe native JSON as Anki compatibility.

Anki documents deck packages and collection packages separately, and scheduling/media inclusion affects what is transferable. Use the [Anki export manual](https://docs.ankiweb.net/exporting.html) and [packaged-deck import documentation](https://docs.ankiweb.net/importing/packaged-decks.html) as starting references. Inspect current format implementations and licensing before choosing a parser/writer. Record exact supported Anki versions and package variants; an extension alone does not establish compatibility.

**Data fidelity:** preserve deck hierarchy, note identifiers, note types and fields, generated card relationships, tags, basic/reversed/cloze content, supported formatting, media references and files, suspension state, review history, and scheduling information when present and correctly mappable. Keep imported review records and source scheduler metadata distinct from Engram's newly generated events. Preserve source identifiers with an origin namespace to prevent collisions.

Implement ordinary image display and audio playback needed for imported cards, while keeping voice tutoring and transcription deferred. Preserve original template/field data. Custom HTML/CSS, JavaScript-based templates, image occlusion, add-on-dependent behaviour, and unsupported card types require explicit detection and a compatibility report. Do not flatten unsupported cards into misleading plain text or silently drop them. Do not execute imported scripts with application privileges. Isolate imported content and validate archive paths and sizes.

**Import flow:** choose file → inspect → show deck/card/media/history counts and compatibility findings → choose destination and scheduling treatment → confirm → import transactionally → show results. Collection imports must never silently replace an existing Engram library. Offer an explicit new-library or supported merge workflow with a pre-import backup. Repeated imports require stable duplicate detection and visible keep/update/skip choices. Keep the original package untouched, and make failure or cancellation leave the active library consistent.

**Scheduling continuity:** preserve historical evidence and due dates where compatible. Identify source scheduling versions, learning states, day-boundary semantics, and available memory parameters. If exact conversion is unsupported, explain it before import and offer a clearly labelled content-only import or an explicit reinitialisation path. Never reset mature cards without consent. Missing history cannot be reconstructed from content-only exports and must be reported as absent.

**Export flow:** allow selected decks or the whole supported library to export as Anki packages, with media included by default. Offer a personal-transfer mode with supported scheduling/history and a sharing mode without personal review progress. Explain the mode before export. If a future or alternative Engram scheduler cannot map to Anki, show the limitation and offer a disclosed content-only package; retain complete state in the native backup. Export must never mutate the source library or require paid AI.

**Complete native backup:** retain all Engram data, source/template originals, media, review events, scheduler versions/state, and supported provenance. Use a versioned manifest plus media payloads rather than a JSON-only file that silently excludes attachments. Keep credentials out of exports. Display progress and actionable errors for large libraries; write output atomically where practical.

**Modular implementation:** create an Anki format adapter separate from the domain, persistence engine, scheduler, and views. Parsing produces a validated intermediate collection and a compatibility report; application use cases control mutation. Keep import/export format versions independently versioned. New format support must not require rewriting review screens.

**Acceptance:** test real fixtures from documented Anki versions with basic, reverse and multi-cloze notes, nested decks, Unicode, images/audio, tags, history, suspension, missing media, malformed packages, and repeated imports. Exercise `.colpkg` import without overwriting an existing library. Round-trip supported fixtures Anki → Engram → Anki in a disposable Anki profile and compare content, IDs/mappings, media, history, and scheduling semantics. Test native backup restoration separately for complete fidelity. Record unsupported cases and platform/runtime checks explicitly. Generating a file with the correct suffix is not proof of compatibility.

## 4. Visual design specification

### 4.1 Art direction and reference interpretation

Engram should feel like a carefully typeset study journal with warm paper surfaces and quiet, sculptural depth. It should be welcoming enough to return to daily and precise enough for serious study. The signature is the relationship between deep olive, luminous ivory, honey amber, generous rounded geometry, and expressive serif headings paired with clean functional text.

The supplied images are App Store promotional compositions, not complete production screens. Their giant headlines, black screenshot viewer, tilted device panels, overlapping badges, health copy, and review laurels are not requirements for Engram's interface. Distil their typography, colour, spacing, and depth into a functional learning product. Do not copy the reference app's logo, marketing claims, or illustrations.

The seven current references are preserved in `design/references/` with the following reading:

| File | Observed visual language | Engram translation |
| --- | --- | --- |
| `01-progress-path.png` | Taupe surround; olive inset; thin meandering ivory/amber line; variable-size circular nodes; serif active label | Optional labelled session milestones; one prominent current marker; no invented retention curve |
| `02-editorial-palette.png` | Olive field; white sans headline paired with amber high-contrast serif; cream, amber, and taupe circular badges | Mixed typographic hierarchy; restrained icon medallions; amber used deliberately |
| `03-layered-cards.png` | Cream surface floating over olive; diffuse warm glow; round white marker; overlapping olive/taupe/ochre panels | Clear surface hierarchy and soft shadow; aligned usable cards in the app; overlaps reserved for illustration |
| `04-light-dark-depth.png` | Warm light and near-black alternatives; muted labels; rounded mini-panels; fine progress line | Coordinated light/dark palettes and shallow depth, without copying the pictured partner feature |
| `05-calendar.png` | Airy cream calendar; serif month title; soft horizontal bands; circular selected day | Real review activity or workload calendar; correct date grid and labels; selection independent of status colour |
| `06-information-cards.png` | White foreground information panel; serif heading and line icon; dark sans body; very soft shadow | Deck detail and review-history panels with readable hierarchy; charts only when backed by real data |
| `07-quiet-reading.png` | Large negative space; small contextual label; centred serif statement; low-contrast ambient colour | Calm short-question presentation and session completion; long answers use left-aligned readable text |

Static screenshots do not establish actual animation behaviour. The motion specification below is an original proposal consistent with the visual reference.

### 4.2 Colour tokens and use

All values below are design starting points inferred visually, not measured brand colours. Define semantic colour assets with light and dark variants rather than scattering literal colours through views.

| Semantic token | Light | Dark | Use |
| --- | --- | --- | --- |
| Canvas | `#F7F3E8` | `#20231C` | Main background |
| Surface | `#FFFCF5` | `#2C3026` | Cards and editor surfaces |
| Elevated surface | `#FFFFFF` | `#373C2F` | Sheets, selected foreground panels |
| Olive anchor | `#434833` | `#434833` | Focus panel and identity anchor |
| Primary text | `#25281F` | `#F7F3E8` | Questions and main labels |
| Secondary text | `#666650` | `#C5C3B5` | Metadata and supporting copy |
| Decorative taupe | `#A4947B` | `#AA9C82` | Quiet fills/illustrations, not default small text |
| Amber accent | `#D79B42` | `#E8B765` | Selected marker, occasional emphasis |
| Amber ink | `#80500D` | `#E8B765` | Accent text where contrast permits |
| Hairline | `#DEDACD` | `#4A503F` | Dividers and subtle boundaries |
| Soft sage | `#E0E6D2` | `#364332` | Positive/finished supporting fill |
| Soft rose | `#F3DDDA` | `#4B302E` | Again/error supporting fill |

Aim for predominantly neutral reading space, with olive anchoring major areas and amber occupying a small fraction of the screen. This is a composition guide, not a fixed percentage quota. Use dark text on amber buttons unless contrast testing supports another pairing. Never use taupe-on-cream merely because it resembles the reference if it makes metadata unreadable.

The primary study action can use an olive fill with ivory text; amber is strongest as a current-position marker or limited callout. Grade controls retain written labels and interval text. Again may use muted rose, Hard a warm neutral, Good olive/sage, and Easy a distinct neutral treatment. Colour is supplementary, never the sole explanation.

Dark mode must be intentionally composed. Use deep olive charcoal and lifted surfaces, not automatic colour inversion. Keep amber soft, text warm, and borders slightly more visible because dark shadows alone will not establish depth. Native system chrome may use system materials; content cards should remain predominantly opaque and readable.

### 4.3 Typography

Use a serif with expressive thick/thin stroke contrast for selected display text. Pair it with a neutral, open sans serif for sustained reading and controls. Begin with platform-provided serif and sans designs; assess a licensed bundled editorial serif only if the default cannot produce the intended character. Record the font and licence. Do not assume the screenshot's exact font is identifiable.

| Role | Initial size / treatment | Use |
| --- | --- | --- |
| Hero heading | 32–40 pt compact, 40–48 pt wide; regular serif | Today greeting or session completion, one per screen |
| Page title | 28–34 pt serif | Deck or main content heading |
| Section heading | 20–24 pt serif or medium sans | Consistent role across screens |
| Short review prompt | 24–30 pt; serif only when short and readable | Simple question emphasis |
| Long prompt / answer | 17–20 pt sans; relaxed line spacing | Technical content and explanations |
| Body | 16–17 pt sans | Supporting prose |
| Controls | 15–17 pt medium sans | Buttons, form labels |
| Metadata | 12–14 pt sans | Counts, dates, intervals |

Treat this as a scalable hierarchy, not fixed text sizing. Support Dynamic Type and macOS accessibility text preferences where applicable. Use approximately 1.35–1.5 line height for sustained reading, avoid aggressive tracking, and use tabular numerals where count alignment helps. Do not shrink content to keep an attractive composition. Wrap long deck names and allow answer scrolling. Avoid centred paragraphs; centre only brief prompts or completion messages. Do not apply decorative serif to every label.

### 4.4 Geometry, spacing, and surface depth

Use a spacing scale of 4, 8, 12, 16, 24, 32, 48, and 64 pt. Typical card padding is 20–24 pt on compact screens and 28–32 pt for a large study surface. Related label/value pairs sit close together; unrelated sections receive 24–32 pt separation.

Use continuous rounded corners: roughly 24–32 pt for a primary study surface, 18–24 pt for deck cards, 12–16 pt for inputs and compact panels. Use capsules for chips and small status labels. Avoid placing every row in its own oversized rounded container. Let platform sheets and window corners follow the system.

Use one subtle shadow family: low-opacity olive-black, broad soft blur, a small downward offset. Starting study-card shadow: opacity 0.06–0.10, radius 16–24 pt, y offset 6–10 pt. A sheet may receive slightly stronger separation. Prefer a hairline to a shadow for dense desktop lists. Avoid stacked heavy shadows, thick outlines, glossy bevels, and permanent coloured glows.

The reference's gentle ambient tint can appear once behind a Today focus panel or completion illustration. Keep it low contrast, static, and out of dense text areas. Surfaces should read as warm and matte.

### 4.5 Components and states

- **Deck card:** small consistent line icon or monogram, serif title, compact due/new counts, clear primary action. Selection uses a subtle fill or border change. Context actions stay discoverable without dominating the card.
- **Review surface:** contextual deck label above the prompt, generous breathing room, answer separation by spacing or a hairline, grading controls anchored outside the scrolling content. Maintain geometry between question and answer without imposing a fixed height on long content.
- **Buttons:** one strongest action per region; secondary actions use subdued fill/outline or text. Provide pressed, keyboard focus, disabled, loading, and destructive states. Loading preserves button width and prevents duplicate submissions.
- **Inputs:** visible labels, warm filled or subtly outlined field, clear focus boundary, inline error text. Placeholder text is not the label. Validation should preserve drafts.
- **Tags:** quiet compact capsules with readable text; selected tags use olive tint and an explicit selected state.
- **Icons:** one consistent family of simple outlined symbols, generally 18–22 pt and visually regular weight. Decorative icon medallions may use 40–56 pt circles. Native symbols are a practical starting point; label unfamiliar actions.
- **Dialogs:** title, short consequence statement, clear actions, correct keyboard focus. Destructive confirmation must identify the affected deck/cards.
- **Empty states:** one modest illustration or icon, a short explanation, and an immediate useful action. No fake analytics to fill space.
- **Errors:** explain what failed, preserve entered work, and offer a specific recovery action. Use text plus an icon or colour.

### 4.6 Screen compositions

**Today:** a warm canvas, restrained greeting, date/context label, and an olive study panel with a large due count and primary start action. Below, show the library or a few relevant decks and a compact factual activity summary. On iPhone these stack; on iPad/Mac the secondary material can sit beside the main panel. Avoid a marketing hero inside the working application.

**Library:** prioritise scanning deck titles, counts, and tags. iPhone uses a clear list or a small number of roomy cards. Mac can use a denser list/detail arrangement. Search and create remain stable as the window changes. A library of 100 decks must be as usable as a library of three.

**Deck detail:** serif deck name, supporting totals, start/add actions, then a card list. Due state and suspension must be readable in rows without opening every card. Use real scheduling data.

**Review:** one question, one reveal action, one predictable grade region. Short prompts may sit centrally with generous space; longer text is top-aligned. On compact width use a 2×2 grade layout if four full labels/intervals do not fit. Larger widths can use a single row. Never truncate grade labels or intervals for symmetry.

**Editor:** labelled fields and a clear card-type selector. Use a mode switch between editing and preview on phone, a split presentation on wider windows. Put deck/tag/source metadata below the content hierarchy. Preserve drafts across size changes.

**Activity:** modest counts and review history from actual events. If a calendar is included, borrow the muted bands and amber selected-day marker while preserving correct chronological order and an accessible textual alternative. No invented mastery graph or decorative data curve. Do not expand the first build into advanced analytics to reproduce a screenshot.

**Completion:** a short serif message, factual session totals, and a return action. A small amber path or completed marker may provide the visual reward. Do not use guilt, streak pressure, or fabricated praise.

### 4.7 Accessibility and design acceptance

Target at least 4.5:1 contrast for ordinary text and 3:1 for large text and essential non-text boundaries. Measure actual pairings during implementation. Use touch hit regions of at least 44×44 pt for iPhone/iPad even when the visible icon is smaller. Mac controls may follow platform density but must retain clear pointer and keyboard targets.

Support VoiceOver order, descriptive labels, visible focus, increased contrast, reduced motion, and text enlargement. Grade controls must announce their label and interval. Answer reveal should move or announce context appropriately without losing the learner's place. Decorative curves and medallions should not clutter accessibility navigation.

Review designs with empty libraries, dense libraries, long titles, multi-paragraph answers, large text, light/dark appearance, keyboard-visible forms, and narrow windows. The visual system is complete only when these states remain coherent.

### 4.8 Liquid Glass navigation — required first-build direction

User addition: incorporate Apple Music-inspired Liquid Glass navigation into the first build. Combine a floating translucent navigation layer with Engram's warm, opaque reading surfaces. This refines the earlier system-chrome guidance: Liquid Glass is an intentional part of the navigation design, not merely an optional effect.

**Native implementation first.** Start with SwiftUI's standard tab/navigation/toolbar components on supported Apple releases. Apple documents that standard components adopt the new material; use public custom glass APIs only for controls the standard components cannot express. Consult [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) and [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views). Check API availability against the selected SDK and each platform's deployment minimum. Avoid building a custom shader merely to reproduce an effect the platform already supplies.

**iPhone composition.** Use a floating capsule-style tab bar for Today, Library, and Activity, with clear icons and labels, a softly defined selected state, rounded edges, and subtle background response. Let the system manage optical treatment, touch response, and supported transitions. Use restrained olive/amber selection tint only where legibility remains strong. The warm content underneath should provide the atmosphere; do not saturate the entire glass surface amber. Respect the home indicator, safe areas, and keyboard. No study text or last list row may become inaccessible behind the bar.

**iPad and Mac adaptation.** Preserve the material language while following native navigation placement. iPad may use the system's adaptable tab/sidebar presentation; narrow windows must remain usable. Mac uses appropriate glass toolbar controls and system sidebar treatment rather than a phone tab bar copied to the bottom of every window. Consistency means related materials and interactions, not identical placement.

**Study mode.** Keep the flashcard and answer surface opaque for sustained reading. A focused review may hide global tabs while retaining an obvious exit/back route. Do not make grading controls move, shrink, or disappear as a learner tries to answer. If an Apple Music-like compact accessory is later useful, it may represent a resumable study session with a real Resume action; it is optional and must not introduce fake playback controls or expand scope into voice playback.

**Optics and motion.** Aim for translucent depth, gently highlighted edges, and fluid selected-state changes driven by the native material. Avoid stacking glass on glass, excessive blur, fabricated lens distortions over text, and independent wobbling controls. Scroll-related minimisation is optional for browsing if supported and discoverable; never sacrifice stable review controls to imitate Music. Honour Reduce Transparency, Increase Contrast, and Reduce Motion. Provide an opaque or ordinary system-material fallback on unsupported OS versions and record that it is a fallback, not native Liquid Glass.

**GitHub reference available for adaptation.** [mikonyaa/LiquidGlassTabBars](https://github.com/mikonyaa/LiquidGlassTabBars) contains native, floating, and morphing SwiftUI tab-bar examples. Its [MIT licence](https://github.com/mikonyaa/LiquidGlassTabBars/blob/main/LICENSE) permits reuse subject to its terms. This is a community implementation inspired by Apple, not Apple's Music source code. Its README describes an iPhone/iPad demo and native/fallback variants; it is not evidence of a finished Mac navigation solution. The repository and licence were inspected for planning; the code has not been integrated or runtime-verified for Engram.

During implementation, prefer the native approach, then inspect and reuse a small relevant portion of a licensed example only if it improves the result. Verify the selected revision, platform support, accessibility, and dependencies; preserve the required copyright/licence notices in third-party acknowledgements if code is copied. Do not import an entire template or its branding by default.

**Acceptance:** capture navigation over light, olive, and dark content; check selected/unselected labels, scrolling to the final row, keyboard presentation, screen-reader tab semantics, larger text, reduced transparency/motion, and narrow iPad/Mac windows. Verify that tab changes preserve drafts and review state. The final handoff should identify whether the bar uses system components or adapted third-party code and list native checks still pending.

## 5. Motion choreography

Motion should feel smooth, lightly weighted, and settled. It establishes continuity between deck, question, answer, and completion. It must support repeated study without introducing waiting or distraction.

Define named motion tokens rather than arbitrary per-view timings: immediate feedback 100–140 ms, content reveal 160–220 ms, navigation 240–320 ms, and one-time completion 300–450 ms. Use ease-out for arrivals and short ease-in for departures. If using springs, prefer a well-damped response with negligible overshoot. These are starting values to validate on actual devices.

| Interaction | Choreography | Constraint |
| --- | --- | --- |
| Button press | Brief opacity/tint response; optional scale to 0.98 | Avoid shifting surrounding layout; pointer/keyboard actions work equally |
| Open deck | Title/surface continuity when supported; 8–16 pt movement plus fade otherwise | Respect native back-navigation gestures and system transitions |
| Reveal answer | Reveal answer region with opacity and small vertical settling; adjust height smoothly | Default to readable content reveal; do not require a full 3D flip or rotate long text |
| Grade | Commit once; outgoing card moves 12–24 pt and fades; incoming card settles into the same frame | Correctness comes from saved state, never animation completion; rapid inputs cannot grade the next card accidentally |
| Counts | Brief numeric transition after committed changes | No oscillation, re-counting from zero, or fictitious progress |
| Open editor | Platform sheet transition with restrained internal fade | Focus the correct field; keyboard appearance must not cover Save |
| Filter/search | Small crossfade or row insertion/removal | Keep scrolling stable; no cascade animation on every keystroke |
| Completion | One restrained path/marker finish with soft fade-in of summary | No endless animation, confetti burst, or forced delay |

Never animate the whole screen merely because it appeared again. Avoid floating cards, continual breathing/glow, parallax while reading, elastic buttons, and long staggered lists. Optional haptics on supported devices should be subtle and supplementary; no sound or vibration should be required to understand a grade.

Reduced Motion removes spatial travel, scaling, path drawing, and decorative effects, using immediate updates or short fades. Animation state must remain separate from scheduling state. Preserve focus, selection, and unsaved content when transitions are interrupted or the window resizes.

Test a long sequence of rapid reviews and a slow sequence with long answers. Aim for consistently smooth rendering on the supported baseline device; measure before claiming a frame rate. Native animation tools should be used where practical, and layout-heavy effects should not compromise typing or scrolling.

## 6. Explicitly deferred features

Do not spend the first build implementing:

- AI question/card generation, tutoring, or AI grading.
- Cumulative assessments or adaptive questioning.
- PDF ingestion, RAG, embeddings, or automatic citations.
- Codex/MCP integrations or connector credentials.
- Voice, local model servers, cloud AI, or on-device models.
- Concept/mastery graphs or predicted understanding scores.
- Accounts, cross-device cloud sync, subscriptions, or production deployment.
- Full Anki application/add-on parity, native image-occlusion authoring, and a plugin ecosystem. Anki package import/export and supported media/history preservation are explicitly in scope.

Preserve sensible extension points without building speculative frameworks. The future AI requirement remains: questions, expected answers, and explanations should be grounded in source materials, with inspectable references and no unsupported gap-filling. Grounding reduces hallucination risk but does not guarantee correctness.

## 6A. Modular architecture — required from the first build

User requirement: keep styling, scheduling, storage, and future services replaceable. Plan for the described AI, source grounding, voice, MCP, pricing, and cross-device features while implementing only the flashcard foundation now. Modularity is a first-build acceptance requirement. It does not mean arbitrary components can be exchanged without migrations or validation.

### Dependency rules

Use a small set of explicit modules with clear responsibilities. Prefer Swift package targets for meaningful boundaries and feature folders inside them; do not create a package for every view. The following names are illustrative, not mandatory framework choices.

| Module | Owns | Must not depend on |
| --- | --- | --- |
| LearningCore | Stable identifiers, notes/cards, review events, scheduling contracts, validation | SwiftUI, database models, provider SDKs, billing |
| StudyApplication | Create/edit/review/undo/import use cases and session coordination | Concrete persistence, concrete scheduler, platform views |
| DesignSystem | Themes, semantic tokens, motion, reusable visual components | Scheduling, storage, AI, billing |
| Features | Today, Library, Editor, Review, Activity, Settings presentation | Direct database access or vendor SDK calls |
| PersistenceAdapters | Native local database implementation, migrations, repository transactions | View state or theme implementation |
| SchedulingAdapters | FSRS or other algorithm integration and state conversion | SwiftUI and platform navigation |
| PlatformShells | iPhone/iPad/Mac navigation, file panels, lifecycle, dependency assembly | Duplicated learning rules |
| Future service adapters | AI, retrieval, speech, sync, MCP, entitlements when implemented | Unrelated feature internals |

Core and application modules define the contracts they need. Concrete adapters implement them. Assemble implementations in one composition root per application configuration and inject dependencies explicitly. Views interact with feature models/use cases, not global service locators or SDK singletons. Keep platform availability checks at platform boundaries where practical.

Use domain values across module boundaries; do not expose SwiftData-managed objects, raw database rows, or a provider's response object to every feature. Map external types at the adapter boundary. Inject clocks and identifier generators where determinism matters. Keep public interfaces small and add capabilities when justified by an actual workflow.

### Theme system: user-selectable from the beginning

Create a versioned theme definition using semantic roles: canvas, surfaces, primary/secondary text, accent, selection, borders, grade states, typography roles, spacing, shape, elevation, and motion. Components request roles, not literal hex values or named fonts.

Include the reference-inspired **Engram Warm** default and one genuinely different **Engram Neutral** preset to demonstrate that colours and typography can change without editing feature views. Both support light/dark variants. Separate theme selection from appearance preference (System / Light / Dark), persist both, and apply changes across the app without losing drafts or review state.

Liquid Glass policy belongs to the design system and platform adapter: tint, fallback material, and opacity preference should be centrally controlled. Do not attempt to override system accessibility settings or claim theme tokens can fully control Apple's native glass renderer. Accessibility preferences override decorative motion and transparency choices.

Keep text size and reduced-motion preferences independent of the selected theme. Validate contrast and enlarged text for every shipped preset. A user-editable theme marketplace, downloadable executable themes, and arbitrary font importing are deferred; declarative built-in presets are sufficient initially.

### Replaceable scheduling engine

Define a scheduler contract around operations such as initialise state, preview grade outcomes, and apply a review. Inputs should include the card's scheduling state, prior history when required, rating, explicit time, and settings. Outputs should include the next due time, learning state, interval preview, and updated algorithm-specific state. The scheduler must not save data or update UI itself.

Keep review-queue policy separate from the algorithm: daily limits, new-card ordering, sibling burying if introduced, deck filters, suspension, and session selection belong to application policy. This prevents a future algorithm swap from rewriting the review interface.

Persist an envelope containing scheduler identifier, implementation/state-schema version, settings version, and algorithm-specific state. Store vendor-neutral review events alongside it. Never force every future algorithm into FSRS-only fields. Interval previews and committed results must use the same scheduler, settings, and relevant time inputs.

Algorithm replacement is an explicit migration, not changing an import statement. Preserve backups and review history; decide whether to replay history, convert state, or reset scheduling for affected cards. Disclose changed due dates and limitations. Reject unsupported state versions rather than silently treating mature cards as new. Undo must restore the prior scheduler state and related queue state; do not switch algorithms halfway through an active review transaction.

Deliver one real scheduler for study. Prove replaceability using a second deterministic test adapter through the same application workflow; the test adapter must not appear as a production learning algorithm. A public algorithm selector and a second production scheduler can be added later without changing feature views.

### Persistence and future sync

Define repositories and transactional operations around domain needs, including atomic review-event plus schedule updates, undo, and validated import. The implementation may use SwiftData or SQLite, but features must not import that choice directly. Export data in a documented portable schema rather than dumping a database-specific representation.

Give notes, cards, decks, reviews, and sources stable identifiers; maintain schema versions and explicit migrations. Use idempotent mutation/review identifiers to prevent duplicate commits and later support sync retries. Record undo/corrections explicitly so audit history can remain meaningful. Do not physically erase unrelated evidence when reversing a grade.

Plan deletion/tombstone and conflict semantics in the architecture notes before sync implementation. Do not build cloud sync now or imply timestamps alone resolve conflicts. Preserve separation between shared learning data and device-specific UI preferences. Credentials are never part of library exports.

### Future feature seams and data planning

| Later feature | Boundary to plan | First-build action |
| --- | --- | --- |
| Source-based generation and RAG | Resource ingestion, retrieval, evidence references, generation | Store optional source references; document stable resource/page/section/version identifiers |
| Combined tests and AI marking | Assessment service and assessment-attempt records | Keep card recall events distinct from future application/understanding evidence |
| AI tutor and managed/BYOK providers | Task-oriented AI adapter, capability discovery, provider routing | Document contract direction; do not embed a provider client in card/editor views |
| Speech recognition | Audio/transcription adapter | Keep future transcript, confidence/ambiguity, and capture metadata distinct from answer content |
| Speech synthesis | Separate voice-output adapter | Avoid coupling voice choice to the language-model provider |
| Local/cloud routing | Enforced privacy policy and capability selection | Reserve a policy boundary; no silent cloud fallback |
| MCP | Authenticated adapter to application use cases | Make useful operations reusable without a visible screen; no separate MCP-only learning logic |
| Paid managed services and one-time BYOK | Entitlement and metering services | Keep feature access separate from provider credentials and domain learning rules |
| Additional card formats | Versioned note/card-content representation and rendering boundary | Implement basic/cloze cleanly; unknown formats must be preserved or rejected explicitly on import |
| Cross-device sync | Repository-backed sync adapter and conflict policies | Stable IDs, migrations, idempotency, and portable export now |

Do not create fake AI services, unused database tables for every roadmap idea, or nonfunctional paid buttons. Document future contracts and introduce only the minimal types needed by current functionality. Keep future additions possible without making today's app depend on their availability.

### Grounding, grading, and cost policies stay outside vendor adapters

When AI is added, all providers must pass through the same evidence/abstention policy. Source excerpts and source identifiers travel with generated questions, rubrics, and results. Supported grades and ungraded outcomes (insufficient evidence, uncertain transcript, conflicting sources, unavailable service) need distinct representations. A provider returning a number must not automatically update scheduling or mastery.

Raw assessment evidence, derived mastery estimates, and scheduling decisions must remain separate so each can evolve independently. For future voices, a premium speech provider should be replaceable independently of transcription and grading. Preserve the cost model from the original plan: local features free, Engram-funded ongoing services paid, BYOK setup a one-time unlock with provider usage billed to the user. Entitlements govern optional services, not the learner's ownership of their stored cards or access to core review.

### Modularity verification and deliverables

Before describing the architecture as modular, demonstrate:

- Switching between Warm and Neutral themes changes the whole interface without modifying feature code; the current draft/review survives.
- The same review use case runs with the real scheduler and an injected deterministic test adapter, with no UI changes.
- Repository contract tests exercise both the production persistence adapter and a test implementation, including transaction failure behaviour; mocks alone do not verify durable storage.
- Core/application logic can be tested independently of SwiftUI and provider SDKs.
- Export/import and supported schema migrations retain card IDs, schedules, and review evidence.
- Failures at adapter boundaries produce meaningful recoverable results without corrupting learning state.

Leave `ARCHITECTURE.md` with the dependency map, public contracts, composition points, and instructions for adding a theme, replacing the scheduler, changing persistence, and later connecting AI/voice/MCP. Record the selected concrete implementations, versions, assumptions, and migrations required to replace them. Keep it concise enough to maintain alongside the source.

## 7. Suggested implementation order

1. Inspect the repository, applicable instructions, runtime availability, and current files. Perform the required Anki source reconnaissance and create the scoped feature/architecture map before committing to data and scheduler designs.
2. Verify Mac/Xcode availability, establish the shared native project and platform shells, and document minimum OS versions. Create a small component study across compact, intermediate, and expansive layouts before multiplying screens.
3. Establish the core/application contracts and composition root; implement domain models, durable persistence, and the scheduler adapter. Verify the boundaries with focused contract tests.
4. Build deck management and the basic/cloze editor.
5. Implement the complete review loop, persistence, undo, and completion state.
6. Apply the shared theme system, Warm and Neutral presets, Liquid Glass policy, and motion across the real screens. Verify theme changes preserve session state.
7. Implement and verify Anki import/export through the format adapter, complete native backup/restore, search, suspension, and useful settings. Inspect migration fixtures early during data-model work.
8. Verify the acceptance checks below and fix failures that affect the core experience.
9. Leave launch instructions and a concise implementation handoff with known limitations.

Work toward a complete vertical flow early. Do not spend the whole run on the dashboard while leaving review and persistence unfinished. If time is limited, protect data integrity and the core study flow, then report unfinished secondary features explicitly.

## 8. Acceptance checks

The build is ready for user review when these checks have been exercised:

- A clean launch shows a usable empty state and no fabricated progress.
- A user can create a deck and basic/cloze notes, edit them, and find them again after restarting.
- Cloze cards hide and reveal the correct text; generated siblings retain independent review state.
- Due queues and counts agree with persisted scheduling data.
- All four grades update the schedule and create exactly one event per accepted action.
- Undo restores the prior review/scheduling state.
- Suspended cards do not appear in ordinary due reviews.
- Rapid clicks and keyboard inputs do not skip or double-grade cards.
- Long content, empty answers, invalid cloze syntax, and deleted content are handled sensibly.
- Anki import/export passes the interoperability fixtures and disposable-profile round-trip checks; complete native backups restore media and history. Malformed imports do not damage the library.
- Core persistence and review work under the documented offline conditions.
- Verify iPhone portrait/landscape, iPad full and narrow windows, and Mac resizable windows; include light/dark and enlarged-text variants. Preserve session and draft state across resizing.
- Keyboard navigation, visible focus, reduced motion, and readable contrast work.
- Compile the iOS/iPadOS and macOS destinations and exercise the primary workflow on iPhone and iPad simulators/devices and the native Mac app. Record actual devices/OS versions. Any unavailable native check remains explicitly pending.

Use meaningful automated tests for scheduling transitions, persistence/restore, cloze generation, and duplicate-grade prevention. Include an end-to-end create → study → reload scenario where feasible. Report what was actually tested and distinguish it from unverified behaviour.

## 9. Deliverables for the future run

- Shared native Apple source code and reproducible project configuration in this project, with platform-specific shells where needed.
- README with prerequisites, exact launch/build commands, storage behaviour, and backup instructions.
- ANKI-SOURCE-REVIEW.md with pinned source references, architecture findings, compatibility notes, and a scoped feature matrix.
- Focused tests and their results, including the modularity checks in section 6A.
- ARCHITECTURE.md documenting dependency boundaries and replacement/migration paths, plus a short build handoff of completed features, known issues, and deferred work.
- A visual handoff/contact sheet covering Today, Library, Review (question and answer), Editor, and Completion across iPhone, iPad, and Mac. Clearly distinguish runtime captures from design mockups. Include light/dark and key accessibility states.
- Clear disclosure of any platform assumption, scheduling limitation, or incomplete acceptance check.

Keep this first version local unless the user separately requests publication. Never claim that a preview has been deployed, data is synced, or functionality has been verified unless it actually has.

## 10. Suggested prompt to start the later run

> Implement the first Engram build described in ENGRAM-FIRST-BUILD.md. Follow its native iPhone/iPad/Mac scope, detailed visual specification, motion choreography, modular architecture requirements, and acceptance checks. Study the official ankitects/anki source as required and map its features to this brief. Check Mac/Xcode access first; if unavailable, continue useful native source/design work and explicitly report all unverified Apple builds instead of substituting a web product. Work through the complete flashcard workflow and verify it. Leave launch instructions, a working local preview if possible, and an honest handoff of completed and unfinished work. Defer the AI and MCP roadmap until the foundation is working.




