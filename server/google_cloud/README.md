# Google Cloud preparation

Server-only provider adapters, not a deployed API or billing server. No credentials are included or requested by the test suite. Sandbox dispatch defaults off; production dispatch is rejected even if the sandbox switch is enabled.

## Prepared

- Chirp 3 Speech-to-Text V2 synchronous recognition: bounded mono PCM16 WAV, explicit language/location, unmodified samples and transcript words, no reference-answer hints. Rejects recordings of 60 seconds or longer; streaming/batch handling is still required for longer answers. Current documented regions are US/EU, independent of the Sydney Supabase choice. [Chirp 3 methods/regions](https://docs.cloud.google.com/speech-to-text/docs/models/chirp-3), [recognize REST](https://docs.cloud.google.com/speech-to-text/docs/reference/rest/v2/projects.locations.recognizers/recognize).
- Vertex text generation: project/location/model allowlist, bounded messages/output, configured token budget, terminal completion required. Internal thought parts are omitted; function calls are rejected by this text-only preparation adapter, never displayed/executed as prose. Provider-neutral streaming/tool support remains future integration. [generateContent REST](https://docs.cloud.google.com/gemini-enterprise-agent-platform/reference/rest/v1/projects.locations.publishers.models/generateContent).
- Google speech output: explicitly allowed voice/language, plain text capped at 4,000 UTF-8 bytes, and validated mono PCM16 WAV output at 24 kHz, capped at two minutes. Rejects malformed/truncated audio without retry. This uses Google's global Text-to-Speech endpoint, independently of Chirp/Supabase regions; returned audio is not automatically played or connected to grading. [synthesize REST](https://docs.cloud.google.com/text-to-speech/docs/reference/rest/v1/text/synthesize).
- Mandatory injected authorization before token acquisition or provider dispatch. No default permissive authorizer. Fixed Google endpoints, no credential-forwarding redirects, no automatic provider retries, bounded responses and error codes without provider bodies.

## Configuration when the account is ready

1. Copy `config.example.json` to ignored `config.local.json`. Set the real project ID, explicitly chosen processing regions and account-accessible model allowlist. Empty models deliberately fail validation. Add exact available voice names to `speech_output_voices` when speech output is wanted; its empty default disables speech output. No region/provider substitution is made.
2. Validate with `Configuration.from_mapping(json.load(...))`. Keep `sandbox_enabled:false` until the authenticated server and sandbox reservation/accounting path exist. Enabling it can incur real Google provider costs; this switch does not create free usage.
3. Supply a server-side access-token callback using Application Default Credentials/workload identity. Keep service-account files and refresh tokens outside the repository and mobile build. ADC supports attached service accounts; the adapter itself does not read credential files or spawn `gcloud`. [ADC setup](https://docs.cloud.google.com/docs/authentication/application-default-credentials).
4. Inject `authorize(operation_id, purpose, model, payload_sha256)` to verify the Engram session, server environment, learner, operation ID, disclosure, exact model/voice, exact serialized payload and reservation. Purposes are `transcription`, `speech-output` and `text`. Bind the hash in the durable dispatch record so an operation cannot be reused for different content. This callback is a required integration contract, not proof those checks already exist.
5. Journal dispatch before sending. Reserve/settle usage through the authoritative backend; a timeout is uncertain delivery, not permission to send again. Correlation UUIDs are not provider idempotency guarantees. Connect returned text to the existing durable transcript/evidence-backed grading system.

## Still needed before deployment

The optional combined-audio bridge is prepared separately in [LIVE-AUDIO.md](LIVE-AUDIO.md), with disabled-by-default configuration and injected SDK connection/authorization. It is not a deployed or mobile-integrated Live service.

The sandbox-only durable accounting foundation is described in [VOICE-LEDGER.md](VOICE-LEDGER.md). It requires verified-session/purchase callbacks and does not activate hosted billing.

Verified hosted auth/StoreKit accounting, durable dispatch receipts/settlement, rate/quota limits, streaming or temporary private batch-storage lifecycle for long audio, Vertex streaming/tools, Gemini Live, mobile transport/disclosure and speech playback integration, and live benchmarks. Provider usage may be billable even when returned audio fails validation; settlement must handle this before deployment. No GCP project, service, bucket, IAM permission or purchase was created. iPhone/iPad settings stay Not configured for managed GCP; no UI layout changed here.

## Fixture validation

From the repository root, with Python 3.10+:

```text
python -m unittest discover -s server/google_cloud -p "test_*.py" -v
```

Tests use injected transports, including bounds, no hints, verbatim negation/correction, completion/tool/thought handling, unavailable production, denied authorization, configuration injection, malformed Unicode, voice allowlists, WAV validation, exact payload hashes and secret-safe errors. A mocked urllib opener tests read limits/redirect behavior. These tests establish local contracts, not real Google recognition or voice quality, availability or hosted billing correctness.
