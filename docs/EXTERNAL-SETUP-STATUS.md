# Engram external setup — 5 October 2026

## Google Cloud

Verified the user-created project **Engram**, `engram-510613`, in Chrome. Prepared `server/google_cloud/config.engram.example.json` with sandbox execution disabled and empty model/voice allowlists. No API calls, billing changes, service credentials or deployments were made by this task. LearnLens is explicitly excluded. Google free-credit balance and eligible services remain unverified; paid testing is disabled.

## OpenAI

Opened the API-key page in the user's signed-in Chrome account. On 5 October the billing overview showed **$0.00 credit remaining** and an **Add payment details** action. No API key was created/read by the agent and no payment or test call occurred. User should create a project-scoped key and enter it through the app's secure key flow, not chat. Before adding credits, keep automatic recharge off. OpenAI documents delayed prepaid cutoff and possible negative balances, so do not promise an absolute balance-only spending cap.

## Supabase

The repository identifies Engram's Supabase project as `heedprsusmrwxasdixbt`, and its dashboard tab is available in Chrome. The connected Supabase MCP currently lists only the unrelated `2026W1-Stocks-In-Hand` project, so no tutor migration or SQL was applied. Do not deploy Engram tutor sharing through that unrelated project. Hosted tutor permissions remain disabled until the Engram project is accessible and its RLS can be tested.

## Apple

Verified App Store Connect access. Existing Gradia is a different bundle (`Akshat.Gradia`) and was not modified. Created the separate iOS app record, with explicit team-access approval:

- Name: **Engram: Study & Recall** (the standalone name Engram was unavailable).
- Bundle: `dev.engram.study`; SKU: `engram-study`.
- App Store Connect app ID: `6819023861`.
- Primary language: English (Australia).
- Draft consumable: `dev.engram.study.voice.credits10`, Apple product ID `6819023766`.
- Draft monthly subscription: `dev.engram.study.voice.monthly`, Apple product ID `6819024288`.
- Voice access subscription group: `22439622`.

Both products are Prepare for Submission. The user explicitly approved US$1.99/month and US$9.99/top-up, the closest standard tiers to the prior US$2/US$10 targets, and both base prices were saved. Apple generates localized storefront prices from each US base price; these may differ from a currency conversion. The consumable, monthly subscription, and subscription group now have English (Australia) display names; both products have descriptions. Storefront availability, review evidence, server verification and sandbox test-account configuration still need completion. No app/product was submitted, no purchase occurred and production activation remains disabled. App Store Connect product drafts are shared metadata, not an isolated sandbox catalogue; only the test environment's transactions are sandbox transactions.

Review screenshots are retained in `.build/setup-evidence`. StoreKit product metadata is not evidence of a functioning wallet. Do not connect the purchase UI until authenticated server verification and sandbox ledger are ready.
