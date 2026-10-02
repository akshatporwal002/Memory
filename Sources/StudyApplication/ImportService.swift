import Foundation
import LearningCore

public enum DuplicateImportPolicy: String, CaseIterable, Sendable {
    case keepExisting, updateContent, skipExisting
    public var label: String {
        switch self {
        case .keepExisting: return "Keep my content and progress; add source history"
        case .updateContent: return "Update content; keep my study progress"
        case .skipExisting: return "Skip existing notes entirely"
        }
    }
}
public struct ImportSummary: Sendable {
    public var addedNotes = 0
    public var updatedNotes = 0
    public var skippedNotes = 0
    public var addedCards = 0
    public var addedHistory = 0
    public var addedMedia = 0
    public init() {}
}
extension StudyService {
    /// Preflight snapshot + backup precede the sole durable commit. Cancellation/backup errors leave the active library unchanged.
    public func mergeImport(_ candidate: LibrarySnapshot, duplicates: DuplicateImportPolicy,
        destinationDeckID: String?, expectedRevision: Int,
        preImportBackup: @Sendable (LibrarySnapshot) async throws -> Void) async throws -> ImportSummary {
        try LibraryValidation.validate(candidate)
        guard candidate.reviews.isEmpty, candidate.corrections.isEmpty else {
            throw EngramError.invalid("This candidate contains native review evidence. Use complete library restore to retain all events and corrections; Anki merge accepts source review records only.")
        }
        let original = try await repository.read()
        guard original.revision == expectedRevision else { throw EngramError.conflict }
        guard !candidate.notes.contains(where: { $0.origin?.metadata["engramSourceLibraryID"] == original.libraryID }) else {
            throw EngramError.invalid("This Anki package originated from this Engram library. Merging it back could duplicate native cards and review evidence. Use a complete Engram backup and confirmed restore to recover this library, or import the package into a different library.")
        }
        var library = original; var summary = ImportSummary()
        if let destinationDeckID, !library.liveDecks.contains(where: { $0.id == destinationDeckID }) { throw EngramError.missing("destination deck") }
        var deckMap: [String: String] = [:]
        for deck in candidate.liveDecks {
            if let destinationDeckID { deckMap[deck.id] = destinationDeckID }
            else if let existing = library.decks.first(where: { $0.id == deck.id }) {
                guard !existing.deleted else { throw EngramError.invalid("An imported deck was deleted locally. Choose an existing destination deck or a separate source identity.") }
                deckMap[deck.id] = existing.id
            }
            else if let existing = library.liveDecks.first(where: { $0.name.caseInsensitiveCompare(deck.name) == .orderedSame }) { deckMap[deck.id] = existing.id }
            else {
                guard !library.decks.contains(where: { $0.id == deck.id }) else { throw EngramError.invalid("An imported deck was deleted locally. Choose an existing destination deck or a separate source identity.") }
                library.decks.append(deck); deckMap[deck.id] = deck.id
            }
        }
        let existingNoteIDs = Set(library.notes.map(\.id))
        var acceptedNotes = Set<String>(), changedNotes = Set<String>()
        for var note in candidate.liveNotes {
            guard let deckID = deckMap[note.deckID] else { throw EngramError.invalid("Imported note has no destination deck.") }
            note.deckID = deckID
            if let index = library.notes.firstIndex(where: { $0.id == note.id }) {
                guard !library.notes[index].deleted else { summary.skippedNotes += 1; continue }
                switch duplicates {
                case .skipExisting: summary.skippedNotes += 1; continue
                case .keepExisting: summary.skippedNotes += 1; acceptedNotes.insert(note.id)
                case .updateContent:
                    guard library.notes[index].kind == note.kind else { throw EngramError.invalid("An imported duplicate changed note type. This needs an explicit type migration.") }
                    library.notes[index] = note; summary.updatedNotes += 1; acceptedNotes.insert(note.id); changedNotes.insert(note.id)
                }
            } else { library.notes.append(note); summary.addedNotes += 1; acceptedNotes.insert(note.id); changedNotes.insert(note.id) }
        }
        for var card in candidate.liveCards where acceptedNotes.contains(card.noteID) {
            guard let deckID = deckMap[card.deckID] else { throw EngramError.invalid("Imported card has no destination deck.") }
            card.deckID = deckID
            if let index = library.cards.firstIndex(where: { $0.id == card.id }) {
                guard library.cards[index].noteID == card.noteID, library.cards[index].ordinal == card.ordinal else { throw EngramError.invalid("A source card identifier now refers to different content. Import under a separate source identity.") }
                if duplicates == .updateContent {
                    // An accepted source sibling is live again; its local progress and suspension remain intact.
                    library.cards[index].deckID = deckID
                    library.cards[index].sourceSchedule = card.sourceSchedule
                    library.cards[index].retired = false
                    library.cards[index].version += 1
                }
            } else if !existingNoteIDs.contains(card.noteID) || duplicates == .updateContent {
                guard !library.cards.contains(where: { $0.noteID == card.noteID && $0.ordinal == card.ordinal }) else {
                    throw EngramError.invalid("A source card was recreated with a different identifier for an existing note and ordinal. Import under a separate source identity.")
                }
                library.cards.append(card); summary.addedCards += 1
            } else {
                throw EngramError.invalid("The source adds a card to existing content. Choose Update content or Skip existing notes to resolve this change.")
            }
        }
        // Retire no-longer-generated siblings on content updates; do not delete their evidence.
        for note in library.liveNotes where changedNotes.contains(note.id) {
            let ordinals = Set(try CardRenderer.ordinals(for: NoteDraft(note: note)))
            for index in library.cards.indices where library.cards[index].noteID == note.id && !ordinals.contains(library.cards[index].ordinal) {
                library.cards[index].retired = true; library.cards[index].version += 1
            }
        }
        let cardIDs = Set(library.cards.filter { acceptedNotes.contains($0.noteID) }.map(\.id))
        var historyByID = Dictionary(uniqueKeysWithValues: library.importedReviews.map { ($0.id, $0) })
        for event in candidate.importedReviews where cardIDs.contains(event.cardID) {
            if let existing = historyByID[event.id] {
                guard existing == event else { throw EngramError.invalid("Imported history changed under an existing identifier. Use a separate source identity to retain both records.") }
            } else {
                library.importedReviews.append(event); historyByID[event.id] = event; summary.addedHistory += 1
            }
        }
        for media in candidate.media {
            if let existing = library.media.first(where: { $0.name.caseInsensitiveCompare(media.name) == .orderedSame }) {
                guard existing.name == media.name, existing.data == media.data else { throw EngramError.invalid("Media filename collision: \(media.name). Rename the conflicting source media before importing; existing media was not overwritten.") }
            } else { library.media.append(media); summary.addedMedia += 1 }
        }
        library.session = nil
        try LibraryValidation.validate(library)
        try Task.checkCancellation()
        try await preImportBackup(original)
        try Task.checkCancellation()
        try await repository.commit(library, expectedRevision: expectedRevision)
        return summary
    }
    public func replaceLibrary(_ candidate: LibrarySnapshot, expectedRevision: Int,
        preImportBackup: @Sendable (LibrarySnapshot) async throws -> Void) async throws {
        try LibraryValidation.validate(candidate)
        let original = try await repository.read()
        guard original.revision == expectedRevision else { throw EngramError.conflict }
        try Task.checkCancellation()
        try await preImportBackup(original)
        try Task.checkCancellation()
        try await restore(candidate, expectedRevision: expectedRevision,expectedContext:original.repositoryContext)
    }
}
