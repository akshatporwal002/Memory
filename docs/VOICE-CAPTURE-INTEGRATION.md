# Voice capture integration

Implementation added 4 October 2026. Compilation and runtime validation are pending; the Mac SSH endpoint remains unreachable and Windows has no Swift compiler.

## Connected workflow

- Voice settings choose provider and Continue/Wait, remembered independently per app account. Managed Mini remains the default; unconfigured providers cannot record or upload audio.
- Debug builds expose an explicit local development preview. It resets on account changes and restart and cannot grant production entitlement. Parakeet/Kokoro models must also be prepared. AI marking uses the selected connection and can incur provider charges.
- Local recognition preserves the transcript, frozen question/evidence/model and original submission time in the durable job transaction before Continue advances. PCM capture is bounded to two minutes; portable WAV encoding rejects nonfinite samples. Successfully persisted local recognition needs no upload and deletes its recording.
- Foreground workers mark saved answers independently of the visible question. Suspension stops dispatch; account/library/credential changes invalidate the worker scope. No background execution promise is made.
- Review exposes a small pending-count action. Voice settings and review options open the same flat results list: original answers, outcome, explanation and errors. Pending transcripts can be corrected; failed marking can be retried without retranscribing; pending work can be cancelled.
- Wait-mode Next advances an already graded answer without creating a second review event. Manual grading, reveal and MCQ submission refuse an existing voice attempt.
- iPhone and iPad share native, adaptive forms for settings/history/correction; the existing question layout is retained. No new question type is introduced.

## Remaining gates

Production entitlement, managed-credit backend and cloud recording dispatch are not connected. Cloud speech output and combined audio remain unfinished. Completed-transcript correction still needs scheduling reconciliation. Failed audio cleanup needs a retry surface. Pending jobs from a replaced grading identity need an explicit migration/discard workflow. Live microphone tests, worker-lifecycle tests, iPhone/iPad screenshots and installation have not run for this revision.

Two WAV and two local-transcript service tests are written, not executed. Earlier passing test counts apply only to their earlier revisions.
