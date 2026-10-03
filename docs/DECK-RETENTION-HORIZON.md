# Deck retention forecast horizon

The deck memory graph runs from today to a saved exam/target date. Without a future date, it ends on 31 December of the current year. Tap the date beneath Memory outlook to set or clear the date. A past deadline falls back to year-end.

The curve uses actual dates and at most 65 samples, concentrated near today to retain the initial decay shape. Both deck averages and individual-card views use the same horizon. The current dot, retention target, theme colours, and next scheduled review marker remain. This is an estimate without future reviews; an exam date changes the view, not the scheduler.

Exam dates are optional in saved decks, so older libraries continue to decode. Personal account synchronization retains the date without publishing it to shared deck collaborators.

Validation: four focused forecast/persistence tests and the private cloud round-trip test passed. Simulator review covers year-end labels, opening/saving the exam-date control and existing questions/notes navigation. The first UI run retained the obsolete seven-day assertion; the next revealed a parent accessibility identifier overriding child controls. Both checks were corrected.

Final UI check passed in /tmp/engram-deck-date-picker.xcresult, explicitly waiting for the exam toggle to be enabled and the native date picker to exist. Graph and enabled picker screenshots were inspected and archived. Final signed build installed and launched on the paired iPhone at 20:58 on 3 October 2026.
