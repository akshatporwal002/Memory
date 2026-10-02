import Foundation

public enum EngramError: Error, LocalizedError, Equatable {
    case invalid(String), conflict, missing(String), unsupported(String), storage(String)
    public var errorDescription: String? {
        switch self {
        case .invalid(let message), .unsupported(let message), .storage(let message): return message
        case .conflict: return "This content changed. Reload it and try again; your saved reviews are safe."
        case .missing(let name): return "The \(name) is no longer available."
        }
    }
}
public enum NoteKind: String, Codable, CaseIterable, Sendable { case basic, reversed, cloze, unsupported }
public enum Grade: Int, Codable, CaseIterable, Sendable { case again = 1, hard, good, easy
    public var label: String { switch self { case .again: return "Again"; case .hard: return "Hard"; case .good: return "Good"; case .easy: return "Easy" } }
}
public enum LearningPhase: String, Codable, Sendable { case new, learning, review, relearning }

public struct ScheduleState: Codable, Equatable, Sendable {
    public var schedulerID: String
    public var implementationVersion: String
    public var schemaVersion: Int
    public var settingsVersion: Int
    public var due: Date
    public var phase: LearningPhase
    public var payload: Data
    public init(schedulerID: String, implementationVersion: String = "1", schemaVersion: Int = 1,
                settingsVersion: Int = 1, due: Date, phase: LearningPhase, payload: Data = Data()) {
        self.schedulerID = schedulerID; self.implementationVersion = implementationVersion
        self.schemaVersion = schemaVersion; self.settingsVersion = settingsVersion
        self.due = due; self.phase = phase; self.payload = payload
    }
}
public struct Deck: Codable, Identifiable, Equatable, Sendable {
    /// Source-preserving PDF learning metadata. Optional for old libraries and backups.
    public var pdfLearning: PDFLearningRecord?
    /// Optional for older libraries; source files are owner-private and never part of shared deck metadata.
    public var documents: [LibraryDocument]?
    public var id: String
    public var name: String
    public var deleted: Bool
    /// Optional so libraries written before deck presentation metadata still decode.
    public var createdAt: Date?
    public var modifiedAt: Date?
    public var coverMediaName: String?
    /// Notebook text, retained for portable reading alongside stable editable blocks.
    public var sourceDocument: String?
    public var notebookBlocks: [NotebookBlock]?
    /// Nil inherits the library's desired retention. Old backups decode as nil.
    public var desiredRetention: Double?
    /// Missing means the original arrow-only document format.
    public var documentFormatVersion: Int?
    public init(id: String = UUID().uuidString, name: String, deleted: Bool = false,
                createdAt: Date? = nil, modifiedAt: Date? = nil, coverMediaName: String? = nil, sourceDocument: String? = nil) {
        self.id = id; self.name = name; self.deleted = deleted
        self.createdAt = createdAt; self.modifiedAt = modifiedAt; self.coverMediaName = coverMediaName
        self.sourceDocument = sourceDocument
    }
}
public struct ImportOrigin: Codable, Equatable, Sendable {
    public var namespace: String
    public var noteID: String
    public var guid: String
    public var noteTypeJSON: Data
    public var fields: [String]
    public var metadata: [String: String]
    public init(namespace: String, noteID: String, guid: String, noteTypeJSON: Data = Data(), fields: [String] = [], metadata: [String: String] = [:]) {
        self.namespace = namespace; self.noteID = noteID; self.guid = guid; self.noteTypeJSON = noteTypeJSON
        self.fields = fields; self.metadata = metadata
    }
}
public struct Note: Codable, Identifiable, Equatable, Sendable {
    public var multipleChoice: MultipleChoiceQuestion?
    public var mcq: MultipleChoiceQuestion? { kind == .basic ? multipleChoice ?? MultipleChoiceQuestion.parse(front: front, back: back) : nil }
    public var id: String
    public var deckID: String
    public var kind: NoteKind
    public var front: String
    public var back: String
    public var tags: [String]
    public var source: String
    public var origin: ImportOrigin?
    public var deleted: Bool
    public var modifiedAt: Date
    public init(id: String = UUID().uuidString, deckID: String, kind: NoteKind, front: String, back: String = "", tags: [String] = [], source: String = "", origin: ImportOrigin? = nil, deleted: Bool = false, modifiedAt: Date = Date()) {
        self.id = id; self.deckID = deckID; self.kind = kind; self.front = front; self.back = back
        self.tags = tags; self.source = source; self.origin = origin; self.deleted = deleted; self.modifiedAt = modifiedAt
        self.multipleChoice = kind == .basic ? MultipleChoiceQuestion.parse(front: front, back: back) : nil
    }
}
public struct NoteDraft: Codable, Equatable, Sendable {
    public var id: String?
    public var deckID: String
    public var kind: NoteKind
    public var front: String
    public var back: String
    public var tags: [String]
    public var source: String
    public init(id: String? = nil, deckID: String, kind: NoteKind = .basic, front: String = "", back: String = "", tags: [String] = [], source: String = "") {
        self.id = id; self.deckID = deckID; self.kind = kind; self.front = front; self.back = back; self.tags = tags; self.source = source
    }
    public init(note: Note) { self.init(id: note.id, deckID: note.deckID, kind: note.kind, front: note.front, back: note.back, tags: note.tags, source: note.source) }
}
public struct StudyCard: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var noteID: String
    public var deckID: String
    /// Zero-based template ordinal; for cloze, cN maps to N-1.
    public var ordinal: Int
    public var schedule: ScheduleState
    public var suspended: Bool
    public var retired: Bool
    public var version: Int
    public var sourceCardID: String?
    public var sourceSchedule: [String: String]
    public init(id: String = UUID().uuidString, noteID: String, deckID: String, ordinal: Int = 0, schedule: ScheduleState, suspended: Bool = false, retired: Bool = false, version: Int = 0, sourceCardID: String? = nil, sourceSchedule: [String: String] = [:]) {
        self.id = id; self.noteID = noteID; self.deckID = deckID; self.ordinal = ordinal; self.schedule = schedule
        self.suspended = suspended; self.retired = retired; self.version = version; self.sourceCardID = sourceCardID; self.sourceSchedule = sourceSchedule
    }
}
public struct ReviewEvent: Codable, Identifiable, Equatable, Sendable {
    public var settingsSnapshot: StudySettings?
    public var assessment: AnswerAssessment?
    public var id: String
    public var cardID: String
    public var deckID: String
    public var sessionID: String
    public var rating: Grade
    public var reviewedAt: Date
    public var committedAt: Date
    public var before: ScheduleState
    public var after: ScheduleState
    public init(id: String, cardID: String, deckID: String, sessionID: String, rating: Grade, reviewedAt: Date, committedAt: Date, before: ScheduleState, after: ScheduleState) {
        self.id = id; self.cardID = cardID; self.deckID = deckID; self.sessionID = sessionID; self.rating = rating
        self.reviewedAt = reviewedAt; self.committedAt = committedAt; self.before = before; self.after = after
    }
}
public struct ReviewCorrection: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var reviewID: String
    public var createdAt: Date
    public init(id: String = UUID().uuidString, reviewID: String, createdAt: Date) { self.id = id; self.reviewID = reviewID; self.createdAt = createdAt }
}
/// Verbatim import evidence, including ease=0 operations. Never recast as Engram grades.
public struct ImportedReview: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var cardID: String
    public var origin: String
    public var values: [String: String]
    public init(id: String, cardID: String, origin: String, values: [String: String]) { self.id = id; self.cardID = cardID; self.origin = origin; self.values = values }
}
public struct MediaFile: Codable, Identifiable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var data: Data
    public init(name: String, data: Data) { self.name = name; self.data = data }
}
public struct StudySettings: Codable, Equatable, Sendable {
    public var version = 1
    public var newCardsPerDay = 20
    public var reviewsPerDay = 200
    public var dayStartsAtHour = 4
    public var timeZoneID: String
    public var desiredRetention = 0.9
    public init(timeZoneID: String = TimeZone.current.identifier) { self.timeZoneID = timeZoneID }
}
public struct ReviewPresentation: Codable, Equatable, Sendable {
    public var assessment: AnswerAssessment?
    public var presentationID: String
    public var card: StudyCard
    public var revealedAt: Date?
    public var outcomes: [Grade: ScheduleState]
    public init(card: StudyCard) { self.presentationID = UUID().uuidString; self.card = card; self.revealedAt = nil; self.outcomes = [:] }
}
public struct StudySession: Codable, Identifiable, Equatable, Sendable {
    public var skippedCardIDs: [String]?
    public var id: String
    public var deckID: String?
    public var startedAt: Date
    public var queue: [String]
    public var current: ReviewPresentation?
    public var completed = 0
    public var nextLearningDue: Date?
    public init(id: String = UUID().uuidString, deckID: String?, startedAt: Date, queue: [String], current: ReviewPresentation?) {
        self.id = id; self.deckID = deckID; self.startedAt = startedAt; self.queue = queue; self.current = current
    }
}
public struct LibrarySnapshot: Codable, Equatable, Sendable {
    /// Ephemeral repository lease; never included in backups or synchronized content.
    public var repositoryContext: String? = nil
    private enum CodingKeys: String,CodingKey {
        case assistantState,answerAttempts,schemaVersion,revision,libraryID,decks,notes,cards,reviews,corrections,importedReviews,media,settings,session
    }
    public var assistantState: LearningAssistantState?
    public var answerAttempts: [AnswerAttempt]?
    public var schemaVersion = 1
    public var revision = 0
    public var libraryID = UUID().uuidString
    public var decks: [Deck] = []
    public var notes: [Note] = []
    public var cards: [StudyCard] = []
    public var reviews: [ReviewEvent] = []
    public var corrections: [ReviewCorrection] = []
    public var importedReviews: [ImportedReview] = []
    public var media: [MediaFile] = []
    public var settings = StudySettings()
    public var session: StudySession?
    public init() {}
    public static func == (lhs: Self,rhs: Self) -> Bool {
        lhs.assistantState == rhs.assistantState && lhs.answerAttempts == rhs.answerAttempts && lhs.schemaVersion == rhs.schemaVersion && lhs.revision == rhs.revision && lhs.libraryID == rhs.libraryID && lhs.decks == rhs.decks && lhs.notes == rhs.notes && lhs.cards == rhs.cards && lhs.reviews == rhs.reviews && lhs.corrections == rhs.corrections && lhs.importedReviews == rhs.importedReviews && lhs.media == rhs.media && lhs.settings == rhs.settings && lhs.session == rhs.session
    }
    public var activeReviews: [ReviewEvent] {
        let undone = Set(corrections.map(\.reviewID)); return reviews.filter { !undone.contains($0.id) }
    }
    public var liveDecks: [Deck] { decks.filter { !$0.deleted }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    public var liveNotes: [Note] { notes.filter { !$0.deleted } }
    public var liveCards: [StudyCard] { cards.filter { !$0.retired } }
}
