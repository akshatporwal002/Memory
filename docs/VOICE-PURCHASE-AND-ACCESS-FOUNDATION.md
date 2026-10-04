# Voice access and purchase foundation

Status: access contract and StoreKit adapter implemented; not connected to production billing or recording settings. No purchase was initiated and no hosted credit was created.

## Implemented boundaries

`VoiceWorkProcessor` now requires an explicit authorization closure. The composition root must check account ownership at every stage and audio access before transcription dispatch. A rejected authorization saves a needs-attention job, retains its recording and never invokes the provider. Test fixtures explicitly supply their own authorization; the processor has no implicit allow-all default.

`VoiceAccessPolicy` keeps sandbox and production separate. Production is disabled by default. Personal-key and local audio require an unrevoked, unexpired entitlement for the current account/environment. Personal keys do not replace the subscription and neither path uses managed reservations. Cloud disclosure is bound to account, provider, transcription/speech-output purpose and disclosure revision. Cloud providers cannot claim the local path to avoid disclosure.

Managed dispatch requires configured service access and a server-issued reservation for the exact account, operation, provider, model, purpose and environment. The reservation must be unexpired and contain a rate version. These checks complement server enforcement; a client-created value is not proof of wallet funds. The backend must authenticate, verify and consume its own reservation when processing audio.

`VoiceBillingBackend` defines entitlement retrieval, signed purchase verification, usage reservation, release and settlement. Implementations must use authenticated account ownership and idempotent operations. Signed purchase strings are private transport data, never library entities or logs.

`VoicePurchaseController` prepares StoreKit 2 product loading, localized prices through `Product`, purchase, pending/cancelled outcomes, restore and transaction updates. It binds purchases to the Engram account UUID using appAccountToken. Before opening a purchase, it requires a verified AppTransaction matching the configured environment; DEBUG builds cannot configure production purchases. Only locally verified transactions for configured products and the selected environment are submitted. Local Xcode transactions are rejected by this hosted verification path.

Transactions finish only after matching server acknowledgement. Interrupted verification leaves them unfinished for replay. Restore checks current entitlements and unfinished consumables; finished top-ups must come from the server wallet, not replayed client credit. Account changes invalidate pending result application. Revocations/refunds must be handled by authoritative verification/server notifications, not by trusting a cached client balance.

Implementation reference: [Apple Transaction documentation](https://developer.apple.com/documentation/storekit/transaction). Compilation is not live purchase verification.

## Configuration and remaining work

- App Store Connect subscription and consumable product IDs, subscription group, storefront prices and proceeds are not configured. The US$2/month and US$10 top-up remain planning targets; UI must display actual localized StoreKit prices.
- Hosted purchase verification, App Store Server Notifications, wallet storage and idempotent usage ledger still need implementation and deployment. No service-role or provider secret belongs in the app.
- Verify signed transaction chain, bundle/app ID, product, environment and account token server-side. Uniquely index environment plus Apple transaction ID; never grant twice on purchase/update/restore races. Handle refunds/revocations and preserve paid credits without time expiry.
- Reservation/submission/settlement must use stable operation IDs and locked rate versions. Audio success remains billable if grading fails; marking-only retries reuse transcripts. Server settlement uses provider-reported usage, precise integer accounting and verified storefront proceeds. No illustrative price is a live settlement rate.
- Fetch wallet and subscription state on foreground/restore/account change. Do not trust backups/preferences. Sandbox and production databases/credentials/ledgers must be separate; production must reject test balances and Xcode JWS fixtures.
- Connect these contracts and recording to the app composition root, then implement compact iPhone and landscape iPad provider/payment/pending controls. Existing local voice UI still uses its earlier path; do not claim these checks govern it until that integration is completed.
- Add StoreKit sandbox integration tests, authoritative ledger tests, purchase replay/pending/refund tests, expiry/cross-device tests and production-disable tests before activation. Provider and capture benchmarks remain separate gates.

## Verified evidence

Isolated Mac package run: 246 tests, one skipped, zero failures. Five access-policy tests check production disablement, subscription/key requirements, disclosure binding, managed configuration/reservation binding and the local-path boundary. The sixth worker test confirms denied access retains audio without provider calls. The StoreKit adapter compiles on the Mac; no claim of sandbox purchase, live server verification, credit settlement or phone deployment is made.
