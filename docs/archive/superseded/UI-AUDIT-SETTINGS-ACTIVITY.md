> Historical local document preserved on 5 October 2026. Implementation and validation claims below describe the earlier local work and have not been reverified against current main.

> Archived on 5 October 2026 from main `381c917`. This is historical context, not current implementation guidance. Outstanding work is tracked in [the backlog](../../BACKLOG.md); newer requirements take precedence.

# UI audit — Settings and Activity

Audited 1 October 2026 using the UI router and Impeccable native audit guidance.
Scope: Settings, its detail pages, voice diagnostics, Activity and its chart/history pages.
Visual authority: `docs/DESIGN-HANDOFF.md`, `EngramTheme.swift` and existing native components.

## Platform conformance

Pass for the inspected surfaces: native navigation stacks, grouped lists, pickers, switches,
steppers, alerts, SF Symbols and Swift Charts are retained. Root pages use large titles;
Settings destinations and activity history use inline titles. No custom back gesture or
web navigation was introduced. This is a scoped audit, not an accessibility certification.

## Health score

These are heuristic scores based on source and rendered evidence, not measured performance scores.

| Dimension | Score | Evidence / limitation |
| --- | --- | --- |
| Accessibility | 3/4 | Larger text reflows; chart controls become menus; 44-point date arrows; chart labels. Full VoiceOver traversal remains a hardware check. |
| Performance | 3/4 | Native virtualized lists and background model-size enumeration. Large-history aggregation needs profiling. |
| Appearance & theming | 4/4 | Shared palette for canvas, sections, text, icons, errors, chart marks and axes; four theme/appearance variants. |
| Platform conformance | 4/4 | Native controls and navigation; inline detail titles; ordinary native transitions. |
| Adaptivity | 3/4 | iPhone dark/large-text and iPad split-view evidence; content width capped by the shared reading-width token. Mac window resizing and rotation remain manual checks. |
| Total | 17/20 | Good; remaining work is focused runtime verification. |

## Findings and fixes

- **[P1] Theme drift — fixed.** `Sources/Features/SettingsView.swift:16`,
  `Sources/Features/ActivityView.swift:18`. System blue and unrelated icon colors made
  utilities look disconnected from the warm/slate app. The shared list style now uses
  the selected theme's canvas, foreground and tint. `Sources/DesignSystem/EngramGroupedList.swift:4`
  supplies themed row surfaces, separators, section labels and footers. Icon tiles use
  selection/primary-text tokens, and Activity's headline uses the theme's display font.
  Category: Theming. Refinement route: `$impeccable colorize` / `$impeccable typeset`.
- **[P1] Floating chart marks — fixed.** `Sources/Features/ActivityView.swift:58`.
  Ranged marks with only a y position produced short horizontal marks. Bars now have
  explicit zero/count bounds and actual calendar-bin widths. Line mode uses linear
  segments and visible points, avoiding smoothed values that were never recorded.
  Category: Conformance / data clarity. Refinement route: `$impeccable harden`.
- **[P2] Small date-arrow hit regions — fixed.** `Sources/Features/ActivityView.swift:39`.
  32-point widths made navigation harder to tap. Both dimensions now use the shared
  44-point touch-target token. Category: Accessibility. Route: `$impeccable adapt`.
- **[P2] Enlarged settings summaries and icons — fixed.** `Sources/Features/SettingsView.swift:103`.
  Summaries previously truncated, and enlarged decorative glyphs exceeded their tiles.
  Accessibility text now places the summary below the title; only hidden decorative
  glyphs keep their normal size. Reading text remains fully scalable. Category:
  Accessibility / Adaptivity. Route: `$impeccable adapt`.
- **[P2] Chart controls at accessibility sizes — fixed.** `Sources/Features/ActivityView.swift:54`.
  Both period and chart-style controls switch to native menus, and the plot gains height
  for larger axis labels. Charts remain selectable in both modes. Category: Accessibility.
  Route: `$impeccable adapt`.
- **[P2] Potential large-library refresh cost — open.** `Sources/Features/ActivityView.swift:148`
  invokes report aggregation in the view task; `Sources/StudyApplication/ActivityWindow.swift:46`
  filters reviews per bucket. Cost grows with review history and bin count. No jank was
  demonstrated with the small UI fixture. Profile a large library before deciding whether
  to move/collate aggregation and cache the earliest-review lookup. Category: Performance.
  Recommended route: `$impeccable optimize`.

## Positive patterns

Theme changes reuse the same views and preserve navigation rather than rebuilding the feature
with a new identity. History distinguishes scheduling grades from exam correctness, and current
memory estimates remain separate from historical activity. Chart choice is persisted. Both line
and bars use the same real review bins, labels and date selection. Errors and secondary text use
shared contrast tokens rather than unrelated system colors.

## Verification

- 36 text/icon/chart-token pairings across Warm/Neutral and light/dark pass 4.5:1;
  minimum ratio **5.289:1**. This verifies opaque token pairings, not every system chrome pixel.
- Swift package tests: 129 executed, one existing skip, zero failures.
- iPhone simulator: settings navigation, daily-limit persistence, bar/line switching and tap
  selection, date navigation, voice/storage navigation; Warm dark and Neutral dark with
  accessibility text. Screenshots use explicitly isolated in-memory review fixtures.
- iPad simulator: Settings and Activity in the native split view, with capped content width.
- Final iPhone simulator pass: three UI tests passed; final iPad pass: one UI test passed.
- Signed iOS build succeeded and the update was installed over Wi-Fi. Automatic launch was
  blocked by the phone's lock screen; opening the installed app requires unlocking the device.

## Remaining checks

1. `$impeccable optimize`: measure large-library refresh cost rather than assume a frame-rate result.
2. `$impeccable audit`: full VoiceOver reading order and chart selection on hardware; Mac resizing,
   iPad multitasking/rotation, Reduce Transparency and Increase Contrast.
3. `$impeccable polish`: a final bounded pass after those runtime checks, preserving the shared theme.
