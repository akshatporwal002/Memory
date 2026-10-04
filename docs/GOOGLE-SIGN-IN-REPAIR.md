# Google sign-in and account linking — 4 October 2026

## Confirmed cause and hosted repair

The Engram Supabase project had `http://localhost:3000` as its Site URL and no redirect URLs. The app already requests `engram://app-auth`, so Supabase rejected that destination and fell back to localhost after Google authentication.

Using the signed-in Chrome dashboard, set both Site URL and the exact redirect allowlist entry to `engram://app-auth`. No wildcard callbacks were added. Verified both settings in the dashboard. Enabled manual identity linking after explicit user approval; anonymous sign-in remains disabled and email confirmation remains enabled.

The redirect repair applies immediately to the installed app. A live Google sign-in on the phone remains necessary to verify the full round trip.

## App changes

- Keep the ChatGPT local profile active until the user accepts a cloud-account library. Cancelling the handoff preserves the original profile.
- Offer an explicit copy of the active ChatGPT profile's library when opening a new Engram account. Preserve the original and reject replacing an existing account library.
- Refresh verified login identities after successful account selection and restoration.
- Keep the existing ChatGPT AI connection independent of Supabase login identities. ChatGPT login alone does not create a Supabase user.

Google and Apple can be linked through the existing account controls when supported by the configured native authentication provider. Apple device provisioning is still a separate prerequisite.

## Validation and remaining work

Eight `LibrarySpaceTests` passed on the Mac, including two new handoff/isolation regressions. Google consent branding remains unchanged: its app name and branding must be configured in the Google OAuth project, and removing the Supabase callback domain from Google's sign-in display may require a supported custom auth domain. Do not replace Google's server callback with the native app URL.

No stay-awake script was launched for this repair; the previous helper is stopped.

The iOS Simulator app also compiled successfully with the account-screen changes. These app-source changes are not yet installed on the physical phone.
