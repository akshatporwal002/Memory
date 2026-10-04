# Cloud speech implementation checkpoint

Status: transport implemented and tested with fixtures, not wired into study capture or enabled for users. No live provider audio call was made.

## Implemented

- Separate `TranscriptionProvider` and `SpeechOutputProvider` interfaces. Marking remains the independently selected grounded AI workflow.
- Personal OpenAI transcription uses multipart audio with JSON output. It supports explicitly selected Mini Transcribe, Transcribe and Whisper models; no silent fallback. File limits, language fields and model choices are checked before networking.
- Original transcript text is preserved, including mistakes and negations. Expected answers are never provided as transcription hints. Empty, oversized or malformed results are rejected rather than graded.
- Personal OpenAI speech requests return bounded WAV data, validate the file signature and reject incompatible model/voice pairs. Output is not played by the transport.
- Ephemeral sessions block redirects and credential-bearing cookies/cache. Cancellation stops consumption; errors omit provider bodies and API keys.
- Requests carry a correlation ID, not an assumed idempotency guarantee. There are no automatic retries. Interrupted delivery is reported as uncertain because a personal provider may already have processed and charged the request.
- Four fixture tests cover binary multipart preservation, no answer leakage, verbatim transcription/usage, no retries, secret-safe errors and rejection of non-audio output.

## Next implementation work

1. Protected device-local audio storage and account-scoped durable jobs, with capture saved before session advance.
2. Continue/Wait review behavior, ten unresolved jobs, two transcription workers and one marking worker.
3. Version/evidence checks, exactly-once scheduling, transcript correction and stale-worker rejection.
4. Local, personal-key and managed entitlement paths; sandbox StoreKit and authoritative managed billing interfaces. Production charging remains disabled.
5. Microphone capture, speech interruption/echo prevention, provider selection, first-use disclosure and accessible iPhone/iPad settings.
6. Google audio, Vertex server configuration and optional feature-flagged combined audio adapter.
7. Live recording benchmarks and correct landscape captures before claiming audio/UI acceptance.

Contracts checked against [OpenAI file transcription](https://developers.openai.com/api/docs/guides/speech-to-text) and [OpenAI text to speech](https://developers.openai.com/api/docs/guides/text-to-speech). These establish request formats; they do not establish this app's live recognition quality or entitlement readiness.
