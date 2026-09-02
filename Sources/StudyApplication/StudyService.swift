import Foundation
import LearningCore

/// Application use cases. Views share this actor; no database or vendor scheduler enters presentation code.
public actor StudyService {
    let repository: any LibraryRepository
    private let scheduler: any Scheduler
    public init(repository: any LibraryRepository, scheduler: any Scheduler) { self.repository = repository; self.scheduler = scheduler }
    public func snapshot() async throws -> LibrarySnapshot { try await repository.read() }

    @discardableResult public func createDeck(name: String) async throws -> Deck {
        var library = try await repository.read()
        let clean = try deckName(name, in: library)
        let deck = Deck(name: clean); library.decks.append(deck)
        try await save(library); return deck
    }
    public func renameDeck(id: String, name: String) async throws {
        var library = try await repository.read()
        guard let index = library.decks.firstIndex(where: { $0.id == id && !$0.deleted }) else { throw EngramError.missing("deck") }
        let clean = try deckName(name, in: library, excluding: id)
        let oldName = library.decks[index].name
        let affected = library.decks.indices.filter { !library.decks[$0].deleted && (library.decks[$0].id == id || library.decks[$0].name.hasPrefix(oldName + "::")) }
        let affectedIDs = Set(affected.map { library.decks[$0].id })
        let mappings = affected.map { index in (index, clean + library.decks[index].name.dropFirst(oldName.count)) }
        for (_, replacement) in mappings {
            guard !library.decks.contains(where: { !$0.deleted && !affectedIDs.contains($0.id) && $0.name.caseInsensitiveCompare(replacement) == .orderedSame }) else { throw EngramError.invalid("Renaming would collide with an existing subdeck.") }
        }
        for (index, replacement) in mappings { library.decks[index].name = replacement }
        try await save(library)
    }
    /// Caller presents a destructive confirmation. Tombstones retain historical evidence for backup.
    public func deleteDeck(id: String) async throws {
        var library = try await repository.read()
        guard let deck = library.decks.first(where: { $0.id == id && !$0.deleted }) else { throw EngramError.missing("deck") }
        let affected = Set(library.decks.filter { $0.id == id || $0.name.hasPrefix(deck.name + "::") }.map(\.id))
        for i in library.decks.indices where affected.contains(library.decks[i].id) { library.decks[i].deleted = true }
        for i in library.notes.indices where affected.contains(library.notes[i].deckID) { library.notes[i].deleted = true }
        for i in library.cards.indices where affected.contains(library.cards[i].deckID) { library.cards[i].retired = true; library.cards[i].version += 1 }
        invalidateSessionIfNeeded(&library)
        try await save(library)
    }
    @discardableResult public func saveNote(_ draft: NoteDraft, now: Date) async throws -> Note {
        let ordinals = try CardRenderer.ordinals(for: draft)
        var library = try await repository.read()
        guard library.decks.contains(where: { $0.id == draft.deckID && !$0.deleted }) else { throw EngramError.missing("destination deck") }
        let prior = library.notes.first(where: { $0.id == draft.id && !$0.deleted })
        if draft.id != nil && prior == nil { throw EngramError.missing("note") }
        if let prior, prior.kind != draft.kind { throw EngramError.invalid("Changing a saved note's type needs a migration. Create a new note instead.") }
        let tags = Array(Set(draft.tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        guard tags.count <= 100, tags.allSatisfy({ $0.count <= 100 && !$0.contains(where: \.isWhitespace) }) else { throw EngramError.invalid("Use at most 100 tags, without spaces, and 100 characters per tag.") }
        let note = Note(id: prior?.id ?? UUID().uuidString, deckID: draft.deckID, kind: draft.kind, front: draft.front,
            back: draft.back, tags: tags, source: draft.source, origin: prior?.origin, modifiedAt: now)
        if let index = library.notes.firstIndex(where: { $0.id == note.id }) { library.notes[index] = note } else { library.notes.append(note) }
        for i in library.cards.indices where library.cards[i].noteID == note.id {
            library.cards[i].deckID = draft.deckID
            library.cards[i].retired = !ordinals.contains(library.cards[i].ordinal)
            library.cards[i].version += 1
        }
        for ordinal in ordinals where !library.cards.contains(where: { $0.noteID == note.id && $0.ordinal == ordinal }) {
            library.cards.append(StudyCard(noteID: note.id, deckID: note.deckID, ordinal: ordinal,
                schedule: try scheduler.initialState(now: now, settings: library.settings)))
        }
        invalidateSessionIfNeeded(&library)
        try await save(library); return note
    }
    public func deleteNote(id: String) async throws {
        var library = try await repository.read()
        guard let index = library.notes.firstIndex(where: { $0.id == id && !$0.deleted }) else { throw EngramError.missing("note") }
        library.notes[index].deleted = true
        for i in library.cards.indices where library.cards[i].noteID == id { library.cards[i].retired = true; library.cards[i].version += 1 }
        invalidateSessionIfNeeded(&library); try await save(library)
    }
    public func setSuspended(cardID: String, suspended: Bool) async throws {
        var library = try await repository.read()
        guard let index = library.cards.firstIndex(where: { $0.id == cardID && !$0.retired }) else { throw EngramError.missing("card") }
        library.cards[index].suspended = suspended; library.cards[index].version += 1
        invalidateSessionIfNeeded(&library); try await save(library)
    }
    public func updateSettings(_ settings: StudySettings) async throws {
        var library = try await repository.read()
        var updated = settings; updated.version = library.settings.version + 1
        library.settings = updated
        if let current = library.session?.current { library.session?.current = ReviewPresentation(card: current.card) }
        try await save(library)
    }
    public func search(_ query: String, deckID: String? = nil) async throws -> [Note] {
        let library = try await repository.read()
        return Self.search(query, deckID: deckID, in: library)
    }
    public static func search(_ query: String, deckID: String?, in library: LibrarySnapshot) -> [Note] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return library.liveNotes.filter { note in
            guard deckID == nil || note.deckID == deckID else { return false }
            let haystack = [note.front, note.back, note.source, note.tags.joined(separator: " ")].joined(separator: " ").lowercased()
            return terms.allSatisfy { term in
                if term.hasPrefix("tag:") { return note.tags.contains { $0.lowercased() == String(term.dropFirst(4)) } }
                if term == "is:suspended" { return library.liveCards.contains { $0.noteID == note.id && $0.suspended } }
                return haystack.contains(term)
            }
        }.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    public func startSession(deckID: String?, now: Date) async throws -> StudySession {
        var library = try await repository.read()
        if let existing = library.session, existing.deckID == deckID, let current = existing.current,
           library.cards.contains(where: { $0.id == current.card.id && $0.version == current.card.version && !$0.retired && !$0.suspended }) {
            return existing
        }
        let queue = QueuePolicy.dueCards(in: library, deckID: deckID, now: now)
        var session = StudySession(deckID: deckID, startedAt: now, queue: queue.map(\.id), current: queue.first.map(ReviewPresentation.init))
        session.nextLearningDue = nextLearningDue(in: library, deckID: deckID, now: now)
        library.session = session; try await save(library); return session
    }
    /// Rechecks cards that became due, including short learning steps. Does not disturb a visible prompt.
    public func refreshSession(now: Date) async throws -> StudySession? {
        var library = try await repository.read()
        guard var session = library.session else { return nil }
        if let item = session.current,
           library.cards.contains(where: { $0.id == item.card.id && $0.version == item.card.version && !$0.retired && !$0.suspended }) { return session }
        refresh(&session, in: library, now: now); library.session = session
        try await save(library); return session
    }
    public func reveal(sessionID: String, presentationID: String, now: Date) async throws -> ReviewPresentation {
        var library = try await repository.read()
        guard var session = library.session, session.id == sessionID,
              var item = session.current, item.presentationID == presentationID else { throw EngramError.conflict }
        guard library.cards.contains(where: { $0.id == item.card.id && $0.version == item.card.version && !$0.retired && !$0.suspended }) else { throw EngramError.conflict }
        if item.revealedAt != nil { return item }
        let history = library.activeReviews.filter { $0.cardID == item.card.id }
        item.outcomes = try scheduler.outcomes(state: item.card.schedule, history: history, now: now, settings: library.settings)
        guard item.outcomes.count == 4 else { throw EngramError.invalid("Scheduler did not supply all four grades.") }
        item.revealedAt = now; session.current = item; library.session = session
        try await save(library); return item
    }
    public func grade(sessionID: String, presentationID: String, rating: Grade, mutationID: String, now: Date) async throws {
        var library = try await repository.read()
        if let previous = library.reviews.first(where: { $0.id == mutationID }) {
            guard previous.sessionID == sessionID, previous.rating == rating else { throw EngramError.conflict }
            return
        }
        guard !mutationID.isEmpty, var session = library.session, session.id == sessionID,
              let item = session.current, item.presentationID == presentationID,
              let revealedAt = item.revealedAt, now >= revealedAt,
              let outcome = item.outcomes[rating],
              let index = library.cards.firstIndex(where: { $0.id == item.card.id && !$0.retired && !$0.suspended }),
              library.cards[index].version == item.card.version,
              outcome.settingsVersion == library.settings.version else { throw EngramError.conflict }
        library.cards[index].schedule = outcome; library.cards[index].version += 1
        library.reviews.append(ReviewEvent(id: mutationID, cardID: item.card.id, deckID: item.card.deckID, sessionID: session.id,
            rating: rating, reviewedAt: revealedAt, committedAt: now, before: item.card.schedule, after: outcome))
        session.completed += 1
        refresh(&session, in: library, now: now); library.session = session
        try await save(library)
    }
    public func undo(sessionID: String, now: Date) async throws {
        var library = try await repository.read()
        guard var session = library.session, session.id == sessionID,
              let event = library.activeReviews.last(where: { $0.sessionID == sessionID }),
              let index = library.cards.firstIndex(where: { $0.id == event.cardID && !$0.retired && !$0.suspended }),
              library.cards[index].schedule == event.after else { throw EngramError.invalid("There is no unchanged review in this session to undo.") }
        library.cards[index].schedule = event.before; library.cards[index].version += 1
        library.corrections.append(ReviewCorrection(reviewID: event.id, createdAt: now))
        session.completed = max(0, session.completed - 1)
        refresh(&session, in: library, now: now)
        let restored = library.cards[index]
        session.current = ReviewPresentation(card: restored)
        session.queue.removeAll { $0 == restored.id }; session.queue.insert(restored.id, at: 0)
        library.session = session; try await save(library)
    }
    /// Exiting the review UI needs no mutation; persisted session and committed grades remain resumable.
    public func endSession() async throws {
        var library = try await repository.read(); library.session = nil; try await save(library)
    }
    /// Only a fully inspected/confirmed restore invokes this operation. Export pre-restore backup first.
    public func restore(_ candidate: LibrarySnapshot, expectedRevision: Int) async throws {
        try LibraryValidation.validate(candidate)
        var restored = candidate; restored.revision = expectedRevision; restored.session = nil
        try await repository.commit(restored, expectedRevision: expectedRevision)
    }

    private func save(_ library: LibrarySnapshot) async throws { try await repository.commit(library, expectedRevision: library.revision) }
    private func deckName(_ value: String, in library: LibrarySnapshot, excluding: String? = nil) throws -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 200, clean.components(separatedBy: "::").allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { throw EngramError.invalid("Enter a deck name up to 200 characters. Separate nested decks with ::.") }
        guard !library.liveDecks.contains(where: { $0.id != excluding && $0.name.caseInsensitiveCompare(clean) == .orderedSame }) else { throw EngramError.invalid("A deck with this name already exists.") }
        return clean
    }
    private func refresh(_ session: inout StudySession, in library: LibrarySnapshot, now: Date) {
        let queue = QueuePolicy.dueCards(in: library, deckID: session.deckID, now: now)
        session.queue = queue.map(\.id); session.current = queue.first.map(ReviewPresentation.init)
        session.nextLearningDue = nextLearningDue(in: library, deckID: session.deckID, now: now)
    }
    private func nextLearningDue(in library: LibrarySnapshot, deckID: String?, now: Date) -> Date? {
        QueuePolicy.eligibleCards(in: library, deckID: deckID).filter { ($0.schedule.phase == .learning || $0.schedule.phase == .relearning) && $0.schedule.due > now }.map(\.schedule.due).min()
    }
    private func invalidateSessionIfNeeded(_ library: inout LibrarySnapshot) {
        guard let current = library.session?.current else { return }
        if !library.cards.contains(where: { $0.id == current.card.id && $0.version == current.card.version && !$0.retired && !$0.suspended }) {
            library.session?.current = nil
        }
    }
}
