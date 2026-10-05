# Engram — current implementation status

Updated 5 October 2026 after main advanced to `ef0218d`. New remote implementation supersedes the [earlier status snapshot](archive/superseded/CURRENT-STATUS-381c917.md). This documentation update does not rerun app tests or certify a release.

## Implemented foundations on main

- Local FSRS study, cards/decks/notebooks, portability, SQLite/account/named-library isolation, cloud adapter/outbox and permission groundwork.
- Inline account management/linking groundwork and ChatGPT deduplication; device-secure personal OpenAI/Gemini providers used across chat, grading and PDF workflows.
- Grounded PDF generation, offline rich Markdown/math/diagrams, shared assistant actions, conversations and mutation journal.
- Durable voice jobs, Continue/Wait, transcript correction/history replay, protected recording cleanup, foreground dispatch and personal-key speech integration groundwork.
- Repeat-safe local Testing content, structured mathematical palettes/resize/undo, and newer inline maths keyboard within existing answers.
- Deferred typed/confirmed-voice marking, batch preferences, optional post-submission reference reveal, durable feedback/disputes and exact-once scheduling.
- Tutor workspace/drafts, subject/student/assignment-scoped presentation and consent-gated account-scoped research queue. Hosted tutor sharing and research upload remain disabled/dependent on deployment gates.
- Adaptive quiz/themes, calendar forecasts and reminders; later UI/device changes are recorded in the current reports.

Implementation details and actual limitations are in [overnight progress](OVERNIGHT-IMPLEMENTATION-PROGRESS.md), [acceptance audit](OVERNIGHT-ACCEPTANCE-AUDIT.md), [latest review implementation decisions](UNATTENDED-REVIEW-IMPLEMENTATION-DECISIONS.md) and the feature reports linked from [the documentation index](README.md).

## Evidence and readiness

The latest review report records 303 package tests (one skip, zero failures), final simulator scenarios and an October 5 signed phone installation/launch. Its final merge note explicitly limits those results: they cover the integrated working source, while an exact separated-commit Mac test/build could not start after connectivity was lost. No fresh validation is claimed by this cleanup.

Provider calls, hosted sync/tutor/research, real purchases and large-library/device acceptance cannot be inferred from fixture tests. The [external setup report](EXTERNAL-SETUP-STATUS.md) records verified projects/App Store product drafts and remaining setup. Production charging and unconfigured managed execution remain disabled.

## Latest authority

Use [October 5 confirmed requirements](REVIEW-UI-BATCH-GRADING-AND-TUTOR-REQUIREMENTS.md), [approvals](OVERNIGHT-APPROVALS-2026-10-05.md) and later explicit follow-ups before conflicting older plans. Q1–Q10 are approved but not all implemented; later research consent and product pricing decisions supersede earlier unresolved notes. See [the current backlog](BACKLOG.md) for only remaining work and acceptance gates.
