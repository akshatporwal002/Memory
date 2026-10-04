import Foundation

public struct AnswerAnnotation: Codable, Equatable, Sendable {
    public var startUTF16: Int
    public var lengthUTF16: Int
    public var text: String
    public var kind: String
    public init(startUTF16: Int,lengthUTF16: Int,text: String,kind: String) {
        self.startUTF16 = startUTF16; self.lengthUTF16 = lengthUTF16; self.text = text; self.kind = kind
    }
}
public struct AnswerAddition: Codable, Equatable, Sendable {
    public var text: String
    public var evidenceIDs: [String]
}
public struct AnswerAttempt: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var sessionID: String
    public var presentationID: String
    public var noteID: String
    public var cardID: String
    public var cardVersion: Int
    public var originalAnswer: String
    public var prompt: String
    public var expectedAnswer: String
    public var modelID: String
    public var providerAccountID: String?
    public var evidence: [AttemptEvidence]
    public var acceptedImprovement: String?
    public var assessment: AnswerAssessment?
    public var annotations: [AnswerAnnotation]
    public var additions: [AnswerAddition]
    public var assisted: Bool
    public var createdAt: Date
    public var committedAt: Date?
    public var revisions: [AnswerAssessment]
    /// Optional fields keep existing backups readable. Deferred answers retain their
    /// own scheduling/content snapshot independently of the active screen.
    public var deferredCard: StudyCard?
    public var deferredSettings: StudySettings?
    public var deferredNote: Note?
    public var processingState: String?
    public var processingError: String?
    public var summaryViewedAt: Date?
    public var questionType: String?
    public var questionSchemaVersion: Int?
    public var subject: String?
    public var questionSubtype: String?
    public var inputModality: String?
    public init(sessionID: String, item: ReviewPresentation, noteID: String, answer: String, prompt: String, expected: String, modelID: String, evidence: [AttemptEvidence], now: Date = Date()) {
        id = "attempt-" + item.presentationID; self.sessionID = sessionID; presentationID = item.presentationID
        self.noteID = noteID; cardID = item.card.id; cardVersion = item.card.version
        originalAnswer = answer; self.prompt = prompt; expectedAnswer = expected; self.modelID = modelID; self.evidence = evidence
        annotations = []; additions = []; assisted = false; createdAt = now; revisions = []
    }
    public func validatedAnnotations(_ supplied: [AnswerAnnotation]) -> [AnswerAnnotation] {
        var priorEnd = 0
        return supplied.sorted { $0.startUTF16 < $1.startUTF16 }.filter { span in
            guard ["correct","incorrect","irrelevant"].contains(span.kind),span.startUTF16 >= priorEnd,span.lengthUTF16 > 0,
                  span.startUTF16 <= originalAnswer.utf16.count,span.lengthUTF16 <= originalAnswer.utf16.count - span.startUTF16,
                  let range = Range(NSRange(location:span.startUTF16,length:span.lengthUTF16),in:originalAnswer),
                  String(originalAnswer[range]) == span.text,
                  originalAnswer.indices.contains(range.lowerBound),
                  range.upperBound == originalAnswer.endIndex || originalAnswer.indices.contains(range.upperBound) else { return false }
            priorEnd = span.startUTF16 + span.lengthUTF16; return true
        }
    }
}
public struct AttemptEvidence: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var text: String
    public var version: String
    public init(id: String,text: String,version: String) { self.id = id; self.text = text; self.version = version }
}
