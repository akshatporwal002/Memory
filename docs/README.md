# Documentation

Project documentation belongs in this directory. Keep new design proposals under `design/`; use the sections below to find existing plans, research, guides, and verification reports.

Documents retain their original dates and verification context. Historical reports are not claims about the current build. Unless stated otherwise, shell commands and plain-text source/tool paths assume the repository root as the working directory. Markdown links resolve relative to their document.

## Product and design

- [iPhone Library product proposal and user flows](design/iphone-library-product-brief.md)
- [iPhone Library landing implementation and scope](design/iphone-library-landing-implementation.md)
- [Product plan](ENGRAM-PLAN.md)
- [First-build specification](ENGRAM-FIRST-BUILD.md)
- [Product research](PRODUCT-RESEARCH.md)
- [Competitor pain-point research](COMPETITOR-PAIN-RESEARCH.md)
- [Design handoff](DESIGN-HANDOFF.md)
- [Design preview and assets](../design/previews/design-preview.html) — mockups, not the native app

## Build and usage

- [Project overview](../README.md)
- [Apple build guide](README-APPLE.md)
- [Toolchain setup](TOOLCHAIN.md)
- [Screenshot export](SCREENSHOT-EXPORT.md)

## Architecture and interoperability

- [Architecture](ARCHITECTURE.md)
- [Anki compatibility](ANKI-COMPATIBILITY.md)
- [Anki source review](ANKI-SOURCE-REVIEW.md)
- [Media compatibility](MEDIA-COMPATIBILITY.md)
- [Third-party notices](THIRD-PARTY-NOTICES.md)

## Handoff and verification

- [Implementation handoff](HANDOFF.md)
- [Implementation log](IMPLEMENTATION-LOG.md)
- [Core review](CORE-REVIEW.md)
- [Import review](IMPORT-REVIEW.md)
- [Test results](TEST-RESULTS.md)
- [Performance](PERFORMANCE.md)
- [Raw validation evidence](../validation/)

## Files intentionally kept with their consumers

- [Agent definitions](../agents/README.md) remain in `agents/` for tool discovery.
- [Anki fixture notes](../Tests/AnkiAdapterTests/Fixtures/README.md) stay with the test resources.
- [SQLite provenance](../Sources/CSQLite/PROVENANCE.md), [archive-codec provenance](../Sources/CArchive/PROVENANCE.md), and vendored licenses stay beside their source.
- [Bundled acknowledgements](../App/Acknowledgements.txt) remain an app resource.
- Design assets/generation tools remain in `design/`; raw logs and measurements remain in `validation/`.
