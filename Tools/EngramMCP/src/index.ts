import { readFile } from "node:fs/promises";
import { McpServer } from "@modelcontextprotocol/server";
import { serveStdio } from "@modelcontextprotocol/server/stdio";
import { z } from "zod";
import { dueCards, parseSnapshot, searchNotes, weakDecks } from "./library.js";

function libraryPath(args: string[]): string {
  const index = args.indexOf("--library");
  const value = index >= 0 ? args[index + 1] : undefined;
  if (!value || value.startsWith("--")) throw new Error("Usage: engram-mcp --library /absolute/path/to/library.json");
  return value;
}

function bounded(value: number | undefined, fallback: number, maximum: number): number {
  return Math.min(Math.max(value ?? fallback, 1), maximum);
}

async function readLibrary(path: string) {
  return parseSnapshot(await readFile(path, "utf8"));
}

export function createServer(path: string): McpServer {
  const server = new McpServer({ name: "engram-mcp", version: "0.1.0" });
  server.registerTool("engram_get_due_cards", {
    title: "Get due Engram cards",
    description: "Read-only. Lists cards due now from the library path selected when this local server was launched.",
    inputSchema: z.object({ deckId: z.string().uuid().optional(), limit: z.number().int().min(1).max(100).optional() }),
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false }
  }, async ({ deckId, limit }) => {
    const cards = dueCards(await readLibrary(path), new Date(), deckId, bounded(limit, 20, 100));
    return { content: [{ type: "text", text: JSON.stringify(cards) }], structuredContent: { cards } };
  });
  server.registerTool("engram_get_weak_decks", {
    title: "Get decks needing attention",
    description: "Read-only. Ranks decks by active Again/Hard review rate; it does not change schedules or grades.",
    inputSchema: z.object({ limit: z.number().int().min(1).max(50).optional() }),
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false }
  }, async ({ limit }) => {
    const decks = weakDecks(await readLibrary(path), bounded(limit, 10, 50));
    return { content: [{ type: "text", text: JSON.stringify(decks) }], structuredContent: { decks } };
  });
  server.registerTool("engram_search_notes", {
    title: "Search Engram notes",
    description: "Read-only. Searches note text and tags in the local library selected at launch.",
    inputSchema: z.object({ query: z.string().min(1).max(500), limit: z.number().int().min(1).max(100).optional() }),
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false }
  }, async ({ query, limit }) => {
    const notes = searchNotes(await readLibrary(path), query, bounded(limit, 20, 100));
    return { content: [{ type: "text", text: JSON.stringify(notes) }], structuredContent: { notes } };
  });
  return server;
}

const path = libraryPath(process.argv.slice(2));
await serveStdio(() => createServer(path));
