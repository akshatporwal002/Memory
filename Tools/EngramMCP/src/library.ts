export interface EngramSnapshot {
  libraryID?: string;
  decks?: Array<{ id: string; name: string; deleted?: boolean }>;
  notes?: Array<{ id: string; deckID: string; front: string; back: string; tags?: string[]; deleted?: boolean }>;
  cards?: Array<{ id: string; noteID: string; deckID: string; suspended?: boolean; retired?: boolean; schedule?: { due?: string; phase?: string } }>;
  reviews?: Array<{ id: string; cardID: string; deckID: string; rating: number; reviewedAt: string }>;
  corrections?: Array<{ reviewID: string }>;
}

export interface DueCard {
  cardId: string;
  deckId: string;
  deckName: string;
  noteId: string;
  front: string;
  due: string;
  phase: string;
}

export function parseSnapshot(input: string): EngramSnapshot {
  const parsed: unknown = JSON.parse(input);
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("The library file is not an Engram snapshot.");
  return parsed as EngramSnapshot;
}

export function dueCards(snapshot: EngramSnapshot, now: Date, deckId?: string, limit = 20): DueCard[] {
  const decks = new Map((snapshot.decks ?? []).filter(deck => !deck.deleted).map(deck => [deck.id, deck.name]));
  const notes = new Map((snapshot.notes ?? []).filter(note => !note.deleted).map(note => [note.id, note]));
  return (snapshot.cards ?? [])
    .filter(card => !card.suspended && !card.retired && (!deckId || card.deckID === deckId))
    .flatMap(card => {
      const due = card.schedule?.due;
      const note = notes.get(card.noteID);
      const deckName = decks.get(card.deckID);
      if (!due || !note || !deckName || new Date(due).getTime() > now.getTime()) return [];
      return [{ cardId: card.id, deckId: card.deckID, deckName, noteId: note.id, front: note.front, due, phase: card.schedule?.phase ?? "unknown" }];
    })
    .sort((left, right) => Date.parse(left.due) - Date.parse(right.due))
    .slice(0, limit);
}

export interface WeakDeck {
  deckId: string;
  deckName: string;
  reviewed: number;
  difficult: number;
  difficultRate: number;
}

export function weakDecks(snapshot: EngramSnapshot, limit = 10): WeakDeck[] {
  const decks = new Map((snapshot.decks ?? []).filter(deck => !deck.deleted).map(deck => [deck.id, deck.name]));
  const corrected = new Set((snapshot.corrections ?? []).map(correction => correction.reviewID));
  const values = new Map<string, { reviewed: number; difficult: number }>();
  for (const review of snapshot.reviews ?? []) {
    if (corrected.has(review.id) || !decks.has(review.deckID)) continue;
    const value = values.get(review.deckID) ?? { reviewed: 0, difficult: 0 };
    value.reviewed += 1;
    if (review.rating <= 2) value.difficult += 1;
    values.set(review.deckID, value);
  }
  return [...values.entries()]
    .map(([deckId, value]) => ({ deckId, deckName: decks.get(deckId)!, ...value, difficultRate: value.difficult / value.reviewed }))
    .sort((left, right) => right.difficultRate - left.difficultRate || right.reviewed - left.reviewed)
    .slice(0, limit);
}

export function searchNotes(snapshot: EngramSnapshot, query: string, limit = 20) {
  const normalized = query.trim().toLocaleLowerCase();
  if (!normalized) throw new Error("A search query is required.");
  const decks = new Map((snapshot.decks ?? []).filter(deck => !deck.deleted).map(deck => [deck.id, deck.name]));
  return (snapshot.notes ?? [])
    .filter(note => !note.deleted && decks.has(note.deckID))
    .filter(note => [note.front, note.back, ...(note.tags ?? [])].join("\n").toLocaleLowerCase().includes(normalized))
    .slice(0, limit)
    .map(note => ({ noteId: note.id, deckId: note.deckID, deckName: decks.get(note.deckID)!, front: note.front, back: note.back, tags: note.tags ?? [] }));
}
