import Foundation

/// Exact reviewed content prevents reusing a Q-row after a question changes.
/// A reviewed version is independent of optimistic card/scheduling revisions.
public struct ReviewedLearnerQuestion: Codable, Equatable, Sendable {
    public let mapping: ReviewedSkillMapping
    public let prompt: String
    public let expectedAnswer: String
    public let kind: LearnerEvidence.Kind
    public init(mapping: ReviewedSkillMapping, prompt: String, expectedAnswer: String, kind: LearnerEvidence.Kind) {
        self.mapping = mapping; self.prompt = prompt; self.expectedAnswer = expectedAnswer; self.kind = kind
    }
    public func validate() throws {
        try mapping.validate()
        guard !prompt.isEmpty, !expectedAnswer.isEmpty, prompt.utf8.count <= 100000,
              expectedAnswer.utf8.count <= 100000 else { throw LearnerError.invalidEvidence }
    }
}

/// Durable capture registered before answering; after a crash, accepted reviews are reconciled.
public struct LearnerCapture: Codable, Equatable, Sendable {
    public let attemptID: String
    public let presentationID: String
    public let sessionID: String
    public let capturedCardVersion: Int
    public let questionID: String
    public let questionVersion: Int
    public let kind: LearnerEvidence.Kind
    public let mapping: ReviewedSkillMapping?
    public let startedAt: Date
    public var assisted: Bool?
    public var studySeconds: Double?
    public let delaySeconds: Double?
    public let unfamiliar: Bool?
    public let assessmentID: String?
    public let assessmentSessionID: String?
    public let sourceEvidence: [AttemptEvidence]
    public let questionPrompt: String?
    public let questionExpectedAnswer: String?
    public let configuration: LearnerConfiguration?
    public let policyRevision: String?
    public var abandonedAt: Date?
    public var confirmedErrorSkillIDs: [String]?
    public init(attemptID: String, presentationID: String, sessionID: String, capturedCardVersion: Int,
                questionID: String, questionVersion: Int, kind: LearnerEvidence.Kind, mapping: ReviewedSkillMapping?,
                startedAt: Date, assisted: Bool?, studySeconds: Double? = nil, delaySeconds: Double? = nil,
                unfamiliar: Bool? = nil, assessmentID: String? = nil, assessmentSessionID: String? = nil,
                sourceEvidence: [AttemptEvidence] = [], questionPrompt: String? = nil, questionExpectedAnswer: String? = nil,
                configuration: LearnerConfiguration? = nil, policyRevision: String? = nil) {
        self.attemptID = attemptID; self.presentationID = presentationID; self.sessionID = sessionID
        self.capturedCardVersion = capturedCardVersion; self.questionID = questionID; self.questionVersion = questionVersion
        self.kind = kind; self.mapping = mapping; self.startedAt = startedAt; self.assisted = assisted
        self.studySeconds = studySeconds; self.delaySeconds = delaySeconds; self.unfamiliar = unfamiliar
        self.assessmentID = assessmentID; self.assessmentSessionID = assessmentSessionID; self.sourceEvidence = sourceEvidence
        self.questionPrompt = questionPrompt; self.questionExpectedAnswer = questionExpectedAnswer
        self.configuration = configuration; self.policyRevision = policyRevision
    }
    public func evidence(revision: Int, acceptance: LearnerEvidence.Acceptance, correct: Bool?, method: String,
                         knownAssistance: Bool? = nil, errorSkillIDs: [String]? = nil) -> LearnerEvidence {
        LearnerEvidence(attemptID: attemptID, revision: revision, questionID: questionID, questionVersion: questionVersion,
            occurredAt: startedAt, kind: kind, mapping: mapping, assisted: knownAssistance ?? assisted,
            acceptance: acceptance, correct: correct, gradingMethod: method, unfamiliar: unfamiliar,
            delaySeconds: delaySeconds, studySeconds: studySeconds, errorSkillIDs: errorSkillIDs ?? confirmedErrorSkillIDs ?? [], assessmentID: assessmentID,
            assessmentSessionID: assessmentSessionID, configuration: configuration, policyRevision: policyRevision)
    }
    public func validate() throws {
        try evidence(revision: 1, acceptance: .provisional, correct: nil, method: "capture").validate()
        guard !presentationID.isEmpty, !sessionID.isEmpty, capturedCardVersion >= 0,
              sourceEvidence.count <= 20, sourceEvidence.allSatisfy({ !$0.id.isEmpty && !$0.version.isEmpty && $0.text.utf8.count <= 100000 }) else { throw LearnerError.invalidEvidence }
    }
}

public struct LearnerArtifactReview: Codable, Sendable {
    public let artifactID: String
    public let reviewedBy: String
    public let reviewedAt: Date
    public init(artifactID: String, reviewedBy: String, reviewedAt: Date) {
        self.artifactID = artifactID; self.reviewedBy = reviewedBy; self.reviewedAt = reviewedAt
    }
}

public struct LearnerWorkspace: Codable, Sendable {
    public var deadlineRecords: [DeadlineRecord]?
    public var understanding: UnderstandingWorkspace?
    public var schemaVersion = 1
    public var revision = 0
    public var recordingEnabled = false
    public var questions: [ReviewedLearnerQuestion] = []
    public var captures: [LearnerCapture] = []
    public var candidates: [LearnerCalibrationCandidate] = []
    public var artifactReviews: [LearnerArtifactReview] = []
    public init() {}
    public func validate() throws {
        guard (deadlineRecords?.count ?? 0) <= 500,
              Set((deadlineRecords ?? []).map { $0.goal.deckID }).count == (deadlineRecords?.count ?? 0) else { throw LearnerError.invalidEvidence }
        for record in deadlineRecords ?? [] { try record.goal.validate(); guard record.forecasts.count <= 100 else { throw LearnerError.invalidEvidence } }
        try understanding?.validate()
        guard schemaVersion == 1, revision >= 0, captures.count <= 500000, questions.count <= 50000,
              candidates.count <= 100, Set(captures.map(\.attemptID)).count == captures.count,
              Set(candidates.map { $0.report.id }).count == candidates.count,
              Set(artifactReviews.map(\.artifactID)).count == artifactReviews.count else { throw LearnerError.invalidEvidence }
        for question in questions { try question.validate() }
        guard questions.enumerated().allSatisfy({ index, question in !questions.prefix(index).contains { prior in
            prior.mapping.questionID == question.mapping.questionID && prior.mapping.questionVersion == question.mapping.questionVersion && prior.mapping.revision == question.mapping.revision
        } }) else { throw LearnerError.invalidEvidence }
        for capture in captures { try capture.validate() }
        for candidate in candidates { _ = try candidate.predictor() }
        for review in artifactReviews {
            guard !review.reviewedBy.isEmpty, review.reviewedAt.timeIntervalSince1970.isFinite,
                  candidates.contains(where: { $0.report.id == review.artifactID && $0.report.eligibleForReview }) else { throw LearnerError.invalidEvidence }
        }
    }
    public func candidate(for model: LearnerModelID, state: LearnerState) -> LearnerCalibrationCandidate? {
        let latest = Dictionary(uniqueKeysWithValues: state.latest.map { ($0.attemptID, $0.revision) })
        return candidates.last { candidate in
            candidate.report.model == model && candidate.report.eligibleForReview
                && artifactReviews.contains(where: { $0.artifactID == candidate.report.id })
                && candidate.sourceRevisions.allSatisfy { latest[$0.key] == $0.value }
        }
    }
}

public protocol LearnerModelStore: Sendable {
    func load(account: UUID, library: String) async throws -> LearnerState
    func workspace(account: UUID, library: String) async throws -> LearnerWorkspace
    func saveWorkspace(_ workspace: LearnerWorkspace, expectedRevision: Int, account: UUID, library: String) async throws
    func reconcile(_ events: [LearnerEvidence], refreshAtBoundary: Bool, account: UUID, library: String) async throws
    func prepare(using predictor: any LearnerPredictor, account: UUID, library: String) async throws -> LearnerSnapshot
    func switchModel(to model: LearnerModelID, mode: LearnerMode, expectedEvidenceRevision: Int, betweenAttempts: Bool, account: UUID, library: String) async throws
    func setPracticePreferences(fixed: Bool, provisionalFeedback: Bool, account: UUID, library: String) async throws
}
