import assert from "node:assert/strict";
import test from "node:test";
import { dueCards, searchNotes, weakDecks } from "../src/library.js";

const snapshot = {
  decks: [{ id: "deck-1", name: "Spanish" }],
  notes: [{ id: "note-1", deckID: "deck-1", front: "hola", back: "hello", tags: ["greetings"] }],
  cards: [{ id: "card-1", noteID: "note-1", deckID: "deck-1", schedule: { due: "2026-01-01T00:00:00Z", phase: "review" } }],
  reviews: [{ id: "review-1", cardID: "card-1", deckID: "deck-1", rating: 1, reviewedAt: "2026-01-01T00:00:00Z" }]
};

test("dueCards excludes suspended cards and returns the note front", () => {
  assert.deepEqual(dueCards(snapshot, new Date("2026-01-02T00:00:00Z")), [{ cardId: "card-1", deckId: "deck-1", deckName: "Spanish", noteId: "note-1", front: "hola", due: "2026-01-01T00:00:00Z", phase: "review" }]);
});

test("weakDecks ignores corrected reviews", () => {
  assert.equal(weakDecks({ ...snapshot, corrections: [{ reviewID: "review-1" }] }).length, 0);
  assert.equal(weakDecks(snapshot)[0]?.difficultRate, 1);
});

test("searchNotes includes tags and excludes deleted notes", () => {
  assert.equal(searchNotes(snapshot, "greeting")[0]?.noteId, "note-1");
  assert.equal(searchNotes({ ...snapshot, notes: [{ ...snapshot.notes[0], deleted: true }] }, "hola").length, 0);
});
