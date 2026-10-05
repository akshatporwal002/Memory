# Minimalist UI revision validation

> Archived on 5 October 2026 from main `381c917`. This is historical context, not current implementation guidance. Outstanding work is tracked in [the backlog](../../BACKLOG.md); newer requirements take precedence.

Branch: `akshat/minimalist-ui-revision`. Review baseline: `a17776a`. Source revision `fddc39a` was accepted in the final Mac simulator recheck on 2 October 2026. All eight initial findings are addressed in the tested flows.

## Implemented behavior

- Today restores the original olive-green study area, Start review, saved-session Resume and deck links from `995e1b2`.
- Deck memory shares the page canvas. Per-deck retention, deck-wide recall and card distribution remain live scheduler estimates; the chart explicitly labels Today and 7 days.
- Questions and Notes are separate deck-owned destinations. Back returns to the overview. Questions render numbered bold prompts, separated italic MCQ options, green correct answers and explanations. Ordinary questions share that numbering and answer color, preserving safe formatted content and media.
- Notes reading filters prose while keeping the complete notebook draft intact for saving. The top-right rail is a compact dash stack with the active dash replaced by an orange heading. A single touch surface maps taps/slides to sections; VoiceOver adjustment and the full Contents menu are alternatives.
- The small assistant shares the bottom navigation row's native glass treatment. Its compact composer morphs from the entry, follows the keyboard safe area, grows for responses and supports expansion/collapse. Distinct themed tint separates it from reading content. Native glass is guarded for iOS 26; material/opaque fallbacks and Reduce Motion are supported in code.
- Dock clearance is applied to the actual content/workflow surfaces and follows measured dock height. Deck actions live in the top-right gear menu.

## Review loop

The existing Mac chat, `Audit UI for GPT6 Astra`, was instructed to use GPT-6.1 Sol and act as a premium product UI reviewer. Windows owns app-source edits. The Mac reviews actual iPhone/iPad simulator screens and reports findings; its current session lacks cross-chat messaging, so Windows retrieves those reports and sends the next revision for rechecking.

The unrelated dirty Mac checkout was preserved. Reviewer worktrees and generated project changes are isolated. Screenshots use DEBUG-only AWS fixtures; simulated AI replies explicitly say that no live request was made.

| Initial Mac finding | Implemented correction | Verification |
| --- | --- | --- |
| Assistant entry did not open | Glass moved into button label; full content shape | Passed: opening, keyboard, sending, expansion and close |
| Back skipped deck overview | Deck-owned reading destinations; separate assistant context state | Passed in the scoped final simulator recheck |
| Dock obscured final actions | Measured height and content-level safe-area clearance | Passed in the scoped final simulator recheck |
| Dash taps did not jump | One full-area contents control, no overlapping targets | Passed in the scoped final simulator recheck |
| iPad used legacy deck page | Shared overview and reading routes | Passed in the scoped final simulator recheck |
| MCQ letters wrapped at large text | Intrinsic non-wrapping letter labels | Passed in the scoped final simulator recheck |
| Ordinary question treatment differed | Inline numbering and green answer ink | Passed in the scoped final simulator recheck |
| Chart omitted endpoint label | Explicit 0…7 domain and both visible endpoint captions | Passed in the scoped final simulator recheck |

A subsequent accessibility test issue was corrected by removing the assistant panel's inherited identifier. A reproducible expansion/close hit-area failure prompted full 44-point content shapes on those controls. Review iterations address specific failures, not speculative cosmetic changes.

## Build and regression evidence

- Xcode 26.6, iPhone generic builds passed at `0d21039`, `173a9c4`, `13f272f` and `583503b`.
- Existing `EngramTests`: 106 tests, zero failures, one skipped, on the initial candidate. Learning/scheduling/persistence code is unchanged by subsequent UI corrections.
- The committed Xcode project and shared iOS scheme now include both UI-test files, matching `project.yml`.
- Mac initial review verified retention changes, Notes editing/save without loss of the five fixture questions, Start/Resume review, and structured MCQ reading. It rejected the initial candidate on the defects above.
- Final candidate: four iPhone tests and one iPad test passed, zero failures, with successful build/test exits. Retention 90% → 96%, Notes editing/save and preservation of all five questions were verified. Dark accessibility3 layouts and iPad portrait were inspected.

## Limits

Simulator fixture evidence does not verify live ChatGPT authentication/API replies, audio quality, model downloads or physical-device performance. VoiceOver traversal, older-OS fallback appearance and runtime accessibility preference combinations require separate device coverage; code support alone is not a claim that those combinations were visually tested.

The temporary Windows keep-awake helper has exited, confirmed before final delivery. Normal sleep behavior is restored; saved Windows power settings were not changed.

## Final review evidence

- [Mac review report](../../../design/previews/minimalist-review/REVIEW-fddc39a.md).
- [28 actual simulator screenshots](../../../design/previews/minimalist-review/INDEX.md), including Today, flat deck outlook, Questions, compact contents, assistant keyboard/response/expanded states, dark large text and iPad.
- Local copies include test logs, accessibility trees, temporary reviewer harness and provenance. Full xcresult bundles remain on the Mac under `/private/tmp/engram-minimalist-review-evidence/final-fddc39a`.
- The Windows implementation owner visually inspected the final Today, deck, Questions, Notes rail and keyboard composer captures. The review loop stopped after acceptance; no further cosmetic churn was requested.

