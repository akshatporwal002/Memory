> Historical local document preserved on 5 October 2026. Implementation and validation claims below describe the earlier local work and have not been reverified against current main.

> Archived on 5 October 2026 from main `381c917`. This is historical context, not current implementation guidance. Outstanding work is tracked in [the backlog](../../BACKLOG.md); newer requirements take precedence.

# Native Settings and Activity

Design reference: [Settings-iOS by zhrispineda](https://github.com/zhrispineda/Settings-iOS).
The reference's grouped lists, icon tiles, account row, value summaries, section footers,
and navigation hierarchy guide these screens. Engram uses public SwiftUI and Swift Charts;
no private preference bundles, Apple assets, or framework-localized strings are copied.

Implemented:
- Searchable grouped Settings with Appearance, Study, Scheduling, Voice, AI & Connections,
  Storage & Downloads, Backup & Restore, and About & Help detail pages.
- Immediate saving of validated study preferences; numeric daily-limit entry and stepper,
  localized hour picker, searchable time zones, and retention control.
- Listening/speaking sections, a temporary microphone recording/playback diagnostic,
  Kokoro preview, model preparation status, measured downloaded-file size and model removal.
- Optional AI marking consent beside its toggle and model selection in an advanced page.
- Backup export timestamp recorded only after a successful complete-backup file export.
- Day/week/month/all activity charts; past-period navigation and tap selection; deck/question
  drill-down pages. History distinguishes manual ratings from automatically marked answers.
- Charts offer persisted Bars/Line choices, use zero-based bars and linear trends, and share
  Engram's palette with settings rows, icon tiles, typography and themed reading surfaces.
- Native UI audit and remaining runtime checks: `docs/UI-AUDIT-SETTINGS-ACTIVITY.md`.
- Calendar-based study windows honor the saved time zone/day boundary, including DST.
  Current due and recall estimates remain separate from historical review totals.
- Native system typography, semantic colors, dark mode, VoiceOver labels and a menu instead
  of segmented periods at accessibility text sizes. Navigation uses native transitions.

Measurement limits:
- No study duration is shown because active study time is not recorded yet.
- Activity uses active, non-suspended cards and active Engram review events. Undone reviews,
  future events, deleted content and imported Anki review records are excluded from totals.
- Recall grades are scheduling evidence rather than an exam accuracy percentage.
- Voice recognition and cloud-service implementation are unchanged by this UI redesign.

Validation:
- `swift test`: activity-window DST/boundary, repeated-card, undo and preference validation tests.
- `Engram-iOS` UI tests: settings navigation, daily-limit persistence, chart selection,
  period navigation, microphone-test and storage navigation. The `--ui-testing` argument
  creates an in-memory fixture in Debug builds, leaving the device's library untouched.
