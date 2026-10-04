# Inline account controls and connection lifecycle

Implementation branch: `akshat/overnight-learning-system`.

## Changes

- AI & Connections now contains sign-in choices directly. A connected ChatGPT account opens Manage ChatGPT; its detailed connection controls no longer dominate the main settings page.
- Common action buttons use filled capsules. Utility settings use flat lists and inline errors instead of enclosing cards.
- Vault migration removes disconnected registrations and collapses repeated registrations by verified subject. It preserves distinct subjects even when their email addresses match, the active registration and acknowledged plan usage. New registrations replace previous registrations for the same identity; local sign-out removes that identity's registrations.
- Google and native Apple linking operate under the existing Supabase user. The returned user must match; a different account is not silently merged. Browser linking ownership survives restart for fifteen minutes and is removed after completion, cancellation or sign-out.
- Email linking uses Supabase's verified email-change flow. It establishes/replaces the account's email login rather than creating unlimited email aliases. Secure email-change deployments can require codes from both old and new inboxes.

## Configuration still required

- Set `EngramAppleSignInEnabled` to true only after Apple Developer capability/provisioning, Apple provider configuration and an actual-device sign-in/linking test succeed. It defaults to false on both platforms; the UI explains that setup is pending.
- Enable manual identity linking in the Supabase Auth configuration and allow `engram://app-auth` in redirects. Configure Google credentials and email OTP templates. These settings were not changed during this stage.
- ChatGPT-only profiles remain local identities, not fabricated Supabase sessions. First cloud sign-in retains the explicit library-transfer choice.
- Hosted account linking, live revocation and cross-device sync require authenticated acceptance tests. Fixture UI captures do not establish that those services are configured.

## Evidence

- Mac package suite: 210 tests executed, one skipped, zero failures. New cases cover duplicate identity migration/replacement, distinct subjects with identical emails, client identity reuse rejection and persisted callback ownership/expiry.
- Exact staged source passed 207 package tests, one skipped, zero failures. iPhone light capture, iPhone dark account/email/library flow, and iPad landscape account/email capture passed.
- Screenshots are retained under `current_ui/Settings/Account`, grouped by presentation, with current and one previous image.
