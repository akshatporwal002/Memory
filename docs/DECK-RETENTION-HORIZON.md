# Deck retention forecast horizon

The deck memory graph begins at deck creation and runs to a saved exam/target date. Without a future date, it ends one calendar year from today. Tap the date beneath Memory outlook to set or clear the date. A past deadline falls back to the rolling-year view.

The curve uses actual dates and at most 65 samples, concentrated near today to retain the initial decay shape. Both deck averages and individual-card views use the same horizon. Solid historical estimates use recorded post-review states only; unsupported periods are left blank rather than reconstructed from the current state. Future estimates start at today. The current dot, retention target, theme colours, and next scheduled review marker remain. This is an estimate without future reviews; an exam date changes the view, not the scheduler.

Exam dates are optional in saved decks, so older libraries continue to decode. Personal account synchronization retains the date without publishing it to shared deck collaborators.

Validation: four focused forecast/persistence tests and the private cloud round-trip test passed. Simulator review covers year-end labels, opening/saving the exam-date control and existing questions/notes navigation. The first UI run retained the obsolete seven-day assertion; the next revealed a parent accessibility identifier overriding child controls. Both checks were corrected.

Final UI check passed in /tmp/engram-deck-date-picker.xcresult, explicitly waiting for the exam toggle to be enabled and the native date picker to exist. Graph and enabled picker screenshots were inspected and archived. Final signed build installed and launched on the paired iPhone at 20:58 on 3 October 2026.

Latest requirements: remove the notebook listing and duplicate saved-session action from Today. Its single study action resumes existing work when available. Left-swipe deck rows reveal Suspend/Resume; long-press menus provide open, suspend/resume, source import and confirmed deletion. All PDF/Markdown/image rows provide Open file and confirmed Delete file. Pausing a deck also excludes descendant decks, without modifying their cards, schedules or existing individual-card pauses. Suspension is account-private in synchronization.

Rolling-year validation: all eight focused logic/synchronization tests passed, including historical evidence boundaries, creation date, descendant suspension, preservation of individual card pauses, and private cloud round trips. Final Library swipe/context tests passed in /tmp/engram-library-actions-final.xcresult; deck graph/date/navigation passed in /tmp/engram-rolling-year-labels.xcresult. Screenshots were inspected and rotated in current_ui. Older decks without creation metadata use their earliest recorded review, or today when neither is known. The final signed app installed and launched on the paired iPhone at 21:20 on 3 October 2026.
