# Screenshot export

Keep the current app design. No wireframe styling is applied by this feature.

## Use

- iPhone/iPad: main-screen toolbar **More (…) → Screenshot all pages…**.
- Mac: **Screenshots → Screenshot all pages…**, or the toolbar More menu.
  Shortcut: Command–Option–Shift–S.
- Choose **Capture all pages** and keep Engram open.
- On iPhone/iPad, choose **Save to Photos**, then allow Engram to add photos.
  Each screenshot is saved as an individual PNG in Photos; no ZIP is created.
  The save button is removed after success to prevent accidental duplicate batches.
- On Mac, choose **Save screenshot ZIP…**.
- Review the screenshots before sharing them in a conversation.

The capture tour returns to the selected screen. Scroll positions may reset.
The Mac menu is disabled while editing, reviewing, importing, or another sheet is open.

## Coverage and privacy

Captures Today, Library, Activity, the first available deck detail, new/rename deck,
basic/cloze new-card forms, the first saved note's editor and preview when available,
all Settings sections, Acknowledgements, import/export, and available review states.
An empty library is captured as-is; no fake cards are inserted. This is a UI tour,
not an exhaustive capture of every deck, card, menu, alert or import failure state.

Long main scroll areas are captured in overlapping viewport PNGs, with a limit of
12 images per screen and 100 images / 100 MB overall. Secondary panes and nested
text editors are not exhaustively scrolled. `screenshots.json` lists captured files,
theme, OS and skipped/truncated states in the Mac ZIP. On iOS, skipped/truncated
states are shown under Capture notes instead. No library JSON is included.

Screenshots can contain private content. Engram does not upload them. Images saved
to Photos may sync through iCloud Photos according to the user's system settings.
The tour uses a separate `MemoryRepository` and disposable preference domain; even
review/reveal actions cannot write to the live library. It never saves or grades a
real card. Cancel discards incomplete captures; capture failures save no images.

iOS captures its own UIWindow hierarchy, then requests add-only Photos permission
only when Save to Photos is tapped. It never reads the existing photo library.
Denied/restricted permission leaves the captured images available for retry;
the batch is submitted in one Photos change transaction. macOS uses
ScreenCaptureKit's `currentProcess` with a filter for the probe's own window,
including child sheets. It does not request capture of other apps or displays.
Screenshot export on Mac requires macOS 14.4+; the app's macOS 14 minimum is unchanged.

## Verification

- Mac and iOS simulator Debug builds passed before the final zero-size window-probe adjustment.
- Regression suite: 64 tests, one skipped, zero failures, including archive round-trip,
  unsafe name, invalid data, empty export and image-count limit checks.
- Manually exercised menu entry, capture, ZIP export, scroll coverage and return to
  the selected page. iOS cancellation discarded the partial capture and returned to Today.
- Inspected exported PNGs for main pages, Settings and Acknowledgements.
- A physical iPhone installation and populated-card review capture are still to be verified.
- Final Mac inspection found top content shifted under the toolbar in capture mode,
  although the normal app layout is correct. A zero-size background window probe is
  a candidate fix, not yet verified: the rebuild approval service failed twice with
  HTTP 404. Rebuild and recheck Mac Today/sidebar framing before calling this complete.

The native window bridge is intentional: AppKit display-cache snapshots omitted
layer-backed SwiftUI split-view content. ScreenCaptureKit captures that content.
