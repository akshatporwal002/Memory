# Personal AI provider foundation

Status: OpenAI/Gemini transport, device key storage, connection UI and shared workflow routing implemented; simulator validation is in progress. This does not enable cloud voice or app charges. Live personal-provider validation awaits credentials.

## Implemented

- `OpenAIAPIProvider` implements the shared `AIProvider` contract. It reuses the bounded, cancellable Responses streaming transport and terminal-completion validation.
- ChatGPT OAuth retains its own catalog format and function namespace. Personal OpenAI API accounts use the API's `data` model list and ordinary function definitions. Both keep `store:false` and local continuation history.
- Request model identity and opaque continuation ownership must match the adapter. Passing ChatGPT history to the personal API provider fails before an HTTP request. Reasoning continuation records keep their provider identity.
- Model discovery does not infer tool/audio capabilities from names. Tool support remains unknown until the selected model is checked. Listing an audio/embedding model does not assert that it supports chat.
- OpenAI/Gemini personal keys use separate, account-scoped device-only Keychain records. Add/update and deletion are explicit operations. Local syntax checks reject embedded whitespace/control characters; they do not establish provider acceptance.
- Keys are not Codable library data and are never added to model descriptors, synchronization, backups, UserDefaults or error messages. Account changes select storage by the active profile's stable identity and invalidate the catalog. Only non-secret credential revisions persist in preferences; a separate runtime epoch rejects interrupted requests after switching away and back.
- Gemini discovers advertised generation models and uses bounded REST streaming. It preserves opaque model parts and thought signatures for continuation, while rendering only ordinary text. Function arguments are released as normalized tool calls only after a successful terminal STOP. Failed/truncated streams cannot execute buffered calls.
- Provider-tagged model selections route chat, typed/spoken grading, grading discussions and PDF generation through the shared transport. Legacy unqualified model IDs resolve only to ChatGPT. Switching providers retains readable chat history without copying foreign opaque continuation state.
- AI & Connections contains masked OpenAI/Gemini key-entry pages. Validation discovers provider access before saving, removal requires confirmation, and controls block key mutation during AI work. Saved keys are scoped to the current app profile.
- Grading discussions retain the original attempt's model. An offline exact match without a model uses the explicitly selected grading model for its first discussion. Assessment ownership persists across restart and is updated when a discussion revises feedback.

## Remaining

- Transcription/speech-output adapters, durable answer jobs, managed billing and Vertex service preparation.
- Live validation with the user's configured provider credentials. No personal API request has been made with production credentials during this foundation stage.

## Verification and sources

The Mac regression suite passed 211 tests (one skipped, zero failures), including API catalog decoding, no guessed tool capabilities, provider-isolated continuation, key syntax/error redaction and cross-provider rejection before networking.

The combined working tree subsequently passed 224 tests (one skipped, zero failures), including Gemini terminal validation, signature retention, function-context tampering, key/profile isolation and durable non-secret identity revisions. Combined results also include unrelated peer work; exact staged validation is recorded separately in the implementation progress document.

API contracts were checked against [OpenAI function calling](https://developers.openai.com/api/docs/guides/function-calling), [OpenAI model listing](https://developers.openai.com/api/reference/resources/models/methods/list) and [Gemini content generation](https://ai.google.dev/api/generate-content). Fixtures do not establish live model quality, billing or account compatibility.
