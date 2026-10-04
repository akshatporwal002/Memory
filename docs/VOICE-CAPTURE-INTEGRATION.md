# Voice capture integration

Implementation added 4 October 2026. Compilation and runtime validation are pending; the Mac SSH endpoint remains unreachable and Windows has no Swift compiler.

## Connected workflow

- Voice settings choose provider and Continue/Wait, remembered independently per app account. Managed Mini remains the default; unconfigured providers cannot record or upload audio.
- Debug builds expose an explicit local development preview. It resets on account changes and restart and cannot grant production entitlement. Parakeet/Kokoro models must also be prepared. AI marking uses the selected connection and can incur provider charges.
- Local recognition preserves the transcript, frozen question/evidence/model and original submission time in the durable job transaction before Continue advances. PCM capture is bounded to two minutes; portable WAV encoding rejects nonfinite samples. Successfully persisted local recognition needs no upload and deletes its recording.
- Foreground workers mark saved answers independently of the visible question. Suspension stops dispatch; account/library/credential changes invalidate the worker scope. No background execution promise is made.
- Review exposes a small pending-count action. Voice settings and review options open the same flat results list: original answers, outcome, explanation and errors. Transcripts can be corrected before or after grading; failed marking can be retried without retranscribing; pending work can be cancelled. Same-account/device jobs from an older grading connection remain visible, but can only be cancelled/cleaned up, never silently retried through a different connection. Explicit account ownership is saved for new jobs; legacy visibility recognizes the previously used account/revision identity format within the isolated repository.
- Recording cleanup is journalled separately from transcript and grade state. Successful recognition or cancellation marks audio ready for deletion; failed deletion leaves a retry control available across restart. Clearing that flag requires removal first and does not rerun recognition or grading. An untranscribed live job cannot acknowledge deletion.
- Completed corrections retain the old transcript and assessment, remove the old grade through a review correction, and replay later reviews from the original baseline. Replacement grades use a new stable review ID at the original answer time. Unsupported/stale evidence or an externally changed schedule prevents automatic reconciliation. If replacement marking fails or is unclear, the removed grade is not silently restored.
- Wait-mode Next advances an already graded answer without creating a second review event. Manual grading, reveal and MCQ submission refuse an existing voice attempt.
- iPhone and iPad share native, adaptive forms for settings/history/correction; the existing question layout is retained. No new question type is introduced.

## Remaining gates

Production entitlement, managed-credit backend and cloud recording dispatch are not connected. Cloud speech output and combined audio remain unfinished. Completed-transcript reconciliation and cleanup/old-connection controls are implemented but unvalidated. Older-account jobs transferred with a library need an explicit ownership migration decision; they are not exposed through matching email addresses or inferred ownership. Live microphone tests, worker-lifecycle tests, iPhone/iPad screenshots and installation have not run for this revision.

Two WAV and two local-transcript service tests are written, not executed. Earlier passing test counts apply only to their earlier revisions.

Three additional correction/reconciliation tests are written, not executed: removing the first review preserves the original baseline; completed correction retains/replays a later review and rejects stale workers; another account or edited reference cannot remove a grade. Cloud synchronization now uses all review events plus correction records to select the preserved baseline rather than starting from a later event's obsolete before-state.

Three cleanup/ownership tests are also written but unexecuted: untranscribed-file protection and idempotent acknowledgement; same-account old-connection visibility with account/device separation; failed recording deletion followed by cleanup without another provider call or review event.

## Personal-key integration status — 4 October 2026

Personal Mini/Full now connects protected WAV capture to OpenAISpeechProvider and the durable worker. Debug preview requires a configured personal key and explicit audio/billing disclosure; it resets on account changes/restart. Production remains disabled pending entitlement/configuration. No live request was made during validation. Cloud capture uses on-screen controls instead of the local spoken-command parser; it still requires local VAD/Kokoro preparation.

Failed transcription exposes an explicit retry with potential duplicate-charge warning. Failed marking reuses the persisted transcript. Managed capture, Google native transport, cloud speech playback and production purchases remain unconnected.

The current isolated Mac package run passed 274 tests, one skipped, zero failures, including the WAV and native selection extensions. SSH then timed out before iOS build launch; latest device/UI validation is pending. Earlier evidence above remains revision-specific.

## Optional speech output integration — unvalidated extension

Output selection now offers default local Kokoro or personal-key OpenAI, with independent model/voice settings and debug-only speech disclosure. Speech preview and study narration use the selected path. No automatic provider fallback or retry is performed; cloud request results reject changed accounts, credentials or settings. Existing playback generation/cancellation and echo processing remain in use. A validated WAV is decoded to mono 24 kHz for study playback; temporary protected files are removed afterwards.

Transcription opt-in cannot grant output opt-in. Both approvals reset on account changes/restart; production stays disabled. A consent regression test is written but unexecuted. The 274 passing package tests above predate this extension; latest Mac SSH attempts timed out. Compile/runtime, iPhone/iPad captures, real provider speech/interrupt behavior and installation are pending. Google native output and combined audio transport remain separate unfinished integrations.
