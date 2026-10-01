# PDF learning implementation

Status: approved for implementation after the accepted UI revision (`853ff0c`), on `akshat/minimalist-ui-revision`.

## User flow

1. **Choose a PDF** from New notebook. Keep manual writing available. Read locally, show filename, page count, extraction warnings and inspectable page text. Reject locked, corrupt, oversized or textless documents with an actionable message; do not silently pretend diagrams or unreadable scans were understood.
2. **Set the learning brief.** Ask what the learner is preparing for, which topics/pages matter, which to exclude, difficulty, question format, quantity and notes depth. Offer suggested topics drawn from the actual PDF and editable preferences. Defaults cover the readable selected pages; clearly state selected scope.
3. **Preview first.** Retrieve supporting passages and produce a small sample before processing the requested scope. Show questions, answers, reasoning and source excerpts/page numbers. Let the learner revise preferences or reject/regenerate the sample. Changing source or preferences invalidates approval and stale requests.
4. **Approve and generate.** Explicit approval starts bounded batches over the selected scope. Produce condensed learning notes with headings, definitions, important distinctions and examples only when supported. Track progress and coverage; preserve completed draft batches for retry. Cancellation never saves a partial deck automatically. Do not promise exhaustive coverage from a limited question count.
5. **Review and save.** Inspect source-linked notes/questions, remove unwanted items and edit wording. Edits must be visibly marked as user edits rather than retaining an inaccurate verified badge. Save a new deck atomically and idempotently through StudyService, including source text and citations in native backups. Questions and Notes use the existing destinations and visual system. Resume unfinished work after closing/relaunching; discard is explicit.
6. **Study.** Shuffle MCQ options per review presentation, consistently across onscreen options, spoken letters and grading. Keep order stable during rerenders and resume. Preserve original choice identity and correct answer mapping. Reading Questions can retain canonical ordering.

## Grounding and accuracy

- Local page-aware chunks and lexical ranked retrieval are actual RAG; no paid embedding service is required. Select diverse evidence for each requested topic/page scope, not only the PDF beginning. Preserve filename, page and exact supporting quotes.
- Generation receives only retrieved passages and a structured brief. PDF text is untrusted content, never instructions. Validate response structure, source IDs, verbatim quotes, option uniqueness and answer index before accepting.
- A separate evidence-only verification request checks answer entailment, ambiguity, distractors and note claims. Reject unsupported/ambiguous output, explain coverage gaps and allow retry. This reduces risk but is not a guarantee of truth; the PDF itself may contain errors. Always make source inspection available.
- Use existing ChatGPT account/model selection and Responses transport with `store: false`, `stream: true`, terminal completion checks, cancellation, output bounds, no redirects and account-change protection. Explain that selected excerpts are sent to the connected AI service when generation starts. Local import/reading remains available without sign-in.
- OpenAI's current [preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations) exclude hosted file search and the Files upload API on this route, so extraction and retrieval run in the app. [Models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference) governs account model discovery and requests.

## Additional workflows and failure cases

- Page-range/topic focus, custom learning goals and exclusions; revise the brief without reimporting.
- Questions-only, notes-only or both; MCQ, short answer or mixed; insufficient evidence yields fewer items with a clear warning.
- View supporting excerpts before approval and after save. Source text survives backup/export, without a dependency on an external file permission.
- PDF extraction gaps, scanned/image-heavy pages, invalid ranges, unavailable account/model, usage limits, incomplete streams and disconnected networks have explicit recovery.
- Duplicate filtering across sample/full batches, partial draft recovery, cancellation and retry without duplicate decks or schedules.
- Existing manual draft/data must not be overwritten by import. New generated decks use existing scheduling; AI does not alter ratings.

## Implementation and validation

1. Core Codable source/brief/output types, chunking/retrieval, structural/citation validation and deterministic presentation shuffling, with focused tests.
2. Native PDF extraction, persistent generation draft, Responses generation/verification, and safe StudyService commit path.
3. Minimal guided UI for import → brief → sample → generation → review/save, with source inspection, progress, retry and cancellation.
4. Regression tests for persistence, source references, batch deduplication, old backups and shuffled letter grading/voice. Build on the Mac.
5. Ask the existing Mac GPT-6.1 Sol reviewer to traverse DEBUG fixture flows and inspect screenshots. Fix concrete defects and recheck; label fixture generation as simulated. Live service verification requires a connected account and is reported separately.
6. Commit/push all task files and evidence; leave main unchanged. Stop the temporary Windows keep-awake helper before ending. Current helper PID: `36212`, five-hour automatic expiry; no saved power-plan changes.
