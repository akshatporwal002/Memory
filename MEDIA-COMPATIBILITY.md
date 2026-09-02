# Card content and media compatibility

Engram renders the supported subset with native SwiftUI text and images plus AVAudioPlayer. It does not use a browser, execute imported template code, or load network URLs. Source fields and original template data remain in the import provenance for supported packages and complete native backups.

## Supported field markup

| Content | Accepted representation | Native behavior |
| --- | --- | --- |
| Plain text | Unicode text, including literal line breaks | Inherits the current theme and Dynamic Type font; wraps and supports selection. |
| Bold | `<b>…</b>`, `<strong>…</strong>` | Bold text. |
| Italic | `<i>…</i>`, `<em>…</em>` | Italic text; may be combined with bold. |
| Underline / strikethrough | `<u>…</u>`, `<s>…</s>`, `<strike>…</strike>` | Native text decoration. |
| Code | `<code>…</code>`, `<pre>…</pre>` | Monospaced text, retaining explicit spaces/newlines. Preformatted blocks create a paragraph boundary. |
| Paragraphs / line breaks | `<p>…</p>`, `<div>…</div>`, `<br>` / `<br/>` | Reading paragraphs and explicit line breaks. |
| Neutral span | `<span>…</span>` | Text grouping; no attributes or CSS. |
| Image | `<img src="filename.png" alt="Description">` | Local embedded image, accessible alternative text. `title` is an optional alternative-text fallback. No other image attributes are supported. |
| Audio | `[sound:filename.mp3]` | An explicit Play/Pause button and filename; no autoplay. |

Only `img` supports attributes: required `src`, optional `alt` and `title`. Attribute names and tag names are case-insensitive. Quoted and simple unquoted attribute values are accepted, duplicate attributes are rejected, and tags must be properly nested/closed. Layout adapts to available width rather than applying imported fixed dimensions.

Named entities: `amp`, `lt`, `gt`, `quot`, `apos`, `nbsp`, `ndash`, `mdash`, `hellip`, `copy`, `reg`, `deg`, `times`, `divide`, `plusmn`, `le`, `ge`, `ne`. Decimal and hexadecimal numeric entities are also accepted for valid nonzero Unicode scalar values. Unknown semicolon-terminated entities produce a finding. Entity text is decoded once and is never reparsed as executable markup.

To teach literal HTML, escape angle brackets: `&lt;b&gt;` displays `<b>`. Unsupported literal tags are rejected when saving a note so users cannot accidentally save a question that this renderer cannot display faithfully. Required basic/reverse fields and individual cloze answers must contain visible decoded text or supported media. Empty tags, whitespace, and `&nbsp;` alone do not count. Cloze back/extra content remains optional. Validation failures retain the editable draft and leave saved notes/cards unchanged.

## Media formats and bounds

- Images: PNG, JPEG (`jpg`/`jpeg`), BMP, TIFF (`tif`/`tiff`), HEIC/HEIF. Local image metadata must report a single image, positive dimensions no greater than 20,000 pixels per axis and no greater than 40 megapixels. ImageIO creates a transformed thumbnail capped at 2,048 pixels. Images display at a readable width within the card, with a maximum preferred width of 640 points.
- Audio: MP3, M4A, AAC, WAV, AIFF (`aif`/`aiff`), CAF. Playback uses only the supplied in-memory library data. It stops when the card view disappears or its media changes.
- All media uses exact stored filenames after HTML-entity decoding and one percent-decoding pass. Schemes, slashes, backslashes, colon paths, control characters and `.`/`..` filenames are rejected. There is no filesystem fallback if a file is absent.
- Library validation caps each media file at 50 MB and the complete embedded media collection at 512 MB.
- Fields are limited to 1 MB, 20,000 markup/audio tokens and 256 nested formatting elements.

GIF, SVG, animated/multipage image content, Ogg and unlisted formats are outside this renderer's supported subset. Missing media is shown as missing rather than replaced silently. Invalid image bytes and audio decoding/playback failures display an actionable message. The pure import parser verifies markup and filename/extension eligibility; actual platform decoder support and file decodability still need Apple runtime validation. An allowed extension is not a claim that every possible codec variant inside that container will play.

## Explicitly unsupported

Custom CSS (including inline `style`), hyperlinks, external resources, scripts and event handlers, HTML declarations/comments, tables/lists, forms, SVG, video, unknown tags or attributes, malformed nesting and unknown entities produce compatibility findings. The Anki adapter additionally rejects LaTeX/MathJax conventions it cannot render. The parser exposes `SafeCardMarkup.inspect(field).isSupported`, `.findings`, `.mediaNames` and `.blocks` so the import inspection and native renderer use the same supported subset. Unsupported imported fields block import rather than being flattened.

## Verification evidence

`Tests/EngramTests/SafeCardMarkupTests.swift` has 12 tests. The initial missing parser API was observed as a compile-time RED. After parsing was implemented, its first 9 tests passed. The save-validation integration then reproduced 20 failing assertions in two tests before the guards were added; the same final 12 tests passed with 0 failures on Swift 6.3.3 Windows at 03:57:58 Australia/Sydney on 3 September 2026.

```powershell
. .\scripts\Enter-SwiftEnvironment.ps1
swift test --filter SafeCardMarkupTests
```

These tests cover nested formatting, quoted `>` in image alternative text, entities, local references, scripts/styles/URL rejection, traversal, malformed markup, complexity limits, draft preservation, visible-content validation and permitted media-only cards. The native `CardContentView.swift` passed a syntax-only `swiftc -frontend -parse` check on Windows. This does **not** typecheck SwiftUI/ImageIO/AVFAudio APIs or establish successful image display, audio playback, focus/VoiceOver, Dynamic Type, interruption handling or Apple performance. Those checks remain pending in the iPhone, iPad and macOS runtime gates.

Apple API references: [AVAudioPlayer in-memory initialization](https://developer.apple.com/documentation/avfaudio/avaudioplayer/init(data:)) and [SwiftUI Text](https://developer.apple.com/documentation/swiftui/text).
