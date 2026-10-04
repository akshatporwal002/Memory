import Foundation

public struct ResearchConsent: Codable, Equatable, Sendable {
    public var metrics = false
    public var answerContent = false
    public var revision = 1
    public var updatedAt = Date()
    public init() {}
}

/// Fixed fields only: no arbitrary dictionaries, provider errors, keys or documents.
public struct ResearchEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: String
    public var occurredAt: Date
    public var answeredAt: Date?
    public var reviewID: String?
    public var correctedReviewID: String?
    public var questionID: String?
    public var attemptID: String?
    public var questionType: String?
    public var subject: String?
    public var questionSubtype: String?
    public var questionSchemaVersion: Int?
    public var inputModality: String?
    public var gradingMethod: String?
    public var outcome: String?
    public var rating: Int?
    public var estimatedRecall: Double?
    public var durationMS: Double?
    public var firstTokenMS: Double?
    public var queueMS: Double?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var cachedTokens: Int?
    public var reasoningTokens: Int?
    public var tokenMeasurement: String?
    public var provider: String?
    public var model: String?
    public var batchSize: Int?
    public var answerText: String?
    public var consentRevision: Int
    public init(id: UUID = UUID(), kind: String, occurredAt: Date = Date(), consentRevision: Int = 1) {
        self.id = id; self.kind = kind; self.occurredAt = occurredAt; self.consentRevision = consentRevision
    }
    public func permitted(by consent: ResearchConsent, now: Date = Date()) -> Self? {
        let allowed = ["review", "review_corrected", "question_activity", "answer_submitted", "ai_completed", "batch_completed", "ai_failed", "transcript_confirmed", "feedback_disputed", "math_entry", "tutor_activated"]
        guard consent.metrics, allowed.contains(kind), occurredAt >= consent.updatedAt,
              occurredAt <= now.addingTimeInterval(300), occurredAt >= now.addingTimeInterval(-365 * 86400),
              [durationMS, firstTokenMS, queueMS].compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= 0 }),
              [inputTokens, outputTokens, cachedTokens, reasoningTokens].compactMap({ $0 }).allSatisfy({ $0 >= 0 }),
              estimatedRecall.map({ $0.isFinite && (0...1).contains($0) }) ?? true else { return nil }
        var event = self
        event.questionType = event.questionType.map { String($0.prefix(80)) }
        event.subject = event.subject.map { String($0.prefix(80)) }
        event.questionSubtype = event.questionSubtype.map { String($0.prefix(80)) }
        event.inputModality = event.inputModality.map { String($0.prefix(40)) }
        event.gradingMethod = event.gradingMethod.map { String($0.prefix(80)) }
        event.provider = event.provider.map { String($0.prefix(80)) }
        event.model = event.model.map { String($0.prefix(160)) }
        event.consentRevision = consent.revision
        if !consent.answerContent { event.answerText = nil }
        if let answerText = event.answerText { event.answerText = String(answerText.prefix(4000)) }
        return event
    }
}
