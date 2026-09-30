# iPhone Library landing page

Implemented 4 September 2026; updated with the compact-library and document-creation pass. MCQs and editing saved decks as live documents remain separate phases.

## Included

- iPhone-only deck landing page; existing iPad/Mac library remains unchanged.
- Compact two-column gallery (one column for accessibility text). Names, paths, counts, review status, and the options menu live inside each tile. Covers use a short photo/typographic band above an opaque, readable information area; there is no detached information below the card.
- Text-only directory mode with expandable existing `::` deck paths, indentation, disclosure chevrons, and compact inline counts. Neither decks nor folders have thumbnail icons. Virtual folder rows do not create, rename, or duplicate decks.
- Show folders groups gallery sections and enables the expandable list hierarchy. Turning it off flattens the view without changing stored content.
- Search by deck/subject path, source-document text, question text, and tags. Results open the containing deck; jumping to a matching document block belongs to the document-editor phase.
- Sort by next review, name A-Z/Z-A, recently edited, newest, or most cards. View/sort/folder preferences persist on the device.
- Next-review sorting separates due, new, future, and empty/unstudiable decks. Daily-limit notices use the current study-day budgets; learning/relearning cards remain uncapped.
- Cover selection through the system Photos picker. A chosen image is downsampled to at most 720 pixels, re-encoded as a JPEG under 1 MB, and stored in existing library media. Original metadata is not retained. No AI or image service is used.
- A visible per-deck options menu opens the deck, changes its cover, or removes the cover assignment.
- A full-page New deck writing flow and a pushed existing deck/cards page. The legacy single-card editor and rename flow are not redesigned in this pass.
- Empty/loading/no-search-results states and an isolated populated Xcode preview in `App/EngramApp.swift`. Preview material never enters the real library.

## Data compatibility

Deck metadata gains optional creation/edit dates, a cover-media reference, and the original creation document. Old deck JSON still decodes without these fields; unknown historical creation dates remain unknown. Existing cards, schedules, review events, and IDs are not recreated when changing a cover.

Native backups include cover assignments and their image resources. Replaced/removed cover media is retained because notes or source evidence may reference it; automatic media cleanup is not part of this change. Media remains subject to the existing total library limit.

Anki export does not preserve Engram cover assignments or the original document (generated Q&A notes remain normal cards). Opening/saving the library with an older Engram build may discard the new optional deck metadata. Use a current native backup for preservation.

## Document creation

1. Open **New deck** (or **Resume draft** when unfinished work exists).
2. Enter a title and optionally type a subject/folder path, or choose an existing subject. Nested paths use `::`; this uses the existing hierarchy, not a separate Subject database model.
3. Write or paste one `Question -> Answer` or `Question → Answer` per line. The first arrow splits the line. Headings beginning with `# ` and ordinary prose are notes. Prefix a line with `\` to retain an arrow as prose.
4. The footer shows the number of ready cards. Incomplete Q&A lines show their line numbers and prevent creation. Limits are 1 MB of document text and 1,000 questions per creation.
5. **Create** validates and commits the deck and all basic Q&A cards in one transaction. Empty decks and note-only documents are allowed. Stable draft identity makes unchanged retries safe after uncertain completion.
6. Original text remains available under **Source document** in the deck, including headings, notes, and incomplete-free Q&A source. Individual card edits do not update that original copy.

Title, subject, document, and draft identity are stored in device-local preferences. Back navigation retains them; successful creation clears them. Discard requires confirmation. Unfinished drafts are not included in library backups or synced. Creation errors retain the draft and do not leave partial decks. The writing page accepts plain text; HTML delimiters are escaped for the card renderer.

## Not included yet

Explicit subject management/moving, editing saved decks as live documents, MCQs, the AWS sample question bank, and the Mac redesign remain follow-up work.

## Verification

- iOS Simulator compile succeeded for Engram-iOS.
- Seven Library tests passed: legacy decoding, review ordering, limits, search/sorts, nested hierarchy, native cover-backup round-trip/history preservation, and invalid cover rejection.
- Ten document-creation tests cover parsing, line numbers, size/count limits, atomic creation, commit failure, safe retries, plain-text escaping, note-only decks, draft encoding, duplicate names, and native document backup.
- Full Swift regression suite: 81 tests executed, one skipped, zero failures.
- Photo picking, draft recovery through the actual UI, and final visual layout still need hands-on iPhone review. Verification in this pass is compile/unit-test only; it has not been installed on the physical phone by the assistant.

Build from Xcode with Engram-iOS and the connected iPhone selected, then Run.
