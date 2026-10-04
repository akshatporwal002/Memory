# Tutor foundation validation — 5 October 2026

`swift test --filter TutorWorkspaceTests` ran in the existing Mac checkout and reusable `.build` cache: four tests passed, zero failures.

Coverage: pending/guardian-required/revoked consent does not share progress or consume student capacity; five-student limit and stale-version conflicts; sequential assignment revisions and owner-only publication; assigned-question filtering, outsider rejection and revocation clearing shared projections; Codable round trip.

This is an application domain contract, not deployed authorization. Actor IDs must ultimately come from authenticated server sessions. Consent must be backed by verified server records. Capacity/version changes must execute transactionally on the server. The local service alone does not enforce a multi-device race or guardian verification.

No tutor UI, hosted migration, invitation, subscription, AI report or real student-sharing flow has been enabled. No phone installation was performed for this foundation. Existing iPhone/iPad layout files were not changed.

Evidence: `.build/setup-evidence/tutor-tests.log`. No disposable build directory or stay-awake helper was created; existing caches remain reusable.
