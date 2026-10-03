# AI chat interaction revision

## Requested behaviour

- Keep a small gap above the keyboard rather than resting the panel on it.
- Open into a compact question composer. Typing opens the medium chat; upward drags move from compact to medium to expanded. Downward drags reverse those stages and finally close the panel.
- Use the title at the top of chat to open saved conversations. Selecting a row switches to that chat; a plus starts a new chat, and swiping a saved row exposes Delete.
- Opening from the closed icon starts a fresh chat. An in-progress request stays associated with its existing conversation.
- Slim the header and remove the separate history icon. Keep the smaller control icons inside usable hit regions.
- Restore readable text streaming without exposing function arguments or command JSON.
- Render inline and display LaTeX correctly in chat, using the shared offline content renderer.

## Implementation choices

The panel has four presentation stages and an eight-point keyboard clearance. Chat history uses native List swipe actions. Deleting a conversation removes its messages and provider continuation history but retains the independent action journal and undo evidence. Chat selection/deletion/new-chat actions are disabled during a running request.

Provider events already distinguish text deltas from tool calls. Visible prose now streams again; possible JSON payload text is buffered from its opening brace, with root arrays and protocol-style fences held back. The completed response still passes the existing payload check. Genuine app actions use friendly command labels. No special symbol is requested from the model: such a convention could leak when a delimiter is omitted, split, or accidentally included in ordinary content. Text containing braces can pause until completion, including some formulas and code examples.

TeX delimiters are protected before CommonMark parses backslash escapes, then handed to the bundled KaTeX renderer. Source text is unchanged. Existing fenced code remains literal, and incomplete equations retain readable fallback behaviour. Rendering stays offline and keeps the existing WebKit restrictions.

## Validation

Focused unit tests cover every prefix of a tool JSON payload, ordinary streaming prose, math preservation, literal code and durable deletion that preserves other conversations and action history. Simulator coverage checks keyboard return, all drag stages, title selection, native swipe deletion, new chats, equation rendering and inverted monochrome palettes. Visual captures are retained under `current_ui/Assistant` and the existing theme folders, with one previous capture per view.

The first simulator checks caught missing explicit header hit regions and an excessive swipe threshold for the smaller handle. Both were corrected and rechecked. Live model streaming is separate from fixture-based UI validation.

Final checks: all 17 focused logic tests passed. Seven distinct simulator scenarios passed across the focused runs: keyboard/button expansion and equations (`/tmp/engram-chat-stages-final.xcresult`), drag/keyboard return (`/tmp/engram-chat-drag-confirmed.xcresult`), both Mono palettes (`/tmp/engram-chat-title-final.xcresult`), and the final title-only history/new/delete flows (`/tmp/engram-chat-history-confirmed.xcresult`). Earlier bundles retain the documented failures; the final history recheck confirms no saved transcript appears before title selection. These are fixture-based checks rather than live model requests.

Device delivery: the SSH build initially failed with `errSecInternalComponent` at code signing. Running the existing build script in the Mac Terminal session succeeded. The updated app was installed and launched on the paired iPhone at 18:44 on 3 October 2026; `/tmp/engram-dev-phone.status` reports `LAUNCHED` and the device log confirms `dev.engram.study`.

Keyboard focus follow-up: expansion/collapse buttons and drag gestures no longer clear composer focus. Only the final drag to closed dismisses the keyboard. The simulator regression passed keyboard return, both resize buttons, upward expansion and downward medium/compact stages with the keyboard still visible (`/tmp/engram-chat-focus.xcresult`). Current/previous stage screenshots were refreshed. Bubble layout and more translucent keyboard styling remain discussion proposals.
