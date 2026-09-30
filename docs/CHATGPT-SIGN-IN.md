# ChatGPT connection

Settings → ChatGPT → Continue with ChatGPT connects an optional ChatGPT account.
Eligible users can grant ChatGPT plan usage. This change adds authentication and
session management; it does not add generation, tutoring, RAG, or library sync.

The implementation follows OpenAI's public open-source flow:

- https://developers.openai.com/siwc/token-sharing-open-source/sign-in
- https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions
- https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations

Each installation keeps a stable host UUID and separately saved account/client
registrations. New clients register dynamically without an API key or secret.
The callback is HTTP IPv4 loopback on an ephemeral port at `/auth/callback`.
macOS opens the system browser; iOS presents Safari Services to keep the app
foregrounded while its listener runs. No custom URL scheme substitutes for
OpenAI's required loopback redirect. Requests time out, and users can cancel.

The auth module checks callback state, PKCE, nonce, issuer, audience, expiry,
and RS256/ES256 signatures against the issuer's JWKS. It rejects redirected token
requests, duplicate callback parameters, and changes to saved account identities.
Token response scopes determine plan permission. Tokens and the host record live
in device-only, non-synchronizing Keychain storage outside the study repository,
library exports, and defaults. Account/client mappings survive local sign-out;
access, refresh, and ID tokens are cleared. Failed remote revocation is disclosed.

Future AI adapters must obtain credentials through `validAccessToken()` so that
plan permission and serialized refresh/token rotation are enforced. Inference
must use the public Responses endpoint with `store: false` and `stream: true`.
ChatGPT plan usage currently excludes hosted file search and the Files upload API.

## Verification

On an Apple host, run `swift test --filter 'OAuthSecurityTests|OAuthClientTests'`,
then build both app schemes. On Windows, dot-source
`scripts/Enter-SwiftEnvironment.ps1`, then run `scripts/Test-ChatGPTAuth.ps1`.
Windows tests exercise the portable OAuth contract; they do not execute Keychain,
the Apple signature verifier, Network listener, or Safari Services.

Device acceptance: connect Plus/Pro; reject consent; cancel Safari; restart and
verify the saved account; reconnect a saved registration; switch accounts;
confirm the first-use plan notice; sign out with and without networking. Check
that iOS Safari returns to the app and macOS sandbox loopback works. Never capture
tokens, authorization URLs, or raw callback queries in logs or screenshots.
