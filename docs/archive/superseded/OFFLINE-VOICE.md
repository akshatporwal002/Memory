> Historical local document preserved on 5 October 2026. Implementation and validation claims below describe the earlier local work and have not been reverified against current main.

> Archived on 5 October 2026 from main `381c917`. This is historical context, not current implementation guidance. Outstanding work is tracked in [the backlog](../../BACKLOG.md); newer requirements take precedence.

# Voice and interactive answer review

Implemented in the current source; see VOICE-AND-MCQ-REVIEW-SPEC.md for the broader
feature plan and acceptance targets. Driving/background operation remains pending.

## Controls

Settings > Voice downloads/loads local Parakeet, Silero speech detection, and
Kokoro models. Review's microphone button enables the mode after setup. Keep
Memory foregrounded. Speaking can interrupt question/feedback playback. Repeat,
Next, Skip, Explain, Done, and Stop are contextual voice controls. Explain reads
the saved answer/explanation after assessment; it does not generate new material.
Ending an answer with Done requests submission before the silence timeout.

MCQ options appear as individual accessible buttons. One tap selects; a second
tap on the same option confirms. A named Confirm accessibility action is also
available. Feedback remains until Next. Correct maps to FSRS Good; incorrect
maps to Again. Unclear recognition prompts for clarification without a grade.
Negated/ambiguous matching does not silently select a choice. Exact option labels,
phonetic letter aliases, choice text, and sufficiently distinctive vocabulary
are supported; broad semantic matching of option descriptions remains conservative.

The original AWS sample's explicit A)/B)/C)/D) and answer-key format is recognized
for existing decks as well as newly created notes. New notes persist structured
choices. No user library is replaced and old backups still decode.

## Automatic short-answer marking

Enable AI answer marking in Settings > ChatGPT, connect a plan-enabled account,
and load/select an available model. The toggle explains transcript/note sharing.
Local exact answers can be accepted without an AI request. Other answers use
Responses streaming with store=false, stream=true, a bounded request/output,
validated completion, evidence IDs, and rejection of unsupported feedback.

Retrieval runs locally: the current answer key, relevant same-deck notes, and
matching notebook prose are sent as evidence. This is lexical retrieval rather
than an embedding index. The saved answer is the default rubric. Marking returns
correct/partial/incorrect/unclear, mapped to Good/Hard/Again/no grade. No Easy
is inferred. AI failures and usage limits leave the question ungraded. Manual
reveal and ordinary grading remain available for short-answer fallback.

Results persist separately from the FSRS rating, with chosen option or AI evidence
IDs, without raw audio or transcript storage. Grade and feedback are committed
atomically; Next advances separately. Duplicate/concurrent submission cannot
record two grades. Undo retains the existing correction/history semantics.

## Audio implementation and limitations

Kokoro PCM playback goes through AVAudioEngine alongside voice-processed input
for echo cancellation. A bounded microphone stream feeds Silero's streaming
speech detector and Parakeet. The detector receives 256 ms windows, with one
second of end-of-utterance silence. One prior audio window is retained to preserve
the initial word. Speech onset stops the player and cancels queued synthesis and
pending AI marking. Resumed speech during assessment extends the uncommitted
answer. Recognition and synthesis run outside the audio-render callback.

Interruption latency, actual speaker echo, road noise, recognition accuracy,
Bluetooth routing, and battery usage require physical live-audio measurements.
Native compilation and model initialization do not certify those behaviours.
Kokoro has upstream intermittent native synthesis crashes on recent iOS releases.
A successful smoke check cannot rule those out. A production fallback voice and
screen-locked/background mode remain release work; this is a foreground preview.

The development argument --prepare-local-voice loads models without starting the
microphone. Documents/voice-model-status.txt contains setup stage/results only.
Credentials remain in ChatGPTAuth's device-only Keychain and never enter backups.

## Validation

Full Swift suite: 124 tests, one existing skip, zero failures. Assessment tests
cover matching/ambiguity, negation, legacy decoding, concurrent first submissions,
feedback resumption, Good/Again mapping, skip, undo, revealed-answer rejection,
notebook retrieval, and invalid/unsupported AI evidence. Signed iPhone build passes.
Live OAuth inference and live microphone accuracy are not covered by unit tests.
