# Engram — current implementation status

> Superseded snapshot of main `381c917`, retained after newer implementation reached main on 5 October. Use the [current backlog](../../BACKLOG.md) and [status](../../CURRENT-STATUS.md).

Reviewed 5 October 2026 against main `381c917`. This is a source/documentation review, not a new build or release certification. Other branches may contain additional work. Newer dated requirements override conflicting older documents; unfinished work lives in [BACKLOG.md](../../BACKLOG.md).

## Present on main

| Area | Implementation evidence | Remaining boundary |
| --- | --- | --- |
| Local study, FSRS, cards/decks, undo and portability | `Sources/StudyApplication`, `Sources/SchedulingAdapters`, `Sources/AnkiAdapters` | Supported Anki subset; complete platform acceptance still required |
| SQLite persistence and isolated accounts | `Sources/PersistenceAdapters/SQLiteLibraryRepository.swift`, `Tests/EngramTests/UnifiedAITests.swift` | Snapshot payload scaling still needs profiling |
| Named libraries and device-only content | `Sources/StudyApplication/LibrarySpaceRepository.swift`, `Tests/EngramTests/LibrarySpaceTests.swift` | Hosted/device acceptance; ChatGPT local identity is not Supabase identity |
| Cloud adapter, outbox and permission-aware sharing | `Sources/CloudAdapters`, `supabase/migrations`, `Tests/CloudAdapterTests` | Hosted pilot disabled in `project.yml` |
| Shared AI transport, app actions, conversations and undo journal | `Sources/AIInfrastructure/AIProvider.swift`, `Sources/Features/AssistantController.swift` | Live capability checks and broader provider/action parity |
| Typed feedback, discussion and accepted improvements | `Sources/Features/TypedAnswerController.swift`, `Sources/StudyApplication/AnswerAttemptService.swift` | Live grading quality; durable asynchronous voice jobs are separate work |
| Grounded PDF import, generation drafts and source-linked save | `Sources/Features/PDFLearningController.swift`, `Tests/EngramTests/PDFLearningTests.swift` | Live generation quality, OCR/diagrams and large-document limits |
| Offline rich Markdown/math/diagrams | `Sources/Features/RichContentView.swift`, `Sources/Features/Resources/RichContent` | Math rendering does not implement an equation keyboard |
| Foreground local voice and answer marking | `Sources/Features/VoiceStudyController.swift`, `Sources/Features/AIAnswerMarker.swift` | Hardware/audio reliability; new cloud voice/payment requirements unfinished |
| Adaptive review, themes, calendar forecasts and reminders | `Sources/Features/MultipleChoiceReviewView.swift`, `Sources/Features/DeckMemoryPanel.swift`, `Sources/Features/ReviewReminderController.swift` | Device reminder delivery and wider accessibility/performance coverage |

These rows identify source presence, not universal completion or successful live service operation.

## Existing validation reports

The [account/library report](../../ACCOUNT-AND-LIBRARIES.md) records isolated tests, fixture UI checks and its hosted-service limitations. Historical [minimalist UI](../completed/MINIMALIST-UI-VALIDATION.md), [PDF](../completed/PDF-LEARNING-VALIDATION.md), [review/themes](../completed/REVIEW-LAYOUT-THEMES-VALIDATION.md) and [integrated AI/cloud](UNIFIED-IMPLEMENTATION-STATUS.md) reports retain their tested revisions and scope. They include native builds, simulator checks and device installation reports, superseding the original Windows-only handoff's claim that no Apple builds had run. Their counts are historical and are not claimed as results for this checkout.

## Latest unfinished requirements

The [4 October consolidated requirements](../../OVERNIGHT-IMPLEMENTATION-REQUIREMENTS.md) cover direct account management/linking, more AI providers, cloud voice, durable answer processing, billing foundations, Testing decks, structured maths input and a tutor specification. They extend the [voice/payment specification](../../VOICE-TRANSCRIPTION-AND-BILLING-PLAN.md), including Google BYOK and optional cloud speech. See [the backlog](../../BACKLOG.md) for implementation gaps separately from configuration/testing gates and optional future ideas.
