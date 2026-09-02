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
        let original = try await repository.read()
        guard original.revision == expectedRevision else { throw EngramError.conflict }
        var library = original; var summary = ImportSummary()
        if let destinationDeckID, !library.liveDecks.contains(where: { $0.id == destinationDeckID }) { throw EngramError.missing("destination deck") }
        var deckMap: [String: String] = [:]
        for deck in candidate.liveDecks {
            if let destinationDeckID { deckMap[deck.id] = destinationDeckID }
            else if let existing = library.liveDecks.first(where: { $0.id == deck.id || $0.name.caseInsensitiveCompare(deck.name) == .orderedSame }) { deckMap[deck.id] = existing.id }
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
                    // Preserve local schedule/suspension/retirement. Source evidence remains available for later export/migration.
                    library.cards[index].deckID = deckID
                    library.cards[index].sourceSchedule = card.sourceSchedule
                    library.cards[index].version += 1
                }
            } else if !existingNoteIDs.contains(card.noteID) || duplicates == .updateContent {
                library.cards.append(card); summary.addedCards += 1
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
        var historyIDs = Set(library.importedReviews.map(\.id))
        for event in candidate.importedReviews where cardIDs.contains(event.cardID) && historyIDs.insert(event.id).inserted {
            library.importedReviews.append(event); summary.addedHistory += 1
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
        try await restore(candidate, expectedRevision: expectedRevision)
    }
}
