# PDF learning review evidence

The [original Mac report](REVIEW-PDF-FINAL.md) accepts the scoped fixture review at `f54620d`, with no unresolved major findings. Screenshots use an explicitly labelled DEBUG AWS fixture: generation and verification are simulated. They do not demonstrate live model quality or a real Files-picker import. Real PDF extraction and draft restoration have domain-test coverage.

Windows made application changes; the Mac GPT-6.1 Sol reviewer used an isolated checkout, simulator screenshots and a temporary test harness. Earlier failing probes and their resolutions are described in the original report. Subsequent singular-count copy corrections at `05b9ef3` passed a generic unsigned iPhone build; these captures predate that copy change.

## Final edit/save check — f54620d

- [Labelled editors](f54620d/recheck-PDF-51-Labelled-Wording-Editors.png)
- [User-edited status](f54620d/recheck-PDF-52-Edited-Status.png)
- [Save action](f54620d/recheck-PDF-52b-Save-Ready.png)
- [Saved flat deck overview](f54620d/recheck-PDF-53-Edited-Deck-Saved.png)
- [Original manual draft preserved](f54620d/recheck-PDF-54-Manual-Draft-Preserved.png)
- [Passing focused log](f54620d/iphone-save-recheck.log)

Matching accessibility trees and the temporary reviewer test are retained in the same directory.

## iPhone and iPad traversal — 77dd033

- [Guided brief](77dd033/iphone-PDF-Learning-Brief.png), [sample approval](77dd033/iphone-PDF-Learning-Sample.png), [final review](77dd033/iphone-PDF-Learning-Review.png)
- [Question evidence](77dd033/iphone-PDF-11-Saved-Question-Evidence.png), [saved notes](77dd033/iphone-PDF-12-Saved-Notes.png)
- [Shuffled options](77dd033/iphone-PDF-13-Shuffled-Review.png), [correct grading](77dd033/iphone-PDF-14-Correct-Shuffled-Answer.png)
- [Large dark controls](77dd033/iphone-PDF-21-Large-Brief-Controls.png), [preferences](77dd033/iphone-PDF-21b-Large-Brief-Preferences.png), [approval](77dd033/iphone-PDF-23-Large-Approval.png)
- [iPad brief](77dd033/ipad-PDF-Learning-Brief.png), [sample](77dd033/ipad-PDF-Learning-Sample.png), [review](77dd033/ipad-PDF-Learning-Review.png), [saved questions](77dd033/ipad-PDF-Saved-Questions.png), [saved source](77dd033/ipad-PDF-Saved-Source.png)
- [iPhone test log](77dd033/iphone.log), [iPad test log](77dd033/ipad.log)

## Targeted checks

- `2a21352`: [paused state](2a21352/iphone-PDF-30-Pause-State.png), [retry sample](2a21352/iphone-PDF-31-Retried-Sample.png), [domain test log](2a21352/domain-pdf.log).
- `ac5efca`: [next question unselected](ac5efca/iphone-PDF-40-Next-MCQ-Unselected.png), [first tap selects](ac5efca/iphone-PDF-41-Next-MCQ-First-Tap.png).

The accepted earlier minimalist UI evidence is in [minimalist-review](../minimalist-review/). This evidence set is deliberately bounded; full intermediate artifacts remain on the Mac.
