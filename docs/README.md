# Documentation

Start with [current implementation status](CURRENT-STATUS.md) and [remaining work](BACKLOG.md). Updated after main advanced to `ef0218d` on 5 October 2026. Later implementation reports supersede the earlier cleanup snapshot.

## Active requirements

- [October 5 review, batch grading, maths and tutor requirements](REVIEW-UI-BATCH-GRADING-AND-TUTOR-REQUIREMENTS.md)
- [October 5 approvals](OVERNIGHT-APPROVALS-2026-10-05.md) — Q1–Q10 and tutor/setup decisions.
- [Latest implementation decisions and validation](UNATTENDED-REVIEW-IMPLEMENTATION-DECISIONS.md)
- [External setup and verified product metadata](EXTERNAL-SETUP-STATUS.md)

- [Remaining work](BACKLOG.md) — unfinished features, configuration/testing gates and optional future candidates extracted from mixed historical documents.
- [Consolidated requirements — 4 October](OVERNIGHT-IMPLEMENTATION-REQUIREMENTS.md) — latest UI/accounts, providers/voice, billing, Testing decks, maths input and tutor specification.
- [Voice, transcription and payment specification — 4 October](VOICE-TRANSCRIPTION-AND-BILLING-PLAN.md) — detailed job/payment behavior, extended by the consolidated requirements.

**Conflict rule:** use the newest dated documentation. Later dated follow-ups inside a document override its earlier directions. The consolidated requirements explicitly override the voice specification's older deferrals of Google BYOK and paid cloud speech. Archived documents supply historical context only; they do not restore superseded requirements.

## Build, architecture and reference

- [Project overview](../README.md)
- [Apple build guide](README-APPLE.md)
- [Current architecture](ARCHITECTURE.md)
- [Accounts and named libraries](ACCOUNT-AND-LIBRARIES.md)
- [ChatGPT authentication](CHATGPT-SIGN-IN.md)
- [Anki compatibility](ANKI-COMPATIBILITY.md)
- [Imported card/media compatibility](MEDIA-COMPATIBILITY.md)
- [Screenshot export](SCREENSHOT-EXPORT.md)
- [Third-party notices](THIRD-PARTY-NOTICES.md)

Reference guides describe their supported scope. Historical test counts inside them retain their original dates; source presence or fixture screenshots do not certify current live services.

## Current feature reports

- [Overnight progress](OVERNIGHT-IMPLEMENTATION-PROGRESS.md) and [acceptance audit](OVERNIGHT-ACCEPTANCE-AUDIT.md) — later stage notes override earlier checklists.
- [Provider foundation](PERSONAL-AI-PROVIDER-FOUNDATION.md), [cloud speech](CLOUD-SPEECH-IMPLEMENTATION.md), [voice capture](VOICE-CAPTURE-INTEGRATION.md), [purchase/access foundation](VOICE-PURCHASE-AND-ACCESS-FOUNDATION.md).
- [Testing library](TESTING-LIBRARY.md), [mathematical input](MATH-EQUATION-ENTRY.md), [tutor assignments](TUTOR-ASSIGNMENTS-PLAN.md), [tutor validation](TUTOR-FOUNDATION-VALIDATION.md).
- [Account revision](ACCOUNT-CONNECTION-REVISION.md), [account validation](ACCOUNT-MANAGEMENT-VALIDATION.md), [Google sign-in repair](GOOGLE-SIGN-IN-REPAIR.md).

## Historical material

[Archive index](archive/README.md) contains completed implementation/review reports, superseded plans, research, benchmarks and old environment setup. Remaining work from those documents is consolidated in the backlog; their original decisions and evidence remain available. Raw logs/screenshots stay beside their existing consumers in `validation/`, `design/previews/` and `current_ui/`.

## Files kept beside their consumers

- [Agent definitions](../agents/README.md), [Anki fixture notes](../Tests/AnkiAdapterTests/Fixtures/README.md), and provenance records stay with their tools/tests/source.
- [SQLite provenance](../Sources/CSQLite/PROVENANCE.md), [archive-codec provenance](../Sources/CArchive/PROVENANCE.md), vendored licenses and [bundled acknowledgements](../App/Acknowledgements.txt) remain in place.
