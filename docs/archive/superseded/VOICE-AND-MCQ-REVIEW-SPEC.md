> Historical local document preserved on 5 October 2026. Implementation and validation claims below describe the earlier local work and have not been reverified against current main.

> Archived on 5 October 2026 from main `381c917`. This is historical context, not current implementation guidance. Outstanding work is tracked in [the backlog](../../BACKLOG.md); newer requirements take precedence.

# Voice tutoring and interactive MCQ review

Status: agreed feature plan, not an implementation or release claim.

This specification records the product decisions made on 30 September 2026. The
existing voice preview is described in [OFFLINE-VOICE.md](OFFLINE-VOICE.md). This
plan replaces its sequential speaking/listening and explicit grading commands.

## Intended experience

Learners can answer naturally by voice or select an MCQ choice on screen. The
app marks the first submitted answer, provides brief feedback, and schedules the
card through FSRS. Users do not need to say “grade good” after each answer.

Voice mode remains optional, with a toggle in Settings and a microphone control
in review. Touch and voice use the same question, choices, answer key, and saved
result. Ordinary flashcards remain usable when voice or AI is unavailable.

## Structured questions

Represent MCQs as a question prompt, ordered choices with stable identifiers and
display letters, a correct choice identifier, an explanation, and source
references. The first version targets single-answer MCQs. Multiple-answer MCQs
need separate interaction and marking rules before support is claimed.

Short-answer questions have an expected answer, essential concepts, accepted
equivalents, important contradictions, and supporting source passages. Missing
or contradictory answer keys must block automatic marking.

The current AWS sample embeds options in its prompt text. Convert that sample to
structured choices. Existing user content must remain intact; conversion must
not silently guess an answer key for arbitrary imported text.

## MCQ layout and touch interaction

- Show the prompt above the choices.
- Put each choice on its own line in a full-width button. Long choices wrap.
- Show the letter and choice text together, with generous touch targets.
- The first tap selects a choice and shows “Tap again to confirm.”
- A second tap on the same selected choice submits it.
- Tapping another choice changes the selection without submitting.
- These are two deliberate taps; there is no rapid double-tap timing requirement.
- Provide an explicit accessible Confirm action for VoiceOver and alternative
  input. Do not require two VoiceOver activation gestures to discover submission.
- After submission, disable further answer submission, mark the selected choice,
  identify the correct choice, and show the explanation.
- Keep the result visible until the learner chooses Next. Saving a grade must
  not immediately replace the question before feedback can be read.

Selection is provisional. Submission records the first answer exactly once.
Simultaneous touch and voice events must not save two grades.

## MCQ spoken answers

Accept a letter, a phrase such as “option B,” an unambiguous letter alias such as
“Bravo,” the choice text, or a distinctive equivalent description. A clear
spoken choice submits directly; uncertain recognition asks for clarification.

Resolve against all choices rather than checking overlap with only the correct
answer. Normalize case, punctuation, service aliases, and appropriate acronyms.
Distinctive vocabulary and the difference between the best and second-best
match can assist selection. Shared generic words do not establish a match.

Do not grade by counting unique matching words alone. Negation, contradictory
statements, and corrections matter. “S3 is not object storage” must not become
correct because it contains “S3” and “object storage.” Recognize an explicit
correction such as “B, actually C” before submission. Conflicting choices without
a clear correction require clarification.

Clarification should be brief, for example “Did you mean B, Amazon S3?” No grade
is saved until a choice is resolved. Silence is not an incorrect answer.

## Marking and FSRS

Use FSRS's existing ratings internally. MCQs expose pass/fail, not the four
manual recall-rating buttons.

| Question type | Marking result | FSRS rating |
| --- | --- | --- |
| MCQ | Correct | Good |
| MCQ | Incorrect | Again |
| Short answer | Correct, essential concepts present | Good |
| Short answer | Partial, some concepts missing or inaccurate | Hard |
| Short answer | Incorrect, central answer wrong | Again |
| Either | Unclear recognition or evidence | No grade; clarify |

Correct does not automatically mean Easy. Do not assign Easy merely because a
response is correct or arrived quickly. A hint or revealed answer must not turn
an initial failed attempt into an unassisted success.

Save question type, first submitted answer, marking result, whether assistance
was used, and the scheduling rating as distinct information. Define transcript
retention separately; recording a result does not require saving raw audio.
Provide a rating correction/undo path with the existing review-history semantics.

## AI marking for short answers

Start with local rules for explicit accepted equivalents where they are reliable.
Use optional AI marking for natural explanations, paraphrases, and ambiguity.

After speech finishes, send a compact request containing the question, answer
transcript, rubric, and relevant source passages. Retrieve supporting passages
locally from the learner's notes when needed. For small authored questions, the
stored explanation and reference can supply the evidence without a broad search.

The model returns a structured result: correct, partial, incorrect, or unclear;
a brief reason; and the rubric concepts supported or missing. Treat confidence
as an aid, not proof. Allow abstention when transcription, rubric, or evidence is
insufficient. Validate the response before changing review history.

Feedback should be short by default. “Explain” requests more detail. A failed
request, invalid response, usage limit, or missing connection must not count as
an incorrect answer. Offer retry or manual assessment while retaining the turn.

Use a fast model available to the signed-in account, selected using measured
latency and marking quality. No specific model is fixed by this plan.

## Interruption and conversational turns

Keep microphone capture active during TTS and detect the learner's speech before
waiting for a transcript. Stop playback and cancel queued speech as soon as
speech onset is confirmed. Keep a short rolling audio buffer so the first word
or a brief letter is preserved.

Use echo cancellation and voice detection so playback cannot interrupt itself
or become the learner's answer. Start by evaluating Apple's voice-processing
audio path; evaluate FluidAudio LocalVQE if needed. Its live integration must be
tested rather than assumed from model benchmarks.

Proposed interruption target: roughly 200–300 ms after clear speech onset. This
is an acceptance target to measure, not a current performance claim.

Use end-of-utterance detection with a tunable silence allowance, initially around
one second. Natural thinking pauses must not repeatedly split answers. “Done”
can explicitly submit a spoken answer. If speech resumes during marking, cancel
the pending result and continue the same unsubmitted turn. A late AI response
must never grade a different card or a superseded answer.

Once an answer is committed, further speech controls feedback or the next turn;
it does not silently submit another answer to the committed question.

## Commands and recognition quality

Use short controls: Stop, Repeat, Skip, Explain, Next, and Done. Interpret them
according to the current turn state so ordinary answer words are not mistaken
for controls. Stop must promptly stop playback/listening; manual controls remain
available. Skip must not be saved as an incorrect answer.

Remove mandatory “grade good” commands from automatically marked questions.
If manual assessment remains available, use simpler phrases such as “got it”
and “try again.” Do not globally rewrite “great” to “grade.” Known recognition
variants may be accepted only within a narrow, explicit command context.

Evaluate Parakeet on actual speech, including Australian accents, AWS acronyms,
short letters, corrections, hesitation, and car noise. Measure answer-selection
accuracy, false submissions, interruption latency, endpoint timing, and battery
usage. Low recognition reliability should produce clarification, not a failed
learning result. Compare another recognizer if Parakeet misses these targets.

## Animation and accessibility

- Selection gains an accent border with a subtle settling animation and light
  haptic feedback where supported.
- Confirmation gives a soft green highlight and checkmark for a correct answer.
  Incorrect answers clearly distinguish the selected and correct choices.
- Explain correctness with text and symbols as well as colour.
- Fade the explanation into place below the choices.
- Transition to the next question only when the learner is ready.
- Avoid shaking, flashing, or celebratory effects that delay review.
- Respect Reduce Motion with immediate changes or simple fades.
- Support Dynamic Type, VoiceOver choice labels, selection/result announcements,
  and accessible confirmation.

Animation must not permit repeated submission or prevent interruption.

## Cost, privacy, and device operation

Parakeet recognition, Kokoro playback, structured MCQ marking, and reliable
authored answer rules run locally without per-request API charges. Download
models as optional assets and reuse cached files. Do not retain raw recordings
by default or log transcripts in diagnostics.

AI marking through ChatGPT uses the subscriber's applicable plan allowance and
requires internet and consent. It is optional and is not universally free.
Keep a useful free/offline MCQ and manual-review path. Before enabling AI marking,
explain that the answer transcript and supporting passages are sent to OpenAI.

Background audio, screen-lock operation, Bluetooth microphones, interruptions
from calls, and route changes require explicit implementation and device tests.
Do not describe the feature as ready for driving until these pass. The current
foreground-only preview does not satisfy this requirement. Start sessions while
parked and make all in-session operation possible without screen interaction.

Kokoro's documented intermittent synthesis crashes on recent iOS versions remain
a release concern. A successful synthesis smoke test is insufficient to establish
session stability; validate repeated use and provide a clearly identified fallback.

## Delivery sequence

1. Fix interruption, echo handling, cancellation, and endpointing. Validate on the
   physical phone before adding marking complexity.
2. Add structured MCQs, separate choice buttons, select-then-confirm behaviour,
   animations, accessible confirmation, and local spoken-choice matching.
3. Add atomic pass/fail scheduling and result/Next presentation. Test simultaneous
   inputs, retries, corrections, hints, and undo.
4. Add optional short-answer AI marking with local retrieval, validated responses,
   bounded request latency, cancellation, and failure recovery.
5. Validate Bluetooth, background/screen-lock operation, repeated synthesis,
   battery use, and realistic noisy audio before hands-free driving availability.

## Acceptance scenarios

- Speaking during a question or explanation stops TTS promptly and preserves the
  opening word. The tutor's own audio never submits an answer.
- “B,” “option B,” “Amazon S3,” and a distinctive equivalent select the expected
  MCQ choice. Shared keywords and negated statements do not silently pass.
- A first tap selects; a second tap on that same choice confirms. Changing choices
  never submits. VoiceOver can confirm through an explicit accessible action.
- Touch and voice racing to submit produce one first-answer result and one FSRS
  mutation. Double callbacks, retries, and transitions cannot grade twice.
- MCQ correctness maps only to Good or Again; uncertainty and skips save no grade.
- A natural short answer is marked against essential concepts and evidence, with
  partial credit represented by Hard. Recognition uncertainty triggers clarification.
- Speaking again during an AI request cancels the old assessment. Its response
  cannot change the next question or overwrite a revised answer.
- Offline/usage-limited AI falls back without recording a failure. Existing study
  data and review history remain intact.
- Selection, confirmation, feedback, and Next animations respect Reduce Motion,
  text size, and non-colour correctness indicators.

## Technical references

- [FluidAudio](https://github.com/FluidInference/FluidAudio)
- [LocalVQE echo cancellation](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Enhancement/LocalVQE.md)
- [ChatGPT plan inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
- [OAuth preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)

Verify upstream APIs, model compatibility, and OAuth limitations again when
implementation begins. Local retrieval is planned because this OAuth route does
not provide hosted file search.
