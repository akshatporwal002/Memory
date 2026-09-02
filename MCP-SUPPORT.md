# Engram MCP support

This branch adds a local, read-only MCP server under `Tools/EngramMCP`. It is an optional companion process, not part of the Apple app bundle. The server reads only the library file passed explicitly at launch; it neither writes a library nor makes network requests.

## Available tools

- `engram_get_due_cards`: cards due at the call time, optionally scoped to one deck.
- `engram_get_weak_decks`: ranks decks from active `Again` and `Hard` reviews.
- `engram_search_notes`: searches visible note fields and tags.

All tools declare read-only, non-destructive, idempotent, local-only annotations. There are deliberately no tools to grade a card, edit a note, import/export, start a session, or change settings. Any future write tool needs an explicit user confirmation mechanism and a transactional application boundary.

## Run locally

```powershell
cd Tools/EngramMCP
npm install
npm run start -- --library C:\absolute\path\to\library.json
```

The MCP host launches the server and communicates through standard input/output. Standard output is protocol-only, so diagnostics must go to standard error. Use the MCP Inspector to exercise the server after installing dependencies:

```powershell
npx @modelcontextprotocol/inspector npm run start -- --library C:\absolute\path\to\library.json
```

The server needs a library produced by the native app and cannot currently unlock a sandboxed or encrypted Apple app container. It should be configured only with an explicit user-selected export/copy until the app has a consented local sharing mechanism.
