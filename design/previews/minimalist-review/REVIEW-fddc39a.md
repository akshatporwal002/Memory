# Final minimalist UI recheck — fddc39a

Reviewed on 2 October 2026, Australia/Melbourne. Isolated checkout: `/private/tmp/engram-minimalist-recheck`, detached revision `fddc39a`. Windows owns application fixes; Mac supplied simulator validation and a temporary reviewer harness.

## Verdict

**The eight original findings are addressed in the scoped simulator recheck.** The final candidate builds and all five selected tests pass: four iPhone tests and one iPad test. The assistant now opens, accepts typing, sends a simulated response, expands and closes. Native Back preserves the deck overview. Notes accepts edits to a visible writing block, saves, and preserves the fixture's five questions.

This is acceptance of the tested fixture flows, not a claim that native Mac, VoiceOver, large libraries, imported rich content or live AI have been comprehensively validated.

## Original findings and final status

| Finding | Final result | Evidence |
| --- | --- | --- |
| F1: assistant entry and response controls unreliable | Resolved in tested iPhone flow. Entry opens; keyboard sits below composer; Send produces a labelled fixture response; Expand switches to Collapse; Close restores the entry and usable Library dock. iPad entry opens above keyboard. | [Keyboard](iphone-Assistant-Keyboard.png), [response](iphone-Assistant-Response.png), [expanded](iphone-Assistant-Expanded.png), [iPad composer](ipad-42-Tablet-Assistant-Tap.png) |
| F2: Back loses deck context | Resolved. Questions → Back → Notes → Back retains the deck. The edit/save probe also returns to its deck without reopening it. | [Notes Back state](iphone-20-Notes-Back-State.png); `testDeckQuestionsAndNotesNavigation` passes |
| F3: dock covers links and final actions; poor selected contrast | Resolved for inspected default-size end positions: both deck links and their supporting text scroll above the dock; the final question's Edit and ellipsis sit above the assistant. Dark accessibility3 selection is readable. Exact end-of-list clearance at every accessibility size was not exercised. | [Deck links](iphone-13-Deck-Links-Scrolled.png), [last question](iphone-22-Questions-Last-After-Save.png), [dark large deck](iphone-Deck-Dark-Large.png) |
| F4: tiny rail buttons, failed section jump | Resolved for tested Shared responsibility jump and scroll synchronization. Rail is one accessible control, with the active orange heading replacing a dash. Both reviewer coordinate selection and supplied rail-value assertion pass. Full Contents menu remains available. | [Jump](iphone-Notes-Rail-Jump.png), [scrolled](iphone-Notes-Scrolled-Contents.png) |
| F5: iPad uses legacy deck interface | Resolved. iPad uses the flat Memory outlook, gear, and equal Questions/Notes links. | [iPad deck](ipad-41-Tablet-Deck-Route.png) |
| F6: large-text A)/B) split onto separate lines | Resolved in inspected dark accessibility3 MCQ: each option label stays together. | [Large-text Questions](iphone-Questions-Dark-Large.png) |
| F7: ordinary questions have detached numbering and inconsistent answer ink | Resolved for the basic fixture questions: prompt carries its number and answer text is green. | [Questions 1–3](iphone-21-Questions-After-Notes-Save.png), [questions 4–5](iphone-22-Questions-Last-After-Save.png) |
| F8: missing seven-day chart endpoint | Resolved. Today and 7 days are visible in light phone, dark accessibility3 and iPad layouts. Supplied existence assertion passes. | [Phone chart](iphone-Deck-Flat-Outlook.png), [dark chart](iphone-Deck-Dark-Large.png), [iPad chart](ipad-41-Tablet-Deck-Route.png) |

## Notes editing: earlier failure was harness selection

The previous probe selected the first `isHittable` writing field, whose frame began at y=0 underneath the navigation area. XCTest failed because that field never acquired keyboard focus. The temporary probe now selects a fully visible field below the toolbar and above the dock area. An ordinary tap focuses that field; typing works with the on-screen keyboard, Save reports Saved, and the first and fifth MCQ assertions still pass. No application editing code was changed by the reviewer.

[Visible editor with keyboard](iphone-18-Notes-Editing-Keyboard.png), [Saved state](iphone-19-Notes-Saved.png), [saved accessibility tree](iphone-19-Notes-Saved-tree.txt).

The test deliberately inserts sample text at the field's current insertion point. That changes the fixture heading shown in the rail; this is a test edit, not unintended app corruption.

## Build and test results

Xcode 26.6 (17F113), iOS Simulator 26.0.1 (23A8464). iPhone 17 Pro: 402 × 874 points. iPad Pro 13-inch M5: 1032 × 1376 points, portrait.

| Test | Result |
| --- | --- |
| Reviewer phone retention / Notes edit / save / question preservation | Pass, 39.163 seconds |
| Supplied assistant keyboard / response / expansion / close | Pass, 15.916 seconds |
| Supplied dark and accessibility3 layout | Pass, 14.530 seconds |
| Supplied deck / Questions / Notes / Back / rail / chart endpoint | Pass, 24.242 seconds |
| Reviewer iPad overview route and assistant opening | Pass, 11.237 seconds |

Phone: **4 tests, 0 failures**, build/test exit 0. iPad: **1 test, 0 failures**, test-without-building exit 0.

Artifacts: [phone log](iphone.log), [iPad log](ipad.log), `iphone.xcresult`, `ipad.xcresult`, exported attachment manifests, [temporary harness](MinimalistReviewerUITests.swift), [screenshot index](INDEX.md), [SHA-256 provenance](provenance.json). There are 28 raw simulator screenshots in the final evidence directory. Selected screenshots above were visually inspected; passing assertions alone were not treated as visual proof.

## Scope and remaining limits

Retention target 90% → 96% and changed memory distribution are verified by the final probe. Today study/resume passed the initial review and was not rerun here because the targeted fixes do not change those flows. Intermediate manual verification on 849d2da also exercised collapse, dismissal and reopening with thread preserved; final standard tests cover expansion and close but do not repeat every conversation-preservation case.

All assistant replies use the DEBUG fixture and display “UI review fixture — no live AI request was made.” No live AI, authentication, voice capture, model download or real library data was used.

Not verified in this pass: native Mac layout, physical-device performance, VoiceOver traversal, Reduce Motion/Transparency runtime settings, iPad landscape/multitasking, empty-library states, large-library stress, question-editor save, imported HTML/cloze/media edge cases, every rail section, assistant context across every destination, or final-action clearance at every Dynamic Type size. No new blocking issue was established in the final targeted checks.

## Workspace handling

No application Swift source was modified, committed or pushed by the Mac reviewer. The original dirty checkout was preserved. XcodeGen regenerated project files only in the isolated checkout; the temporary Notes probe received the visible-field selection correction. GitNexus impact was called for the edited test symbol and returned Target not found; manual scope is reviewer tests only, with no app callers. No commit was created, so no pre-commit detect_changes operation was required.

Initial findings and reproduction evidence remain on the Mac at `/private/tmp/engram-minimalist-review-evidence/REVIEW-0d21039.md`. Full xcresult bundles and exported attachment manifests remain in the final evidence directory on the Mac; the other linked evidence files are copied here. The earlier 783f3cc assistant failures are superseded by this final passing run; they should not be reported as current defects.

