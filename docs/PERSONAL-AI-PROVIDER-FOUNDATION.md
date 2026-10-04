# Personal AI provider foundation

Status: transport/storage foundation implemented; connection UI and workflow routing are still pending. This does not enable cloud voice or charge users.

## Implemented

- `OpenAIAPIProvider` implements the shared `AIProvider` contract. It reuses the bounded, cancellable Responses streaming transport and terminal-completion validation.
- ChatGPT OAuth retains its own catalog format and function namespace. Personal OpenAI API accounts use the API's `data` model list and ordinary function definitions. Both keep `store:false` and local continuation history.
- Request model identity and opaque continuation ownership must match the adapter. Passing ChatGPT history to the personal API provider fails before an HTTP request. Reasoning continuation records keep their provider identity.
- Model discovery does not infer tool/audio capabilities from names. Tool support remains unknown until the selected model is checked. Listing an audio/embedding model does not assert that it supports chat.
- OpenAI/Gemini personal keys use separate, account-scoped device-only Keychain records. Add/update and deletion are explicit operations. Local syntax checks reject embedded whitespace/control characters; they do not establish provider acceptance.
- Keys are not Codable library data and are never added to model descriptors, synchronization, backups, UserDefaults or error messages. Future account UI must instantiate storage with the active profile's stable identity and clear in-memory keys when switching accounts.

## Remaining

- Gemini model discovery, content/function streaming and provider continuation handling.
- Masked key-entry/validation/removal UI, capability-aware provider/model pickers and shared routing for chat, grading and PDF generation.
- Transcription/speech-output adapters, durable answer jobs, managed billing and Vertex service preparation.
- Live validation with the user's configured provider credentials. No personal API request has been made with production credentials during this foundation stage.

## Verification and sources

The Mac regression suite passed 211 tests (one skipped, zero failures), including API catalog decoding, no guessed tool capabilities, provider-isolated continuation, key syntax/error redaction and cross-provider rejection before networking.

API contracts were checked against [OpenAI function calling](https://developers.openai.com/api/docs/guides/function-calling), [OpenAI model listing](https://developers.openai.com/api/reference/resources/models/methods/list) and [Gemini content generation](https://ai.google.dev/api/generate-content). Gemini remains pending; consulting its contract is not proof of an implemented adapter.
