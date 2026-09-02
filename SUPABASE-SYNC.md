# Supabase sync foundation

This branch adds the shared-library sync contract and a reproducible Supabase schema. It does **not** connect Engram to a hosted project yet: no project URL, publishable key, account provider, or user data is present in this repository.

## Data model and safety boundary

Each signed-in user owns library rows. Devices append immutable, sequenced operations and retain an independent pull cursor. The client sync layer treats operation payloads as opaque `Data`; a later encryption codec can turn those payloads into ciphertext without changing retry, ordering, or authorization rules.

The coordinator only uploads, downloads, acknowledges explicit server acceptance, and persists a forward-only cursor. It deliberately does not apply operations to a `LibrarySnapshot`. Applying a remote operation, reconciling a card edit, and changing a schedule must happen through an explicit application transaction after the user-visible conflict policy is designed. A network retry therefore cannot silently reschedule a card or alter an in-progress session.

Media bytes are not included in the operation log. `mediaReference` is reserved for a future content-addressed Storage design with a separate, tested bucket policy.

## Schema setup

1. Create a Supabase project and enable the sign-in methods Engram will support.
2. Apply [`supabase/migrations/20260902191048_engram_sync_foundation.sql`](supabase/migrations/20260902191048_engram_sync_foundation.sql) using the Supabase CLI or SQL editor.
3. Confirm that the `public` schema is exposed to the Data API if the project uses the new opt-in exposure setting. The migration grants only `authenticated`, never `anon`, and enables RLS on every exposed table.
4. Run allow/deny RLS tests against a local or hosted project before enabling a client transport. The required cases are: anonymous read/write denial; one user cannot read or write another user's library; an owner can create, read, and update its library; an owner can append but cannot update/delete an operation; and one owner can only advance its own checkpoint.
5. Add the project URL and **publishable** key through the platform's secret/configuration mechanism. Do not commit them. A service-role or secret key must never ship in an Apple client.

The migration records `owner_id` on every table so policies can use `(select auth.uid()) = owner_id` without user-editable JWT metadata. It gives the client no `UPDATE` or `DELETE` grant on the append-only operation table.

## Implementing the transport

`EngramSyncTransport` is the only network-facing boundary. Its production implementation should use an authenticated Supabase Swift client, obtain the access token from the platform auth session, and map `bytea` payloads to the SDK's supported base64 representation. It must not use a service role, trust user metadata for authorization, or report a successful sync before the server returns accepted IDs.

The existing tests exercise the contracts and retry safeguards without a network dependency. A hosted verification remains required once a project and non-production test accounts are supplied.
