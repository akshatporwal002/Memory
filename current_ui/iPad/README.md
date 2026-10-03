# iPad UI captures — 4 October 2026

Captured from the latest working app sources based on dev revision 32b8a89, on iPad Pro 13-inch (M5), iOS simulator 26.0.1. Screens use the deterministic UI sample library and fixture assistant responses; no live AI request was made.

Main screens: Today, Library, Deck, Questions, Notes, Activity, Settings. Additional captures cover MCQ selection/feedback, assistant keyboard/response/expanded states and monochrome white Today/chat.

Each view folder holds current.png and, after its next refresh, one previous.png. Use tooling/update-current-ui.ps1 to rotate captures.

Validation: testIPadScreenCaptures passed; testMCQTextChoicesAndInlineExplanation passed. The earlier phone-oriented traversal failed because it queries bottom-tab buttons absent on the iPad sidebar. Chat and white-theme passes captured their states before failing their phone-tab checks; these do not certify the full workflows.

Visible follow-up issues:
- Library repeats its heading below the navigation title.
- Notes use almost the full detail-column width, giving long reading lines.
- The compact assistant response initially has text clipped above the visible transcript.
- Assess sidebar duplication of deck navigation and large empty areas during the iPad design review.

Source UI design was not changed during this capture task. A reusable iPad sidebar capture test was added.
