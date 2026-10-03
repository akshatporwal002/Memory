# Review layout, themes and memory growth

Planned 3 October 2026 against `akshat/dev` at `262f819`. Review layout, quiet header and shared theme implementation are complete. Validation and deployment evidence is recorded in `REVIEW-LAYOUT-THEMES-VALIDATION.md`. Memory growth remains a separate interactive design preview.

## 1. Review composition — first priority

- In portrait, centre a narrower answer column within the screen while keeping letters and answer text left aligned. Start with approximately 32–40 pt outer margins on ordinary iPhones, constrained by available width and text size. Centre the group vertically below the question, moving it up from the current low placement. Do not centre individual multiline answers.
- Keep text-only italic options, restrained dividers, orange selection, green correct answers, red incorrect answers, and inline explanation beneath the correct answer. Entire rows remain tappable with at least 44 pt targets. Preserve select-then-confirm and canonical shuffled choice identities.
- Replace the current fixed proportional top padding with content-aware composition. Short content gets breathing room; long prompts/options take the space they require. Never truncate, shrink text to fit, or enforce a lower-half boundary when content exceeds it.
- For a wide, shallow viewport, place the question on the left and options on the right, with a quiet gutter and no surrounding boxes. The current 680 pt single-column cap must not constrain the entire split layout. Each pane can scroll if necessary; feedback remains with its answer.
- Use available geometry and text size to choose layout, rather than orientation alone. Narrow iPad windows and large accessibility text may use one column even in landscape. Preserve selection, shuffled order and assessment through rotation.
- Retain theme typography, using the reading/body role for long questions. Keep question-first accessibility reading order in both arrangements.

## 2. Quiet review header

- Show the deck name as small italic secondary text, with truncation only for this metadata and its full name available to accessibility.
- Retain Back and one restrained ellipsis control. Move voice start/stop into the existing review-options sheet, where model preparation and voice settings already live.
- When voice is active, show a small state indicator so its microphone use remains apparent. Keep stopping voice easy through the menu; expose an accessible stop action.
- Avoid changing unrelated deck-page typography or hiding necessary recording/error states.

## 3. Theme compatibility — parallel workstream

- Preserve Warm as the default. Add a colour-only Monochrome theme with a pure white light canvas and pure black dark canvas. Keep the existing System / Light / Dark appearance preference independent of theme and preserve the editorial typography.
- Follow-up: invert the open assistant panel in Mono: black with white text over a white page, white with dark text over a black page. Keep the closed navigation dock matched to the page. Rich content and controls inherit the panel's opposite appearance.
- Define every app-owned colour in DesignSystem. Add explicit inline tokens for success, incorrect, selected-answer, missing-content, charts, assistant tint and decorative growth where existing tokens have incompatible meanings. In particular, `goodInk` is text on a filled grade button and is not an inline green-text token.
- Replace semantic raw RGB/named colours in feature views, including the current MCQ `correctInk`. Review Today, Library, decks, study, chat, grading, settings, account/sharing, PDF/Markdown viewers and action history.
- Pass theme colours into bundled math/diagram rendering. Theme changes must refresh cached rich blocks without losing conversation, draft, session or scroll state.
- Preserve original media and necessary provider branding. Hard-coded token definitions are expected; app-owned feature colours should reference those definitions. System controls must respect the chosen app appearance.
- Check readable text, selected/disabled controls, graph series, glass, keyboard-adjacent surfaces, errors and feedback in all themes. Colour must supplement icons/state labels rather than carry the only meaning.

Luna's read-only audit identified the initial remediation sites:

- `MultipleChoiceReviewView.swift` and `DeckOverviewView.swift`: custom RGB correct-answer ink; replace with the new inline success token.
- `RichContentView.swift`: code/quotation surfaces use system colours; math HTML uses scheme-only `#eee`/`#222`, and Mermaid does not receive the selected palette. Pass shared tokens into both native and web rendering.
- `LibraryLandingView.swift`, `VoiceModeSettings.swift`, `SettingsDetailPages.swift`: inspect remaining system foreground styles against custom palettes.
- `ActivityView.swift` and `DeckMemoryPanel.swift`: mostly token-based already; verify axis defaults and curve contrast on white/black.
- `ContextualAssistant.swift`: verify material/opaque fallbacks for Reduce Transparency across themes. Preserve system glass where appropriate rather than painting every surface pure black/white.

## 4. Edge-case acceptance matrix

Create deterministic DEBUG fixtures independent of live AI and test:

| Dimension | Cases |
| --- | --- |
| Content | Short question; long paragraph question; multiline choices; long explanation; long unbroken term; punctuation/Unicode; 2, 4 and 8 choices |
| Answer state | Unselected; selected; correct; incorrect; correct choice first/middle/last; undo; Next; resumed question |
| Geometry | Small iPhone; current iPhone; portrait/landscape; iPad; narrow split window; keyboard/composer open |
| Accessibility | Default and largest text; VoiceOver order/confirmation; increased contrast; reduced motion/transparency |
| Themes | Warm light/dark; Neutral light/dark; Monochrome white/black; live switching during an active review |
| Continuity | Rotate before/after grading; preserve canonical letters; voice selection matches visible letters; repeated taps commit once |

Use focused interaction tests plus screenshot inspection: screenshots alone cannot verify grading or touch behaviour. Require readable content, reachable confirmation/Next, no clipping or assistant overlap, and no review-state reset. Save captures by view/state under `current_ui`, retaining only current and previous versions. This covers representative edge cases, not every possible document or device combination.

## 5. Optional memory-growth artwork — later prototype

Recommended first placement: a subtle brain-shaped vine illustration on the deck overview, followed by one short growth transition on session completion when memory strength improves. Keep the active question background clear. A per-card post-answer flourish can be evaluated later after the deck version is reviewed.

- Use a deterministic vector brain outline with branching paths and leaves. Native SwiftUI paths/Canvas can reveal branches progressively and adapt to themes, resolution and fill state. Provide an accessible textual description separately from the decorative drawing.
- Image generation may help explore the art direction; the shipped animation should use controllable vectors. A rendered video would require additional assets to support partial growth, theme changes and interruption.
- Growth must reflect accumulated scheduling evidence, not merely a correct tap or the user's desired-retention setting. Prototype an aggregate of FSRS-estimated recall 30 days after each reviewed card's last review; clearly label it an estimate, exclude new/unavailable cards, and show coverage separately. Confirm this mapping visually before connecting it to real progress. It is distinct from the current live forgetting curve.
- A lapse may reduce estimated strength without a dramatic punitive withering animation. Avoid continual decay or looping while the user is reading.
- Add an Appearance toggle, initially off until the user elects to try the preview. Off hides the artwork and stops decorative animation work. Reduce Motion uses a static final state or a short fade. Backgrounding stops animation; advancing never waits for it. Undo/retry must not replay earned growth incorrectly.
- Aim for a brief 0.6–1.0 second transition, no autoplay loop, no layout movement, and no interference with touches. Profile on the actual phone before enabling it broadly.

Apple references: [Canvas](https://developer.apple.com/documentation/swiftui/canvas) and [Motion guidance](https://developer.apple.com/design/human-interface-guidelines/motion).

## Delivery order

1. Adaptive portrait/landscape review and quieter header.
2. Theme audit/remediation and Monochrome previews in parallel, then integrate semantic colours with the review work.
3. Run the fixture matrix, inspect captures, build/install on the phone and commit/push on `akshat/dev`.
4. Prototype the optional vector growth artwork separately, review its aesthetic and metric, then integrate only after the core review work passes.

No additional user decision is needed for the recommended review layout. The growth artwork remains a lower-priority proposal, with its metric and visual treatment subject to prototype review.
