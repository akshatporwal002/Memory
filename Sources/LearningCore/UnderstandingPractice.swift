import Foundation

public struct UnderstandingSettings: Codable, Equatable, Sendable {
    public enum ReviewTiming: String, Codable, CaseIterable, Sendable { case background, sessionEnd }
    public var enabled = true
    public var variantCount = 3
    public var harderProgression = false
    public var quickFeedback = false
    public var reviewTiming: ReviewTiming = .background
    public var batchSize = 5
    public var configuration = LearnerConfiguration()
    public init() {}
    public func validate() throws {
        try configuration.validate()
        guard (1...4).contains(variantCount), (1...10).contains(batchSize) else { throw LearnerError.invalidEvidence }
    }
}

/// Automated task checks are not empirical calibration. Accepted mappings remain explicitly AI-reviewed.
public struct VariantValidation: Codable, Equatable, Sendable {
    public var mapping: ReviewedSkillMapping
    public var modelID: String
    public var checkedAt: Date
    public var sourceSupported: Bool
    public var samePrerequisites: Bool
    public var comparableReasoning: Bool
    public var rubricSupported: Bool
    public var harder: Bool
    public var front: String
    public var back: String
    public var rubric: String
    public init(mapping: ReviewedSkillMapping, modelID: String, checkedAt: Date, sourceSupported: Bool,
                samePrerequisites: Bool, comparableReasoning: Bool, rubricSupported: Bool, harder: Bool,
                front: String, back: String, rubric: String) {
        self.mapping = mapping; self.modelID = modelID; self.checkedAt = checkedAt; self.sourceSupported = sourceSupported
        self.samePrerequisites = samePrerequisites; self.comparableReasoning = comparableReasoning; self.rubricSupported = rubricSupported
        self.harder = harder; self.front = front; self.back = back; self.rubric = rubric
    }
    public func supports(_ variant: QuestionVariant, questionID: String) -> Bool {
        (try? mapping.validate()) != nil && !modelID.isEmpty && checkedAt.timeIntervalSince1970.isFinite
            && sourceSupported && samePrerequisites && rubricSupported && (comparableReasoning || harder)
            && front == variant.front && back == variant.back && rubric == variant.rubric
            && mapping.questionID == questionID && mapping.questionVersion == (variant.revision ?? 1)
    }
}

public struct UnderstandingAttempt: Codable, Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable { case presented, queued, assessed, attention, abandoned }
    public var id: String
    public var noteID: String
    public var variant: QuestionVariant
    public var sourceOriginalFront: String
    public var sourceOriginalBack: String
    public var status: Status = .presented
    public var answer: String = ""
    public var assisted: Bool?
    public var activeSeconds: Double?
    public var presentedAt: Date
    public var submittedAt: Date?
    public var draftModifiedAt: Date?
    public var exposed: Bool
    public var providerIdentity: String
    public var gradingModel: String
    public var provisional: Grade?
    public var assessment: AnswerAssessment?
    public var assessmentRevisions: [AnswerAssessment] = []
    public var assessmentJSON: String?
    public var error: String?
    public var correctionReason: String?
    public var errorSkillIDs: [String]?
    /// Recording permission captured with this attempt; later consent does not backfill it.
    public var recordingEnabled: Bool
    public var configuration: LearnerConfiguration
    public init(id: String = UUID().uuidString, note: Note, variant: QuestionVariant, now: Date,
                providerIdentity: String, gradingModel: String, recordingEnabled: Bool, configuration: LearnerConfiguration) {
        self.id = id; noteID = note.id; self.variant = variant; sourceOriginalFront = note.front; sourceOriginalBack = note.back
        presentedAt = now; exposed = !(note.questionFamily?.exposedVariantIDs.isEmpty ?? true)
        self.providerIdentity = providerIdentity; self.gradingModel = gradingModel; self.recordingEnabled = recordingEnabled
        self.configuration = configuration
    }
}
public struct UnderstandingSession: Codable, Equatable, Identifiable, Sendable {
    public var id: String = UUID().uuidString
    public var deckID: String
    public var startedAt: Date
    public var endedAt: Date?
    public var settings: UnderstandingSettings
    public var attempts: [UnderstandingAttempt] = []
    public var current: UnderstandingAttempt? { endedAt == nil ? attempts.first { $0.status == .presented } : nil }
    public init(deckID: String, now: Date, settings: UnderstandingSettings) { self.deckID = deckID; startedAt = now; self.settings = settings }
}
public struct UnderstandingWorkspace: Codable, Sendable {
    public var sessions: [UnderstandingSession] = []
    public init() {}
    public func validate() throws {
        guard sessions.count <= 1000, Set(sessions.map(\.id)).count == sessions.count,
              Set(sessions.flatMap(\.attempts).map(\.id)).count == sessions.flatMap(\.attempts).count else { throw LearnerError.invalidEvidence }
        for session in sessions {
            try session.settings.validate()
            guard session.attempts.count <= 100, session.startedAt.timeIntervalSince1970.isFinite,
                  session.attempts.filter({ $0.status == .presented }).count <= 1 else { throw LearnerError.invalidEvidence }
            for attempt in session.attempts {
                try attempt.variant.validate()
                try attempt.configuration.validate()
                guard !attempt.id.isEmpty, attempt.answer.utf8.count <= 16000, attempt.assessmentRevisions.count <= 100,
                      !attempt.providerIdentity.isEmpty, !attempt.gradingModel.isEmpty,
                      attempt.presentedAt.timeIntervalSince1970.isFinite,
                      attempt.activeSeconds.map({ $0.isFinite && $0 >= 0 }) ?? true else { throw LearnerError.invalidEvidence }
                guard attempt.variant.validation?.supports(attempt.variant, questionID: attempt.noteID + ":variant:" + attempt.variant.id) == true else { throw LearnerError.invalidEvidence }
                let errors = attempt.errorSkillIDs ?? []
                guard Set(errors).count == errors.count, Set(errors).isSubset(of: Set(attempt.variant.validation!.mapping.skillIDs)),
                      errors.isEmpty || attempt.assessment?.outcome == .incorrect else { throw LearnerError.invalidEvidence }
                if let json = attempt.assessmentJSON {
                    guard json.utf8.count <= 100000, let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any], object["attempt_id"] as? String == attempt.id,
                          try LocalAnswerEvidence.validate(json, allowedIDs: Set(attempt.variant.evidence.map(\.id))) == attempt.assessment else { throw LearnerError.invalidEvidence }
                    guard (object["error_skill_ids"] as? [String] ?? []) == errors else { throw LearnerError.invalidEvidence }
                } else if attempt.assessment != nil { throw LearnerError.invalidEvidence }
                if attempt.status == .assessed && (attempt.assessment == nil || attempt.submittedAt == nil || attempt.answer.isEmpty) { throw LearnerError.invalidEvidence }
            }
        }
    }
}

/// Implemented only by an already-installed local runtime. Unavailable is the default;
/// provisional marks never provide accepted correctness or reset recall cards.
public protocol ProvisionalUnderstandingGrader: Sendable {
    var available: Bool { get }
    func grade(answer: String, question: String, expected: String, rubric: String) async throws -> Grade
}
