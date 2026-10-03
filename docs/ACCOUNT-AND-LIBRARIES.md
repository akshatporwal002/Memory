# Account screen and separate libraries

Implemented on `akshat/ipad-support`, October 4, 2026.

## User experience

- One themed account screen offers ChatGPT, Google, native Apple, and email verification. ChatGPT uses the existing secure browser OAuth; it is not a separate settings journey.
- ChatGPT's verified identity opens an isolated local profile and supplies AI access. It does **not** create a Supabase session. Its cloud library sync requires a supported server identity integration before enabling it.
- Google/Apple/email use Supabase Auth. Cloud synchronization remains behind the hosted-pilot switch. Email templates must send the verification token (`{{ .Token }}`); provider credentials, callbacks and Apple capabilities require deployment configuration.
- The Library picker creates named libraries, starts them empty and remembers the selected library per account on this device. Each device can choose a different library without copying decks.
- Deck context menus move a notebook and its children to another library while retaining IDs and study history. Device-only libraries accept newly created/imported content; moving already uploaded content into one cannot promise to recall remote copies.
- Chats, retrieval, folders, study and PDF drafts follow the selected library. Switching stops active AI/audio generation and invalidates pending repository writes. Sign-out returns to the separate local library.
- Device-only content and its files are excluded from cloud projection. Shared account libraries use private catalog/membership records, with account permissions enforced by the existing server operations.
- Native exports/restores operate on the active library. Other libraries are retained by the repository when replacing the active one; export libraries individually for recovery.

## Verification and boundaries

Six library tests cover isolation, restart, stale writes, moving decks, device-only projection and local ChatGPT profiles. A two-repository fake-server test checks named-library sync without duplicate decks or uploading device-only content. The isolated feature suite passed (201 tests, one skipped); the concurrent working tree also passed all 204 tests. Three iPhone UI tests passed for the unified account, inline email form and Library creation/switching. The iPad landscape traversal passed, including Library, deck, questions, notes, Activity and Settings.

Screenshots are under `current_ui/Settings/Account` and `current_ui/Library/Libraries`, with the preceding iPhone screen retained as `previous.png`. Captures use fixtures, not authenticated provider sessions. Hosted authentication, email delivery and cross-device live synchronization still require deployment acceptance; no hosted provider settings were changed by this implementation.

ChatGPT's account can be used by its owner on multiple devices; this does not authorize sharing credentials between different people. See [OpenAI's account policy](https://help.openai.com/en/articles/10471989-openai-account-sharing-policy), [Sign in with ChatGPT](https://developers.openai.com/siwc/token-sharing-open-source), and [Supabase email OTP](https://supabase.com/docs/reference/swift/auth-signinwithotp).
