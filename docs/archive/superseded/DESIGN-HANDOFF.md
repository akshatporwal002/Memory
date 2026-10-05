# Engram design handoff

> Archived on 5 October 2026 from main `381c917`. This is historical context, not current implementation guidance. Outstanding work is tracked in [the backlog](../../BACKLOG.md); newer requirements take precedence.

Status: native SwiftUI source and design mockups. Apple compilation, native previews, accessibility runtime behavior and optical glass rendering remain **unverified**. The HTML is a design review artifact, not the application. Its example counts and intervals are illustrative.

## Intent and reference decisions

The learner should be able to see what is ready, study one readable question, reveal deliberately, rate with stable controls, and know the review has been saved. The authoritative first-build brief governs the scope. All seven supplied PNG references were viewed in this run.

| Reference | Applied interpretation |
| --- | --- |
| 01 progress path | One quiet completion marker; no invented retention plot |
| 02 editorial palette | Olive anchor with ivory typography, amber limited to emphasis |
| 03 layered cards | Opaque matte content with shallow soft depth; no overlapping interactive cards |
| 04 light/dark depth | Warm charcoal canvas and lifted dark surfaces |
| 05 calendar | Quiet information density and explicit selected state; no decorative calendar data |
| 06 information cards | Editorial heading, line symbols, readable sans-serif explanations |
| 07 quiet reading | Breathing room for short prompts; answers left aligned |

Warm uses native system serif display roles with neutral sans-serif reading text. Neutral is a slate/blue-gray palette with entirely sans-serif headings, demonstrating that theme replacement changes both color and typography. No font binaries, external images, third-party UI code or paid assets were incorporated. Native fonts use the operating system; HTML Georgia/system-ui are approximations only.

## Public integration contract

The DesignSystem target depends only on Foundation and, when available, SwiftUI. It owns no storage, grading, navigation selection, editor draft or review session state.

```swift
import DesignSystem

@Environment(\.engramTheme) private var theme
@Environment(\.colorScheme) private var scheme
@Environment(\.accessibilityReduceMotion) private var reduceMotion

// Persist selectedTheme and appearance separately at the application composition root.
// Update the environment in place. Never put .id(selectedTheme) on the feature root.
RootView()
    .environment(\.engramTheme, selectedTheme)
    .preferredColorScheme(appearance.colorScheme)

let palette = theme.palette(for: scheme)
Text("Today").font(theme.font(.hero)).foregroundStyle(palette.primaryText)
Button("Start review", action: start).buttonStyle(EngramButtonStyle(.primary))
```

- `EngramTheme`: `warm`, `neutral`; RawRepresentable/Codable/CaseIterable/Identifiable/Sendable, `title`, `definitionVersion = 1`. `colors(dark:)` returns raw sRGB values; `palette(for:)` returns SwiftUI colors.
- `EngramAppearance`: `system`, `light`, `dark`; `colorScheme` returns `nil`, `.light`, `.dark`. Persistence belongs to application preferences.
- Palette: `canvas`, `surface`, `elevated`, `primaryText`, `secondaryText`, `anchor`, `onAnchor`, `accent`, `accentInk`, `hairline`, `controlBorder`, `selection`; `againFill/Ink`, `hardFill/Ink`, `goodFill/Ink`, `easyFill/Ink`.
- Typography: `theme.font(.hero/.title/.section/.prompt/.body/.control/.metadata)` uses system semantic text styles so it participates in text enlargement. Feature code must use `.body` for long prompts/answers and `.prompt` only for short prompts.
- Geometry: `EngramSpacing` (4/8/12/16/20/24/32/48/64), `EngramShape` (14/22/28 continuous corners, 44 minimum hit target, 680 preferred reading width). Treat reading width as a preference; do not clip enlarged content.
- Surface modifiers: `.engramCanvas()`, `.engramSurface(padding:)`. Reading surfaces are fully opaque. Increased contrast strengthens the surface border.
- Controls: `EngramButtonStyle(.primary/.secondary/.destructive)`, `EngramActionButton("Save", busy: saving, action:)`, `EngramGradeButton(label:interval:tone:action:)`, `EngramTag(text:selected:)`, `EngramInlineError(message:)`, `EngramEmptyState(title:message:symbol:)`.
- Grades: tones `.again/.hard/.good/.easy` are presentation values, independent of scheduler rating types. The caller provides exact interval text from scheduler previews. The grade control combines label + interval for VoiceOver. Feature layout must use 2×2 on compact widths, four across when labels fit, one column at large accessibility sizes.
- Empty states supply meaning; the feature places a working immediate action beside/below the component. Tags are display components, not hidden buttons. A selectable tag must be wrapped in a labelled button with at least a 44 pt hit region.
- Loading: the action button preserves its title and disables repeated submissions. The use case must still enforce idempotency and commit before advancing; a disabled button is not a data-integrity mechanism.

To add a theme: add a Codable enum case and four required dimensions (light/dark colors, typography); regenerate contrast evidence; persist stable identifiers; preserve a fallback for unknown saved IDs at the preferences boundary. Built-in theme versioning must never migrate learning records. To replace geometry or motion, modify the centralized tokens, then check all three size families and enlarged text.

## Navigation, motion and accessibility

Platform shells own native `TabView`, `NavigationStack`, `NavigationSplitView`, toolbars and OS availability. Use native Liquid Glass on supported OS releases. `EngramNavigationPolicy` defines a regular-material fallback and chooses opaque chrome when Reduce Transparency or Increase Contrast is enabled. It cannot override Apple's system glass optics. Use palette accentInk for legible selection tint, not decorative taupe. Keep flashcards and grading surfaces opaque.

`EngramMotion.feedback/reveal/navigation/completion(reduceMotion:)` provides 120/200/280/360 ms easing, reduced to short 120 ms feedback/fades. `contentTransition(reduceMotion:)` removes its 12 pt offset when reduced. Button scale feedback is removed for Reduce Motion. No spring overshoot, indefinite decoration or card flip is introduced. Persist reviews independently of animation completion. Use the motion token inside feature-owned `withAnimation` after durable state succeeds, never to postpone commit.

System text styles, wrapping, minimum 44 pt buttons, explicit grade labels and intervals, selected-tag checkmarks, errors with symbols/text, opaque study surfaces and native keyboard semantics provide the foundation. Keyboard focus uses a separate external ring so it has contrast against the surrounding reading surface. This requires native verification; no claim of VoiceOver conformance is made from source inspection. The feature must move or announce focus on reveal, preserve scroll position for long answers, hide decorative images from accessibility, keep error messages adjacent to fields, and never let the keyboard cover Save. No component clamps Dynamic Type or uses minimumScaleFactor to make content fit.

## Mockup deliverable

Open `design/previews/design-preview.html` directly in a regular browser. It contains Today, Library, Review question, Review answer, Editor and Completion; choose iPhone, iPad or Mac layout and any Warm/Neutral light/dark preset. The enlarged-text control is a reflow design study, not native Dynamic Type emulation. Empty library, editor error and keyboard focus/reduced-effects guidance are shown separately. Native navigation optics are deliberately not simulated.

This artifact is entirely local with no CDN, telemetry, font downloads or backend. Controls at the top only change the mockup presentation. Illustrated application actions are noninteractive. The served mockup was visually inspected in the in-app browser in phone Warm light, Mac Warm dark and iPad Neutral enlarged-text states. The first phone capture showed the Library's last card partially obscured by tabs; the generator now reserves 108 pixels below browsing content and the corrected capture shows the complete last row above navigation. Saved screenshots are in `design/previews/captures/` and named `*-mockup.png`. Temporary responsive viewport overrides were reset. There are no native screenshots in this deliverable.

## Verification evidence and remaining acceptance checks

Run from repository root with Node.js:

```powershell
node design/previews/build-previews.cjs
```

The generator reads **actual native Swift color declarations**, checks their opaque sRGB contrast, and creates the HTML, design-tokens.json and contrast-results.json. Result in this run: **72 pairings pass**, minimum ordinary-text ratio **5.289:1**. Every theme checks primary/secondary/accent text on canvas/surface/elevated; selection text; anchor text; each grade label; essential borders on reading backgrounds. Thresholds: 4.5:1 ordinary text, 3:1 essential control boundaries. Decorative hairlines and disabled controls are excluded, as are OS-generated glass optics. This evidence proves token pairings, not all rendered application pairings.

Remaining Apple checks, to be run against the integrated application:

1. Compile and render iPhone/iPad/Mac with the selected stable Xcode SDK; capture all required screens on documented OS/device sizes.
2. Verify theme/appearance switching during unsaved editing and revealed review preserves model, selection and focus; resize iPad and Mac windows during both states.
3. Verify Dynamic Type accessibility sizes, long translated labels, long deck names, multi-paragraph answers, 100-deck scrolling, landscape and keyboard-safe layout.
4. Test VoiceOver reading order, reveal announcement, grade label + interval, validation focus, empty-state action and no duplicate decorative accessibility elements.
5. Test native focus traversal and shortcuts (Space, 1–4, Escape, Undo) with text-field focus; ensure focus rings stay visible at all actual action backgrounds.
6. Check standard native glass on light/olive/dark backdrops, supported OS fallback, Reduce Transparency, Increase Contrast, Reduce Motion toggled live, and access to the last list item above safe areas.
7. Review rapidly and slowly with long answers. Confirm no double-grading, no transition-driven persistence, no forced waits and no inaccessible moving controls. Measure frame performance before making a frame-rate claim.

Known design limitations: no native runtime evidence on this Windows host; the parent's mockup screenshot inspection does not establish native layout behavior; mockup samples are not evidence of real activity. Features now implement persisted device preferences, model-owned drafts and sessions, and review reveal accessibility focus, but these behaviors still require Apple runtime verification.
