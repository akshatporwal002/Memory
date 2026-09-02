# Anki adapter compatibility and verification

Verified 3 September 2026 on Windows x86_64 with Swift 6.3.3 and official Anki Python backend **26.08.1**. Native Apple compilation, document-picker integration, image decoding and audible playback remain separate platform checks. This is backend interoperability evidence; no desktop GUI/profile or Apple runtime is claimed tested.

## Supported path

- Anki 26.08.1 **legacy-compatible schema11** APKG import/export and COLPKG import. Current legacy exports include `meta` protobuf bytes `08 02`, a `collection.anki21` SQLite member and JSON media manifest. The adapter also recognizes older metadata-free `.anki2`/`.anki21` discovery, but this run did not validate separate historical Anki releases.
- Stock basic, two-template reversed and ordinary c1/c2 cloze notes; Unicode, note fields, original note-type/template data, GUIDs, namespaced source IDs, tags, nested deck names, image/audio references and media bytes. Imported source review records remain separate from new Engram recall events.
- Preflight returns counts and findings before a candidate is created. No adapter API mutates an active library. Application confirmation, pre-import backup, duplicate choices and transactional merge/restore are owned by StudyApplication.
- `.preserveSource` maps new cards and supported FSRS review cards containing stability, difficulty, last-review timestamp and collection creation timezone. Due calendar dates map to the chosen library timezone/rollover. Suspension is preserved. This retains memory/due/history; future intervals use Engram FSRS-6 defaults and retention policy, not all Anki parameters/fuzz. That difference is explicitly reported.
- `.contentOnly` initializes new Engram schedules only after explicit choice. It still retains raw source schedule/collection metadata and imported history for provenance and complete native backup. It preserves explicit suspension.
- Personal APKG export includes supported current schedules, original source history and non-corrected Engram reviews. Sharing export clears personal schedules/history/suspension and system marked/leech tags. Source library values are not mutated.
- Parent-deck selection includes descendants. Selection includes all cards belonging to each selected note, preserving siblings even when in different decks; the UI must disclose that scope. Only media referenced in exported retained fields is included. Missing referenced media stops Anki export before replacing any existing destination file.
- Own exports carry `engramLibraryID` in collection config for stable origin namespaces on direct reimport. Arbitrary collection config is not guaranteed to survive Anki's later package merging/export; source GUIDs and raw origin records remain important. External packages without this identifier use SHA-256 of the exact inspected package bytes. Repeating the same file is idempotent; different exports are distinct unless the user supplies the same stable source name. Explicit source names override embedded identity only when passed by the application.

### Direct reimport into the originating Engram library

An APKG transfer regenerates adapter identities, so it is not a native restoration path. Regression tests reproduced different note/card IDs when a native library or a library containing merged Anki notes exported and then reimported its own package. Blind merging would add duplicates and could recast existing native review events as additional imported evidence.

The application must reject this same-library merge before backup or mutation and direct the user to complete native backup restoration when restoration is intended. The adapter exposes immutable `AnkiInspection.sourceLibraryID` and stamps `note.origin.metadata["engramSourceLibraryID"]` from validated collection metadata. An explicit namespace override changes import identity but never removes this origin signal. Transfer into a different Engram library remains supported; repeated inspection of the same transferred package retains stable note/card/imported-history identities. This bounded safeguard deliberately avoids pretending that APKG preserves all native review/correction semantics.

## Explicit unsupported cases

- Modern Latest `collection.anki21b` zstd/protobuf packages; unknown package metadata; schema versions other than 11. Preflight directs the user to Anki's “Support older Anki versions” export option. Legacy-compatible schema11 is this build's explicit validated package boundary.
- Exact continuation of legacy SM-2, learning/relearning, buried or filtered source states. The user can cancel or explicitly select content-only import with original evidence retained. Filtered decks must be returned to original decks in Anki before this importer accepts them.
- Custom template logic, JavaScript, non-default CSS, image occlusion, typed-answer templates, nested/comma clozes and unsupported field markup. Unsupported notes are reported and block import; the adapter does not flatten them into misleading plain text.
- Rendering uses the shared SafeCardMarkup allowlist. HTML attributes/CSS, remote URLs, scripts and unsupported tags are rejected. Ordinary inline emphasis/paragraphs and local image/audio references are supported. LaTeX/MathJax markers are rejected. See the parser for exact image/audio formats. Unsupported media files may remain in complete native backups, but unsupported referenced content cannot enter the ordinary study renderer.
- Whole-collection Anki export is not implemented; required export is APKG. Anki export is not a complete Engram backup.

## Complete native backup

NativeBackupAdapter writes a versioned ZIP with `manifest.json` and separate numbered media payloads. The manifest contains the complete LibrarySnapshot with media moved to indexed payloads: originals, provenance, decks/notes/cards, schedules, settings, review events, correction records and session state. There are no credential fields in the snapshot. Restore validates version, entry count, unique mapping, payload sizes, referential integrity and library limits before returning the candidate.

ZIP entries are processed in memory, never extracted to archive-provided filesystem paths. Unsafe names, duplicate case-folded entries, encryption, unsupported ZIP entries, corruption/CRC failure and resource bounds cause rejection. Limits are 768 MB archive/expanded payload, 256 MB per archive entry, 100,000 entries and a 10,000:1 expansion cap; domain media limits remain 50 MB/file and 512 MB total. Output writes atomically. SQLite queries run against a private temporary database with extension loading disabled, trusted schema disabled, read-only connection and query-only mode. Temporary databases close before cleanup.

## Evidence

`Tests/AnkiAdapterTests/Fixtures/provenance.json` records SHA-256 hashes of fixtures created by the official 26.08.1 backend. The generator creates a fresh disposable collection with 3 notes/5 cards, nested decks, Unicode, an actual PNG/WAV, tags, one suspended reverse sibling, FSRS review memory and source history. It exports legacy APKG/COLPKG, content-sharing and modern packages; missing-media and unsafe-path fixtures derive from these or a small explicit malicious archive.

The adapter suite includes 12 tests (8 fixture tests, 4 archive tests), including the added source-library provenance and explicit-namespace regression checks. They cover inspection counts, basic/reverse/cloze relationships, stable repeated-import IDs, separate history, source memory import, modern/unsafe rejection, unsupported-template rejection, selected hierarchy, missing-media fail-before-write, invalid scheduler-payload rejection, export without source mutation and complete native restoration equality. SHA-256 package identity is checked against empty, abc and million-a known vectors. The latest recorded adapter run must pass before handoff; application merge rejection is verified in the separate application suite.

The script `scripts/anki_fixture_roundtrip.py verify` then imported **four actual Swift-produced packages** into fresh official Anki collections: personal transfer, sharing, newly authored native note-type templates, and a package containing a new Engram grade. It compared field/GUID/tag data where preserved, media SHA-256 hashes, source history values, card type/queue/interval, FSRS stability/difficulty/last-review timestamp and relative due days. It confirmed sharing removes history, new Engram history survives, and a repeated import does not duplicate note/card/history counts. All four passed. Full synthetic comparison rows are saved in `validation/anki-roundtrip-results.json`.

Reproduce after installing `anki==26.8.1` into a separate tooling environment:

```powershell
$env:PYTHONPATH = '<tooling>/anki-python'
python scripts/anki_fixture_roundtrip.py generate
$env:ENGRAM_ROUNDTRIP_DIR = '<tooling>/anki-roundtrip'
swift test --filter AnkiAdapterTests
python scripts/anki_fixture_roundtrip.py verify '<tooling>/anki-roundtrip'
```

Regenerating fixtures changes timestamps and hashes; inspect and record the new provenance. The official Anki package is development validation tooling only and is not linked or shipped in Engram. Production C dependencies are SQLite 3.50.4 (public-domain amalgamation) and miniz 3.1.0 (upstream LICENSE retained); pinned provenance is beside each C target. No Anki implementation code was incorporated.

Remaining verification includes adversarial large-library throughput/cancellation, older historical release fixtures, exhaustive learning-step export equivalence, malformed SQLite fuzzing, modern packages, Apple builds and UI-level end-to-end migration. Do not describe these backend tests as complete first-build acceptance.
