# Tutor foundation validation — 5 October 2026

`swift test --filter TutorWorkspaceTests` ran in the existing Mac checkout and reusable `.build` cache: four tests passed, zero failures. The subsequent full package suite ran 284 tests with one skipped and zero failures.

Coverage: pending/guardian-required/revoked consent does not share progress or consume student capacity; five-student limit and stale-version conflicts; sequential assignment revisions and owner-only publication; assigned-question filtering, outsider rejection and revocation clearing shared projections; Codable round trip.

The next local stage adds an account-scoped JSON draft repository and a Settings → Tutor screen. Workspace drafts survive app restart without exposing student data. One repository test covers persistence, account isolation and stale writes. iPhone and iPad landscape UI tests cover workspace creation and reopening. These tests use the existing iOS 26.5 simulators and reusable DerivedData path. An initial iPhone UI test failed because its selector did not match the Settings row's accessibility label; the selector was corrected and the test passed. A later iPad run reported zero tests and was not counted; an explicit class run executed two UI tests with zero failures. The final iPad capture verifies the shortened sharing copy. A subsequent iPhone rerun found that Settings virtualizes the Tutor row below the fold; the test now scrolls to it, but SSH timed out before that correction could be rerun.

This is an application domain contract, not deployed authorization. Actor IDs must ultimately come from authenticated server sessions. Consent must be backed by verified server records. Capacity/version changes must execute transactionally on the server. The local service alone does not enforce a multi-device race or guardian verification.

No hosted migration, invitation, subscription entitlement, AI report or real student-sharing flow has been enabled. No phone installation was performed for this foundation. Existing iPhone/iPad study layouts were not changed.

Evidence: `.build/setup-evidence/tutor-tests.log` and the paired screenshots under `current_ui/Tutor/iPhone` and `current_ui/Tutor/iPad`. No disposable build directory or stay-awake helper was created; existing caches remain reusable.
