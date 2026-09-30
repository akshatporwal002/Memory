# Third-party source and notices

Engram includes the following independently licensed components. Complete notices are retained in source and bundled as `App/Acknowledgements.txt`, accessible from Settings.

| Component | Pinned source | Notice |
| --- | --- | --- |
| swift-fsrs | open-spaced-repetition/swift-fsrs, `4fbaf20184d62f82a9f44f343337c61a2c5483e9` | MIT, Copyright (c) 2023 Ben Smiley; `Vendor/FSRS/LICENSE` |
| miniz | richgel999/miniz 3.1.0, `174573d60290f447c13a2b1b3405de2b96e27d6c` | Permissive notice in `Sources/CArchive/LICENSE`; origin in adjacent PROVENANCE.md |
| SQLite | 3.50.4 amalgamation | Public-domain dedication in original headers; download hash in `Sources/CSQLite/PROVENANCE.md` |

FSRS source and upstream tests are vendored for reproducible offline builds. The adapter explicitly selects FSRS-6; upstream default parameters are not silently assumed. Upstream tests remain separate from Engram's application contract tests.

Anki source was inspected in a separate reference checkout under its applicable licences. No Anki implementation was copied, translated, linked or bundled. The official Anki Python backend is disposable development validation tooling only. Generated synthetic fixtures and comparison results have provenance records under Tests and validation.

Native UI uses system fonts and symbols. The HTML design mockup uses local font fallbacks and contains no downloaded commercial assets. Supplied user design references remain separate from app resources. Original Engram code has no public distribution licence assigned by this build; do not infer a release licence from dependencies.
