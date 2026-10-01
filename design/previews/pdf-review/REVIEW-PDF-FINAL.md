# PDF learning UI review — final scoped result

Reviewed candidate: **f54620d**, with earlier affected checks on its ancestor revisions. Review completed 2 October 2026. **Accepted for the scoped fixture/UI checks; no unresolved P1/P2 finding from this review.** This is not live-AI or production-service acceptance.

The final focused edited-save/manual-draft check passed, 1 test and 0 failures. After entering labelled wording editors and typing an answer edit, the UI showed “Edited by you · not rechecked”. Scrolling Save fully into view and tapping opened AWS PDF learning. One Back returned to New notebook with the original title and document text intact. Captures were visually inspected.

## Findings and resolution

| Finding | Resolution and evidence |
| --- | --- |
| P1 Save left an empty PDF chooser open | Navigation fixed in 219c4ae. Supplied save/source tests pass on iPhone and iPad on 77dd033; edited-save check passes on f54620d. |
| P1 Primary CTA contrast | Initial light approval text/fill measured 2.19:1. 77dd033 uses deliberate olive/on-anchor button styling. Light and dark large-text captures inspected; the fixed pairing was not numerically remeasured. |
| P1 Large-text clipping | Page labels wrapped into individual letters and Questions and notes clipped. 77dd033 stacks page controls and wraps labelled menu rows; accessibility3 screenshots show full labels and values. |
| P2 Preference menus lacked labels | Difficulty, Create, Question style and Notes labels now persist. Final focused test changes Difficulty to Beginner successfully. |
| P2 Populated wording fields lacked accessible labels | f54620d adds Question or heading / Answer or notes; final test finds and types through the labelled fields, with AX trees recording labels. |
| MCQ selection persisted into next question | ac5efca resets selected state per presentation ID. Dedicated next-question test passes; first tap on the next question selects without grading. |
| P3 Singular grammar | Still present: 1 pages, 1 questions, 1 note sections, 1 cards and related count wording. Minor copy polish remains. |

## Verification matrix

| Revision | Check | Result |
| --- | --- | --- |
| 2a21352 | PDFLearningTests: extraction/draft persistence, scope/textless rejection, exact citations, retrieval, old backup decoding, atomic/idempotent save, valid choices, shuffled letters/stable resume, unverified rejection and verifier IDs | 11 passed, 0 failures |
| 2a21352 | iPhone pause/retry fixture flow | Passed; actual paused state and retry sample captured |
| ac5efca | iPhone MCQ selection reset | Passed |
| 77dd033 | Supplied sample approval and source-linked save, iPhone | Passed |
| 77dd033 | Dark accessibility3 brief/sample, iPhone | Passed and screenshots inspected |
| 77dd033 | Supplied sample approval and source-linked save, iPad | Passed and source/questions screenshots inspected |
| f54620d | Labels, preference change, wording edit, save, manual draft preservation | Final focused recheck passed, 1 test, 0 failures |

The longer 77dd033 traversal also reached saved Questions, Notes, source evidence and shuffled review grading before failing reviewer harness assertions. Screenshots show canonical CloudFront A displayed as C, selected C marked Correct, and explanation using C. Supporting source filename/page/quotation is retained; Notes is prose rather than another question list. Adjust removed approval/save until a new sample was generated.

Earlier harness failures remain recorded, not hidden: placeholder lookup failed because populated fields exposed only values; a scroll helper overasserted Save hittability with the keyboard open; an excessive Back loop reached Today rather than reopening the manual draft. Initial f54620d direct Save tap did not open the deck, but its capture/tree showed an enabled Save with no validation error. The focused recheck changes only the temporary harness to scroll Save fully into view before tapping and passes. This supports a tap/scroll-state problem in that run, not an edited-content validation defect.

## Final evidence

- [Final focused log](f54620d/iphone-save-recheck.log)
- [Labelled editor AX tree](f54620d/recheck-PDF-51-Labelled-Wording-Editors-tree.txt)
- [Edited status](f54620d/recheck-PDF-52-Edited-Status.png)
- [Save ready](f54620d/recheck-PDF-52b-Save-Ready.png)
- [Saved deck overview](f54620d/recheck-PDF-53-Edited-Deck-Saved.png)
- [Manual draft preserved](f54620d/recheck-PDF-54-Manual-Draft-Preserved.png)
- [Large brief controls](77dd033/iphone-PDF-21-Large-Brief-Controls.png)
- [Large preferences](77dd033/iphone-PDF-21b-Large-Brief-Preferences.png)
- [Large approval](77dd033/iphone-PDF-23-Large-Approval.png)
- [Saved question/evidence](77dd033/iphone-PDF-11-Saved-Question-Evidence.png)
- [Saved notes](77dd033/iphone-PDF-12-Saved-Notes.png)
- [Shuffled display](77dd033/iphone-PDF-13-Shuffled-Review.png)
- [Correct shuffled grading](77dd033/iphone-PDF-14-Correct-Shuffled-Answer.png)
- [Domain log](2a21352/domain-pdf.log)

## Limits and ownership

The UI uses an explicit DEBUG one-page AWS learning fixture and simulated generation/verification. It did not import the user's full AWS v44 slide PDF through the picker. Actual PDF extraction is covered by domain tests using generated local PDFs. Fixture launches reset the test repository; UI reentry/relaunch persistence of the PDF draft is not claimed. Manual draft preservation was tested within one session; domain tests cover persisted source/draft restoration.

No live AI request, account/auth flow, microphone, model download or end-to-end spoken interaction was exercised. Code paths and domain tests establish displayed/spoken choice-letter mapping, not live voice acceptance. Large-text review is scoped to the brief/sample screens; this is not a complete screen-reader traversal or a full platform/accessibility matrix.

Windows owns all application source fixes. Mac reviewer changed only the temporary UI test harness and generated Xcode build files in /private/tmp/engram-minimalist-recheck. No application Swift was modified, no commit or push was made, and the original dirty Memory checkout was untouched. GitNexus impact lookup for the temporary test returned Target not found; manual impact scope was test-only, no app callers or processes changed. Outbound cross-thread messaging is unavailable; the implementation thread can retrieve this report and artifacts.
