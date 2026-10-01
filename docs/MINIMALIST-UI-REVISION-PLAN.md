# Minimalist UI revision

Status: implemented, reviewed and pushed on `akshat/minimalist-ui-revision`, based on `a17776a`. Continue the native SwiftUI app; the React Native migration discussion is set aside.

Active-goal cleanup requirement: keep Windows awake with a temporary PowerShell `SetThreadExecutionState` helper during work (display may turn off). Stop the helper and restore the normal sleep behavior before ending the task, including a blocked/error ending. Helper automatically expires after five hours. Do not change saved Windows power-plan settings.

## Delivery sequence and ownership

1. Restore Today from `995e1b2`, the last version with the large olive-green study area. Preserve current model/service calls and theme support.
2. Replace the deck-scoped list with a dedicated reading-friendly overview. Chart, target control, study action and two content destinations share the page canvas. The general library and its gallery/list preferences remain intact.
3. Add a Questions destination rendering all deck notes, including MCQ, ordinary questions and imported formatted/cloze content. Keep current editing, suspend/resume and delete pathways available. Notes becomes a writing-only view of the same notebook document; filtering display must never remove question blocks from its saved draft.
4. Rebuild the assistant chrome around a single bottom dock. On narrow iPhone layouts, navigation and the assistant entry share the bottom row. In pushed workflows retain a compact assistant affordance without restoring hidden study tabs. The open panel follows the keyboard safe area and must not cover review submission controls when closed.
5. Commit and push a buildable candidate. Ask the existing Mac Codex chat to fetch this exact revision in an isolated worktree, build, traverse the simulator and send findings back. Windows is the implementation owner; Mac does not edit source concurrently.
6. Fix actionable findings as one batch, commit/push and ask the Mac to recheck affected flows. Repeat only for a remaining reproducible defect or unmet user requirement. Stop after acceptance; do not consume the five-hour window with cosmetic churn. Final report includes revision, screenshots, validation and real limitations.

## Files and behavioral boundaries

- `LibraryScreens.swift`: Today recovery and routing deck-scoped screens away from the old nested List.
- New deck overview/Questions views in `Sources/Features`: shared page padding, readable content width, top-right deck menu, distinct Questions/Notes routes.
- `DeckMemoryPanel.swift`: remove surface wrapper, keep scheduler estimates and retention editing unchanged. Make asynchronous loading refresh even after initial failure/empty state and after library changes.
- `NotebookView.swift`: reading/writing-only mode, compact active-title contents rail and safe draft preservation. Existing combined editor remains available for legacy edit paths.
- `EngramRootView.swift`, `ContextualAssistant.swift`, `EngramModel.swift`, shared layout: single assistant state and navigation dock, context-aware Questions/Notes identity, keyboard-safe geometry, native glass availability guards and material/opaque fallbacks.
- Existing learning/scheduling/import/authentication implementations are not redesigned. No study data schema migration and no credentials in commits. Commit all changes belonging to this task; keep unrelated SSH setup logs/scripts, local archives and pre-existing scratch assets outside the branch commits.

## Acceptance cases for the review loop

| Flow | Required evidence |
| --- | --- |
| Today with decks / empty / paused review | Original green study area, functional Start/Resume and deck navigation; no recent notebook-led replacement |
| Deck overview | Single canvas, no white panel nesting, target settings and chart still work; gear actions and Questions/Notes are findable |
| Questions | Numbered bold prompt; each MCQ choice occupies its own line; smaller italic options, green correct option and answer/explanation; long content and normal questions readable |
| Notes | Only prose in reading mode; short top-right dash rail with orange active title in-place, no vertical rotated title or full-height strip; tap/scroll synchronization; edits preserve all cards |
| AI closed / compose / response / expanded | Small glass entry next to bottom tabs, tinted distinct panel, smooth shared-shape morph and growth, composer meets keyboard top, close/collapse preserve conversation |
| Navigation and accessibility | All three tabs work, back navigation works, editing and deck actions reachable; larger text, dark theme and Reduce Motion usable |
| Build and regression | iPhone simulator build and focused UI traversal; existing domain tests appropriate to touched behavior pass; no real ChatGPT credentials required for UI fixtures |

The Mac reviewer must label any mocked response used for screenshots as test-only. Do not present simulated AI requests as successful live service verification.

## Design direction

One coherent, premium interface: consistent typography, spacing, surfaces, navigation and motion. Minimalism means clear hierarchy and deliberate content, not missing functionality. Reuse the existing theme and native glass treatments. Avoid nested cards, mismatched white panels and unnecessary borders.

Contents reference clarified by the user during implementation: a tightly grouped stack of short dashes like the attached conversation-timeline image. The active dash is replaced by the orange section heading itself, rather than a dash plus title or a popout box. Keep it at the top right; the full Contents menu is an accessible alternative, separate from the compact rail.

## Implementation checklist

- [x] Today: recover the earlier layout and prominent large green study area from Git history. Restore its hierarchy and working review/resume actions; replace the recently introduced notebook-led Today composition.
- [x] Deck detail: remove the contrasting white wrapper around Memory Outlook and integrate its chart and retention controls directly into the page. Preserve above/below-target counts and per-deck retention settings.
- [x] Deck navigation: replace Open notebook with two equal Questions and Notes actions, side by side at normal phone sizes and stacked when text size requires it. Move the inline question/note listing into these destinations so deck detail stays focused.
- [x] Deck actions: place a gear menu in the top-right toolbar instead of the plus. Keep adding questions, editing, renaming and other existing actions accessible through appropriate menu entries.
- [x] Questions: render numbered, bold question text; separate A), B), C) options on individual lines, using smaller italic text. Highlight the correct option in green. Place the explanation with the correct answer, with a green answer reference and legible explanation text. Support non-MCQ content and existing edit actions.
- [x] Notes: show note content with a compact contents rail at the top right. Inactive sections are closely spaced dashes; only the current section exposes its title, in orange. Tapping a dash navigates and scrolling updates the active section. Do not stretch the rail across the page; maintain usable hit targets without enlarging its visual footprint.
- [x] AI entry: move the small assistant control beside the bottom navigation bar and give it the same native glass styling. Keep it available in relevant study, deck creation, question and note workflows.
- [x] AI presentation: smoothly morph from the entry into a compact composer, then grow into a response panel with an optional expansion control. Position the composer directly above the keyboard when typing. Use a distinct theme-compatible tinted surface so the assistant is visibly separate from content; support dismissal, interrupted transitions and Reduce Motion.
- [x] Verify content, navigation, keyboard layout, light/dark themes, larger text and existing study functionality. Build for iPhone before the Mac design review.

## Mac Codex review brief

After implementation, find the existing Memory chat on the connected Mac and send it this checklist and the implementation revision. Explicitly authorize that chat to review and fix these UI changes. Preserve unrelated work in the Mac checkout by using an isolated checkout if needed.

Ask it to act as a senior product designer responsible for a premium app at a multimillion-dollar company. Explain the requested behavior from this document; do not require the absent user to repeat the brief. Prefer the iOS simulator, seed representative AWS content, traverse each affected screen and capture before/after screenshots. Use Xcode UI/computer use only if needed for preview or diagnosis.

Review Today, deck detail/chart, Questions, Notes/contents rail and AI closed/composer/response/expanded/keyboard states. Evaluate them as one visual system. Record concrete findings against the checklist, fix issues, rebuild and revisit the affected flows. Distinguish visual simulator verification from features that still require physical-device testing. Retrieve and inspect the report and screenshots, resolve remaining findings, and summarize the completed work with any actual blockers.

## Unattended prerequisites

No additional design answers are required. Keep the Mac powered, awake, connected and logged in. Keep its login keychain unlocked for signing. If device installation is requested afterward, the iPhone must also be reachable and available for launch. A macOS authorization prompt may still require the user; report that exact blocker if it occurs.

## Completion

The Mac accepted source revision `fddc39a` after four iPhone tests and one iPad test passed with zero failures. All eight initial findings were corrected. See [validation](MINIMALIST-UI-VALIDATION.md) for screenshot evidence and coverage limits. The Windows keep-awake helper has exited; normal sleep behavior is restored.

