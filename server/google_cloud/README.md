# Google Cloud preparation

Server-only provider adapters, not a deployed API or billing server. No credentials are included or requested by the test suite. Sandbox dispatch defaults off; production dispatch is rejected even if the sandbox switch is enabled.

## Prepared

- Chirp 3 Speech-to-Text V2 synchronous recognition: bounded mono PCM16 WAV, explicit language/location, unmodified samples and transcript words, no reference-answer hints. Rejects recordings of 60 seconds or longer; streaming/batch handling is still required for longer answers. Current documented regions are US/EU, independent of the Sydney Supabase choice. [Chirp 3 methods/regions](https://docs.cloud.google.com/speech-to-text/docs/models/chirp-3), [recognize REST](https://docs.cloud.google.com/speech-to-text/docs/reference/rest/v2/projects.locations.recognizers/recognize).
- Vertex text generation: project/location/model allowlist, bounded messages/output, configured token budget, terminal completion required. Internal thought parts are omitted; function calls are rejected by this text-only preparation adapter, never displayed/executed as prose. Provider-neutral streaming/tool support remains future integration. [generateContent REST](https://docs.cloud.google.com/gemini-enterprise-agent-platform/reference/rest/v1/projects.locations.publishers.models/generateContent).
- Mandatory injected authorization before token acquisition or provider dispatch. No default permissive authorizer. Fixed Google endpoints, no credential-forwarding redirects, no automatic provider retries, bounded responses and error codes without provider bodies.

## Configuration when the account is ready

1. Copy `config.example.json` to ignored `config.local.json`. Set the real project ID, explicitly chosen processing regions and account-accessible model allowlist. Empty models deliberately fail validation. No region/provider substitution is made.
2. Validate with `Configuration.from_mapping(json.load(...))`. Keep `sandbox_enabled:false` until the authenticated server and sandbox reservation/accounting path exist. Enabling it can incur real Google provider costs; this switch does not create free usage.
3. Supply a server-side access-token callback using Application Default Credentials/workload identity. Keep service-account files and refresh tokens outside the repository and mobile build. ADC supports attached service accounts; the adapter itself does not read credential files or spawn `gcloud`. [ADC setup](https://docs.cloud.google.com/docs/authentication/application-default-credentials).
4. Inject an authorizer that verifies the Engram session, server environment, learner, operation ID, disclosure, exact model and reservation. This callback is a required integration contract, not proof those checks already exist.
5. Journal dispatch before sending. Reserve/settle usage through the authoritative backend; a timeout is uncertain delivery, not permission to send again. Correlation UUIDs are not provider idempotency guarantees. Connect returned text to the existing durable transcript/evidence-backed grading system.

## Still needed before deployment

Verified hosted auth/StoreKit accounting, durable dispatch receipts/settlement, rate/quota limits, streaming or temporary private batch-storage lifecycle for long audio, Vertex streaming/tools, Google speech output, Gemini Live, mobile transport/disclosure integration and live benchmarks. No GCP project, service, bucket, IAM permission or purchase was created. iPhone/iPad settings stay Not configured for managed GCP; no UI layout changed here.

## Fixture validation

From the repository root, with Python 3.10+:

```text
python -m unittest discover -s server/google_cloud -p "test_*.py" -v
```

Tests use injected transports, including bounds, no hints, verbatim negation/correction, completion/tool/thought handling, unavailable production, denied authorization, configuration injection, malformed Unicode and secret-safe errors. A mocked urllib opener tests read limits/redirect behavior. These tests establish local contracts, not real Google recognition quality, availability or hosted billing correctness.
