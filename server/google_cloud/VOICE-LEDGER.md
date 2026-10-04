# Durable voice ledger preparation

`voice_ledger.py` is a sandbox-only server accounting foundation. It is disabled by default and rejects production. No hosted wallet, credits, purchase or provider dispatch was created. This is not an Apple signed-transaction verifier or an HTTP billing API.

## Implemented

- SQLite transactions serialize purchase grants, reservations, dispatch state and settlement across processes/connections. Account/environment/operation keys bind each reservation; verified Apple transaction IDs cannot be granted twice or reassigned to a different account.
- Integer credit units avoid floating-point wallet arithmetic. Rate versions are persisted and immutable. Reservations freeze provider, model, purpose, unit rate and maximum usage. The host defines usage-unit meaning/rates; no illustrative launch prices are configured.
- Available balance subtracts both completed charges and outstanding holds. Concurrent reservations cannot spend the same funds. Settlement releases unused reserved units and records the actual charge once; a conflicting replay is rejected.
- `begin_dispatch` commits the exact payload hash before networking. It can only execute once for an operation. Restarted `dispatching` or `uncertain` records remain held and cannot resend or release automatically. A verified usage receipt can settle uncertain delivery without another provider call.
- Undispatched reservations can be released idempotently. Purchased credit records have no time expiry. Provider usage exceeding the reservation is retained for reconciliation rather than charging an unapproved amount.
- This ledger covers managed transcription/speech-output only. Personal keys and local voice never reserve or deduct managed credit. Subscription entitlement verification remains separate.

## Host integration contract

Construct the ledger with mandatory `authenticate` and `verify_purchase` callbacks. `authenticate` must return the verified Engram account UUID for the current request; never read the identity from a caller-supplied account field. `verify_purchase` must verify Apple's signature chain, bundle/app/product/environment, appAccountToken, revocation and product-to-credit grant mapping before returning `VerifiedTopUp`. A fixture callback is not production verification.

Keep the SQLite database in protected server storage outside the repository/mobile bundle. Local database files are ignored. The database path and callbacks are trusted server configuration. This local SQLite implementation demonstrates durable transaction semantics; it is not a substitute for the hosted database/permissions architecture.

The server route must validate disclosure, provider capability, request limits and the current account before reserving. It must choose the maximum usage and immutable rate itself, bind the payload, journal dispatch immediately before a billed request, and settle only from verified provider usage. Do not expose `settle`, purchase credit amounts or `begin_dispatch` as unrestricted client inputs.

Reserve and dispatch each paid audio operation independently with a stable UUID. Grading retries reuse the saved transcript and its completed transcription charge; they must not create another audio operation. Successful transcription remains chargeable when later grading fails.

No adapter is automatically connected to this ledger. The existing GCP authorization callback must validate the reservation/model/purpose/payload. Place the dispatch transition immediately before transport dispatch, not before credential acquisition; a rejected credential request did not send audio. Any failure after the dispatch journal requires receipt-based reconciliation or a verified no-dispatch resolution, not blind retries.

Combined Live sessions need their own bounded session-rate/reservation/settlement contract; this per-operation ledger does not pretend to price or settle Live audio chunks.

## Remaining before activation

Apple JWS verification, Server Notifications/refunds/revocations, subscription entitlements, reservation expiry for provably undispatched work, provider receipt recovery/verified rejection release, immutable hosted rate configuration, authentication/permissions, migrations and backups, hosted wallet endpoints, mobile purchase integration and StoreKit sandbox testing remain outstanding. In particular, a dispatched hold is intentionally conservative; staff reconciliation must resolve it before enabling a user pilot.

Nine local fixture tests pass, including a two-connection reservation race and reopening the database after dispatch. They use temporary databases and fake verified receipts; no real Apple purchase, Supabase write or billed provider call occurred. iPhone/iPad purchase UI and physical-device acceptance remain separate gates.

## Verified revocation contract — 4 October 2026

Optional `verify_revocation` is disabled unless the trusted host supplies it. It must verify the notification JWS chain, bundle/app ID, notification type (an actual refund/revocation), nested transaction, product, environment, account token and event UUID before returning `VerifiedRevocation`. Ordinary renewal/status events must not be mapped to this type. A client cannot submit a credit amount or an unverified notification to remove funds.

`accept_revocation` binds the verified event to the authenticated account and stored transaction/product. It persists a tombstone even before purchase arrival. Duplicate notifications/event IDs are idempotent; conflicting identities reject. Purchase restore cannot regrant revoked funds. Host notifications must execute with a trusted affected-account context; the app-session callback contract is not a Server Notifications endpoint.

Available credit excludes revoked grants. Already spent usage and dispatched/uncertain holds remain intact; a deficit is retained, preventing new reservations/dispatch until valid funds cover it. Undispatched reservations can still be released. Negative balances must be presented as an account adjustment by the host, never silently converted into a new purchase or unlimited usage. This foundation handles full grant revocation; refund reversals and partial refunds need explicit verified adjustment semantics before activation.

Fourteen ledger tests now pass; the full server fixture suite passes 39 tests. These are temporary databases and fake verified receipts, not real refunds. Apple JWS verification, hosted notification routing, subscription entitlement handling and production activation remain outstanding. Earlier nine-test figures describe the pre-revocation revision.
