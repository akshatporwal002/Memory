# PDF learning validation

> Archived on 5 October 2026 from main `381c917`. This is historical context, not current implementation guidance. Outstanding work is tracked in [the backlog](../../BACKLOG.md); newer requirements take precedence.

Status: delivered on `akshat/minimalist-ui-revision`, following the accepted minimalist UI baseline `853ff0c`. Mac accepted the scoped simulator review at `f54620d`; subsequent count-copy polish at `05b9ef3` passed a generic iPhone unsigned Xcode build.

## Implemented

- New notebook offers Learn from a PDF / Resume PDF learning without overwriting the manual notebook draft.
- Native PDFKit import retains selectable page text, filename and page numbers locally. Bounds: 25 MB file, 300 pages, 2 MB extracted text; selected generation scope up to 24 batches of eight passages. Empty/scanned pages produce explicit warnings; image/diagram understanding and OCR are not claimed.
- Guided brief asks about learning goal, topics, exclusions, page range, difficulty, question style/count and notes depth. Source headings are offered as suggestions. Questions-only, notes-only and mixed output are available.
- Local ranked retrieval supplies a diverse preview sample. Explicit approval retains the checked sample and starts bounded generation across selected pages. Generated prompts are passed back to avoid repetitions; duplicate fingerprints are filtered. Requested counts are maxima, not a guarantee of exhaustive factual coverage.
- Generation and a separate evidence-only verification request use the existing connected ChatGPT account/model. Structural checks reject missing/incorrect quotations, invented source IDs, invalid answer indices, duplicate options, unshufflable all/none-of-the-above choices and incomplete verification results. Unsupported items are withheld.
- Drafts persist in Application Support; completed batches survive pause/retry. Closing the flow cancels work. Generation errors never create a partial saved deck. Atomic/idempotent StudyService saving preserves source text and citations in native Codable backups.
- Preview supports source inspection, wording edits, removal and explicit save. User edits are marked as not rechecked. Saved Questions expose source evidence; Notes contain source references; the deck gear opens original source pages. The assistant retrieves original PDF passages and uses source-only instructions in PDF workflows.
- MCQ review options shuffle deterministically by presentation ID. Canonical answer identities still drive scheduling; visible letters, spoken recognition, spoken playback, feedback and assistant review context share the displayed order. Resume does not reshuffle mid-answer.

## Tests and review

- iPhone generic unsigned Xcode builds passed at `55988bd` and `d911de3`.
- `swift test --filter EngramTests` passed on `2a21352`: 117 tests, zero failures, one skipped. Includes actual generated-PDF extraction and draft persistence, page-aware retrieval, quotation matching, verification completion/ID rejection, choice validation, shuffled recognition, atomic save/retry and old-model decoding. Later changes affect presentation and accessibility labels only; focused simulator checks cover them.
- Supplied simulator test: `MinimalistStudyUITests/testPDFSampleApprovalAndSourceLinkedSave`.
- The initial Mac run found that saving left a cleared PDF screen onscreen. `219c4ae` keeps the route owner alive and opens the saved deck overview inside that navigation destination. Final recheck covers this and additional draft, source/Notes and shuffled grading workflows.
- Mac uses DEBUG fixtures explicitly labelled “UI review fixture — no live AI request was made.” The separate extraction test exercises a real PDF, rather than pretending the fixture tests exercise Files import.

## Practical limits

RAG plus evidence checking reduces unsupported answers; it cannot guarantee source truth or perfect model judgments. Live AI generation, account permissions/usage limits, physical-device performance, OCR/diagrams, very large documents and all accessibility combinations are not established by fixture screenshots. Requests use `store: false`, `stream: true`, terminal completion checks, no redirects and account-change checks. No hosted file search, Files upload API, paid embeddings or new server dependency is used.

The Mac's original dirty checkout and unrelated Windows changes remain preserved. Main is unchanged. The temporary Windows keep-awake helper was stopped and its process exit verified before final delivery; no power-plan settings were changed.

## Delivered evidence

The [Mac's final review](../../../design/previews/pdf-review/REVIEW-PDF-FINAL.md) reports no unresolved P1/P2 findings within its stated scope. The [evidence index](../../../design/previews/pdf-review/INDEX.md) links screenshots, accessibility trees and logs by tested revision. Its minor singular-count finding was corrected in `05b9ef3`; screenshots intentionally retain the pre-copy-polish tested revisions. Live AI quality and installation on the physical phone remain unverified in this delivery.

## Review corrections

- Save route: open the saved deck overview inside the existing creation route, retaining the independent manual draft.
- Large text: stacked page steppers and explicit wrapping menu rows replace cramped native menu-picker layouts.
- Dark contrast: PDF primary actions reuse the app’s explicit anchor/onAnchor button style.
- Wording editors: accessible labels are explicit; user edits remain marked as not rechecked.
- MCQ continuity: clear a selected option when the presentation changes, so the next question requires its own select/confirm interaction.
- Corrected reviewer timing/scroll selection established that editing/save and return to the manual draft work; earlier failed probes are not current app defects.

