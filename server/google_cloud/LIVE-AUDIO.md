# Combined audio preparation

`live_audio.py` prepares a server-side Gemini Live bridge. It is disabled by default, rejects production and has not been deployed or tested against a live SDK/provider. It changes no iPhone/iPad layout or grading rule.

## Connection contract

- The server host creates and owns a Google Gen AI SDK client configured with its explicitly selected Vertex project/region and ADC. Pass `sdk_connector(client)` to the bridge; no service-account credential belongs on the device. Verify model availability, SDK version and region before enabling sandbox.
- `LiveConfiguration(models=(...), enabled=False)` is independent of the synchronous provider configuration. Exact allowlisted model names must be chosen explicitly; no default model or automatic reconnect exists.
- Supply `authorize(operation_id, purpose, model, payload_sha256, sequence)`. Validate the authenticated learner, session environment, disclosure, model, reservation and current membership. Purposes: `live-connect`, `live-audio-input`, `live-audio-end`, `live-output`. This callback must bind a durable session/dispatch record; the fixture callback is not a deployed authorization or billing service.
- Call `open`, send bounded raw PCM16 mono input chunks at 16 kHz, and consume `receive_turn` once at a time. Repeat receive calls for subsequent turns on the same connection. `end_audio` flushes a paused stream. Always call `close` in the host's `finally` path and on account/device disconnection.
- Limits: one-second input chunks, two minutes total input, five minutes output/session duration, 4,096 normalized frames and bounded transcription/audio payloads. A watchdog closes idle sessions at the deadline. Cancellation, authorization revocation and uncertain network delivery close without automatic retries. Correlation IDs are not provider idempotency guarantees.

## Playback and learning boundaries

The bridge emits typed audio, provisional input transcript, spoken-response transcript, interrupt and turn-complete events. It never accesses application repositories, grading, scheduling or application tools. Provider tool calls are rejected. Hidden thoughts are omitted.

On local speech detection, the device should immediately flush playback and queued audio; `user_started_speaking` emits an interrupt event and changes generation. Suppress stale output until the server acknowledges interruption or finishes that turn. The receiver must reject old playback generations, close/suspension output and microphone echo. The bridge prepares these events; native audio-session, echo-cancellation and playback controls still need integration and hardware testing.

Live input transcription is a provisional conversational transcript. Do not use it to infer correctness or rewrite a learner's attempt. Review grading continues through the independent durable transcription/evidence-backed assessment pipeline. Any future combined-mode submission must preserve the original recording and content versions before scheduling; spoken feedback itself never awards a grade.

## iPhone and iPad integration still required

Use the existing compact voice controls and pending/results UI on iPhone; on iPad landscape keep the study panes and show status near existing input controls. Add explicit provider/cost disclosure, capability/readiness selection and close-on-background/account-change handling. No new always-visible panel is needed. Keep this mode unavailable until hosted transport, reservation/settlement, SDK compatibility and interruption/echo benchmarks pass.

## Evidence

Local tests inject asynchronous session fixtures and make no provider calls. They cover disabled/production/denied access, raw audio and provisional transcript separation, local interruption, malformed audio/tool rejection, no retries, cancellation, revocation and late-output rejection. They do not prove speech quality, SDK compatibility, hosted billing or device behaviour.

Protocol details were checked against Google's [Live capabilities guide](https://ai.google.dev/gemini-api/docs/live-api/capabilities) and [Vertex Live overview](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/live-api). Supported models and regions must be rechecked at configuration time.
