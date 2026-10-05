# Activity overview

> Archived on 5 October 2026 from main `381c917`. This is historical context, not current implementation guidance. Outstanding work is tracked in [the backlog](../../BACKLOG.md); newer requirements take precedence.

Activity is a read-only projection of active cards and native, uncorrected review events. It does not change scheduling or library storage.

- Today / 7 days / 30 days / All time use the configured timezone and study-day boundary. The latter two rolling windows include today and the previous 6/29 study days.
- Memory and due counts always describe the present. The FSRS adapter exposes optional recall estimates; unsupported review states display Unavailable. New and learning/relearning states remain separate.
- Each deck counts its own active cards. Suspended cards are disclosed but excluded; retired cards and deleted content are excluded. Reviews of excluded cards do not enter active summaries.
- At target uses the configured desired retention. Bars show proportions, with labeled counts independent of color.
- Question outcomes are self-ratings. The latest rating in the chosen window is shown, with all attempts available inline. Undo corrections are excluded. Imported logs remain separate and are never converted into native grades.
- Decks sort by current due count, then name; questions sort due first. One deck and one question can be open at a time. Question lists load 20 at a time.
- The screen refreshes when library revision, period, or foreground state changes, and every minute while active. Accessibility text sizes use menu pickers; disclosure changes have no motion.

## Validation — 2026-09-07

- Swift suite: 102 tests, one existing skip, zero failures.
- iOS simulator and macOS Xcode builds: passed.
- Regression tests cover threshold estimates, unsupported/invalid states, imported schedules, undo, period boundaries across DST, repeated attempts, exclusions, nested decks, large decks, and reversed/cloze rendering.
- iPhone simulator: inspected memory bars, deck expansion, due-first ordering, outcome labels, and pagination control. Fixed percent rounding and singular attempt wording after inspection.
- Full interactive VoiceOver, accessibility-size, iPad, and Mac visual checks remain manual verification; concurrent simulator use interrupted further interactions, and the Mac capture tool did not find a window.
