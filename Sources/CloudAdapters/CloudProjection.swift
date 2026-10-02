import Foundation
import LearningCore

public struct CloudProjectionEntity: Codable, Equatable, Sendable {
    public var kind: String
    public var id: String
    public var deckID: String?
    public var payload: JSONValue
    public var deleted: Bool
    public var key: String { kind + ":" + id }
}
public enum CloudProjection {
    /// Shared content and learner state have independent identities and authorization scopes.
    public static func entities(_ library: LibrarySnapshot,userID: UUID,ownedDecks: Set<String>) throws -> [CloudProjectionEntity] {
        let prefix = userID.uuidString.lowercased() + ":"
        var result: [CloudProjectionEntity] = []
        func personal<T:Encodable>(_ category: String,_ id: String,_ value: T,deckID: String? = nil) throws {
            result.append(CloudProjectionEntity(kind:"private",id:prefix + category + ":" + id,deckID:nil,payload:.object(["category":.string(category),"id":.string(id),"deckID":deckID.map(JSONValue.string) ?? .null,"value":try JSONValue.encode(value)]),deleted:false))
        }
        for deck in library.decks {
            var shared = deck; shared.pdfLearning = nil; shared.coverMediaName = nil; shared.desiredRetention = nil
            result.append(CloudProjectionEntity(kind:"deck",id:deck.id,deckID:deck.id,payload:try .encode(shared),deleted:deck.deleted))
            var extras: [String:JSONValue] = ["desiredRetention":deck.desiredRetention.map(JSONValue.number) ?? .null,"coverMediaName":deck.coverMediaName.map(JSONValue.string) ?? .null]
            if ownedDecks.contains(deck.id),let pdf = deck.pdfLearning { extras["pdfLearning"] = try .encode(pdf) }
            try personal("deckExtras",deck.id,extras,deckID:deck.id)
        }
        for note in library.notes {
            var shared = note; shared.origin = nil
            result.append(CloudProjectionEntity(kind:"note",id:note.id,deckID:note.deckID,payload:try .encode(shared),deleted:note.deleted))
            if let origin = note.origin,ownedDecks.contains(note.deckID) { try personal("noteOrigin",note.id,origin,deckID:note.deckID) }
        }
        for card in library.cards { try personal("card",card.id,card,deckID:card.deckID) }
        for review in library.reviews { try personal("review",review.id,review,deckID:review.deckID) }
        for imported in library.importedReviews { try personal("importedReview",imported.id,imported) }
        for correction in library.corrections { try personal("correction",correction.id,correction) }
        for media in library.media { try personal("media",media.name,media) }
        try personal("settings","study",library.settings)
        for attempt in library.answerAttempts ?? [] { try personal("attempt",attempt.id,attempt) }
        if let state = library.assistantState {
            for conversation in state.conversations { try personal("conversation",conversation.id,conversation) }
            for run in state.runs { try personal("run",run.id,run) }
            for memory in state.memory { try personal("memory",memory.id,memory) }
        }
        return result
    }
    public static func apply(_ entity: CloudProjectionEntity,to library: inout LibrarySnapshot) throws {
        if entity.kind == "deck" {
            var deck = try entity.payload.decode(Deck.self)
            if let previous = library.decks.first(where: { $0.id == deck.id }) { deck.pdfLearning = previous.pdfLearning; deck.desiredRetention = previous.desiredRetention; deck.coverMediaName = previous.coverMediaName }
            replace(deck,in:&library.decks); return
        }
        if entity.kind == "note" {
            var note = try entity.payload.decode(Note.self)
            note.origin = library.notes.first(where: { $0.id == note.id })?.origin
            replace(note,in:&library.notes); return
        }
        guard case .object(let envelope) = entity.payload,case .string(let category) = envelope["category"],case .string(let id) = envelope["id"],let value = envelope["value"] else { throw EngramError.invalid("Malformed learner entity.") }
        switch category {
        case "deckExtras":
            guard let index = library.decks.firstIndex(where: { $0.id == id }),case .object(let extras) = value else { return }
            if case .number(let retention) = extras["desiredRetention"] { library.decks[index].desiredRetention = retention }
            if case .string(let cover) = extras["coverMediaName"] { library.decks[index].coverMediaName = cover }
            if let pdf = extras["pdfLearning"] { library.decks[index].pdfLearning = try pdf.decode(PDFLearningRecord.self) }
        case "noteOrigin": if let index = library.notes.firstIndex(where: { $0.id == id }) { library.notes[index].origin = try value.decode(ImportOrigin.self) }
        case "card": replace(try value.decode(StudyCard.self),in:&library.cards)
        case "review": replace(try value.decode(ReviewEvent.self),in:&library.reviews)
        case "importedReview": replace(try value.decode(ImportedReview.self),in:&library.importedReviews)
        case "correction": replace(try value.decode(ReviewCorrection.self),in:&library.corrections)
        case "media": replace(try value.decode(MediaFile.self),in:&library.media)
        case "settings": library.settings = try value.decode(StudySettings.self)
        case "attempt": var attempts = library.answerAttempts ?? []; replace(try value.decode(AnswerAttempt.self),in:&attempts); library.answerAttempts = attempts
        case "conversation", "run", "memory":
            var state = library.assistantState ?? LearningAssistantState()
            if category == "conversation" { replace(try value.decode(LearningConversation.self),in:&state.conversations) }
            else if category == "run" { replace(try value.decode(AIActionRun.self),in:&state.runs) }
            else { replace(try value.decode(LearningMemory.self),in:&state.memory) }
            library.assistantState = state
        default: throw EngramError.invalid("Unsupported learner entity.")
        }
    }
    private static func replace<T:Identifiable>(_ value: T,in values: inout [T]) where T.ID == String {
        if let index = values.firstIndex(where: { $0.id == value.id }) { values[index] = value } else { values.append(value) }
    }
}
