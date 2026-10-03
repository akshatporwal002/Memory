# Adaptive review and themes — 3 October 2026

Branch: `akshat/dev`; baseline `262f819`. The Warm appearance remains the default.

## Delivered

- Portrait MCQs use a centred, narrower group with left-aligned italic answer text. Long content scrolls without truncation. Landscape uses question/answer panes with independent scrolling; accessibility text uses a single readable column.
- The phone keeps one navigation stack across rotation. Selection, canonical shuffled choice identity and assessment survive rotation and theme changes.
- Deck metadata is smaller and italic. Voice controls live in Review options, with an active microphone indicator and accessible stop action.
- Engram Mono supplies pure white/light and black/dark canvases, independently of System/Light/Dark appearance. Shared semantic colours now cover answer selection, success, missing concepts, charts, rich notes and action feedback. Bundled math and Mermaid receive the same palette; the diagram bundle was regenerated from its source.
- Manual MCQs support two through eight choices, including spoken G/H aliases. PDF generation keeps its existing two-to-six-choice contract.
- `design/previews/memory-growth/index.html` is an offline vector prototype with theme, visibility and animation controls. Its slider is illustrative; it is not connected to real retention and adds no animation to active study.

## Evidence and limits

The focused Swift suite passed 22 tests covering theme contrast, canonical shuffled answers, eight-choice parsing/voice aliases and existing PDF generation constraints. The first simulator suite passed all 15 tests. It revealed excessive rotation settling, which was corrected by retaining the phone navigation stack.

The expanded suite adds independent landscape scrolling, accessibility landscape fallback and changing theme during an unfinished answer. A parent accessibility identifier initially masked both scroll-pane identifiers; it was removed before the focused recheck. The picker test now scrolls its sheet to the appearance section. Long-answer tests use the visible portion of the row for touch coordinates and scroll towards the target, avoiding XCTest activation-point failures on oversized/offscreen elements.

All 18 distinct simulator scenarios have passed across the regression and focused runs. Final fresh-build checks passed rotation/selection/feedback, live theme switching and independent scrolling of an eight-choice long question, including reachable inline feedback. The latest rotation test completed in about 17 seconds rather than the initial 313 seconds. Results on the Mac: `/tmp/engram-adaptive-review-continuity.xcresult`, `/tmp/engram-adaptive-screen-tests.xcresult`, and `/tmp/engram-adaptive-long-confirmed.xcresult`. The first two contain the documented test-harness failures; the final long-answer recheck passes. A fresh DerivedData directory was used after an incremental run executed an obsolete test bundle. Screen-level captures replace application-only captures, which cropped landscape images.

The signed app was installed and launched on the paired iPhone (`13777C05-01CF-5583-AAD8-65CB3653FA07`); `/tmp/engram-dev-phone.status` reports `LAUNCHED`. Later edits only adjust test capture/scrolling, not the installed application source. Smaller-phone and iPad layout checks remain pending for this revision.

Screenshots are stored by view/state beneath `current_ui`, retaining only current and previous versions. Screenshot inspection supplements interaction assertions; neither establishes live transcription quality or live AI behavior. Tests use local fixtures and cover representative cases, not every device/content combination. Growth metric integration, VoiceOver traversal, narrow iPad multitasking and a full live voice session remain separate checks.
