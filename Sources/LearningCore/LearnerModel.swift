import Foundation

public enum LearnerMode: String, Codable, Sendable { case off, observe, active }
public enum LearnerPurpose: String, Codable, Sendable { case skill, difficulty, diagnosis }
public enum LearnerModelID: String, Codable, CaseIterable, Sendable {
    case das3h, bkt, dynamicRasch, dina
    public var purpose: LearnerPurpose {
        switch self { case .das3h, .bkt: return .skill; case .dynamicRasch: return .difficulty; case .dina: return .diagnosis }
    }
}
public enum LearnerError: Error { case invalidEvidence, conflict, unavailable, unsupportedVersion }

/// New preferences only. Existing study preferences and research consent are separate.
public struct LearnerConfiguration: Codable, Equatable, Sendable {
    public var version = 1
    public fileprivate(set) var revision = 0
    public var skill: LearnerModelID = .das3h
    public var difficulty: LearnerModelID = .dynamicRasch
    public var diagnosis: LearnerModelID = .dina
    public var modes: [LearnerPurpose: LearnerMode] = [.skill: .off, .difficulty: .off, .diagnosis: .off]
    public var fixedPractice = true
    public var provisionalFeedback = false
    public init() {}
    private enum CodingKeys: String, CodingKey { case version, revision, skill, difficulty, diagnosis, modes, fixedPractice, provisionalFeedback }
    public init(from decoder: Decoder) throws {
        self.init(); let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        skill = try c.decodeIfPresent(LearnerModelID.self, forKey: .skill) ?? .das3h
        difficulty = try c.decodeIfPresent(LearnerModelID.self, forKey: .difficulty) ?? .dynamicRasch
        diagnosis = try c.decodeIfPresent(LearnerModelID.self, forKey: .diagnosis) ?? .dina
        modes = try c.decodeIfPresent([LearnerPurpose: LearnerMode].self, forKey: .modes) ?? modes
        fixedPractice = try c.decodeIfPresent(Bool.self, forKey: .fixedPractice) ?? true
        provisionalFeedback = try c.decodeIfPresent(Bool.self, forKey: .provisionalFeedback) ?? false
    }
    public var recallScheduler: String { "fsrs" }
    public func validate() throws {
        guard version == 1 else { throw LearnerError.unsupportedVersion }
        guard revision >= 0, skill.purpose == .skill, difficulty.purpose == .difficulty, diagnosis.purpose == .diagnosis else { throw LearnerError.invalidEvidence }
    }
}

/// Immutable, reviewed Q-matrix row. Question content and mapping have separate versions.
public struct ReviewedSkillMapping: Codable, Equatable, Sendable {
    public let questionID: String
    public let questionVersion: Int
    public let revision: String
    public let skillIDs: [String]
    public let reviewedBy: String
    public init(questionID: String, questionVersion: Int, revision: String, skillIDs: [String], reviewedBy: String) throws {
        guard !questionID.isEmpty, questionVersion >= 0, !revision.isEmpty, !reviewedBy.isEmpty,
              !skillIDs.isEmpty, skillIDs.allSatisfy({ !$0.isEmpty }), Set(skillIDs).count == skillIDs.count else { throw LearnerError.invalidEvidence }
        self.questionID = questionID; self.questionVersion = questionVersion; self.revision = revision
        self.skillIDs = skillIDs.sorted(); self.reviewedBy = reviewedBy
    }
    public func validate() throws {
        let checked = try Self(questionID: questionID, questionVersion: questionVersion,
            revision: revision, skillIDs: skillIDs, reviewedBy: reviewedBy)
        guard checked == self else { throw LearnerError.invalidEvidence }
    }
}

/// One attempt, with append-only grading revisions. Unknown historical fields stay nil.
/// No answer text or FSRS card mutation belongs in this evidence stream.
public struct LearnerEvidence: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case recall, fixedApplication, generatedApplication }
    public enum Acceptance: String, Codable, Sendable { case provisional, accepted, retracted }
    public let attemptID: String
    public let revision: Int
    public let questionID: String
    public let questionVersion: Int
    public let occurredAt: Date
    public let kind: Kind
    public let mapping: ReviewedSkillMapping?
    public let assisted: Bool?
    public let acceptance: Acceptance
    public let correct: Bool?
    public let gradingMethod: String
    public let unfamiliar: Bool?
    public let delaySeconds: Double?
    public let studySeconds: Double?
    public let errorSkillIDs: [String]
    public let assessmentID: String?
    public let assessmentSessionID: String?
    public let configuration: LearnerConfiguration?
    public let policyRevision: String?
    public init(attemptID: String, revision: Int, questionID: String, questionVersion: Int, occurredAt: Date,
                kind: Kind, mapping: ReviewedSkillMapping? = nil, assisted: Bool? = nil,
                acceptance: Acceptance, correct: Bool?, gradingMethod: String, unfamiliar: Bool? = nil,
                delaySeconds: Double? = nil, studySeconds: Double? = nil, errorSkillIDs: [String] = [], assessmentID: String? = nil,
                assessmentSessionID: String? = nil, configuration: LearnerConfiguration? = nil, policyRevision: String? = nil) {
        self.attemptID = attemptID; self.revision = revision; self.questionID = questionID
        self.questionVersion = questionVersion; self.occurredAt = occurredAt; self.kind = kind
        self.mapping = mapping; self.assisted = assisted; self.acceptance = acceptance; self.correct = correct
        self.gradingMethod = gradingMethod; self.unfamiliar = unfamiliar; self.delaySeconds = delaySeconds
        self.studySeconds = studySeconds; self.errorSkillIDs = errorSkillIDs
        self.assessmentID = assessmentID
        self.assessmentSessionID = assessmentSessionID
        self.configuration = configuration; self.policyRevision = policyRevision
    }
    public func validate() throws {
        try configuration?.validate()
        guard !attemptID.isEmpty, revision > 0, !questionID.isEmpty, questionVersion >= 0,
              occurredAt.timeIntervalSince1970.isFinite, !gradingMethod.isEmpty,
              [delaySeconds, studySeconds].allSatisfy({ $0.map { $0.isFinite && $0 >= 0 } ?? true }),
              Set(errorSkillIDs).count == errorSkillIDs.count else { throw LearnerError.invalidEvidence }
        if let mapping {
            let checked = try ReviewedSkillMapping(questionID: mapping.questionID, questionVersion: mapping.questionVersion,
                revision: mapping.revision, skillIDs: mapping.skillIDs, reviewedBy: mapping.reviewedBy)
            guard checked == mapping, mapping.questionID == questionID, mapping.questionVersion == questionVersion,
                  Set(errorSkillIDs).isSubset(of: Set(mapping.skillIDs)) else { throw LearnerError.invalidEvidence }
        } else if !errorSkillIDs.isEmpty { throw LearnerError.invalidEvidence }
        if acceptance != .accepted && correct != nil { throw LearnerError.invalidEvidence }
    }
}

public struct LearnerSnapshot: Codable, Equatable, Sendable {
    public let id: UUID
    public let model: LearnerModelID
    public let artifactRevision: String
    public let evidenceRevision: Int
    public let compatibleAttempts: Int
    public let payload: Data
    public init(model: LearnerModelID, artifactRevision: String, evidenceRevision: Int, compatibleAttempts: Int, payload: Data) {
        id = UUID(); self.model = model; self.artifactRevision = artifactRevision
        self.evidenceRevision = evidenceRevision; self.compatibleAttempts = compatibleAttempts; self.payload = payload
    }
}

/// Implementations replay their own compatible evidence, never another model's latent state.
/// Registered adapters must supply calibrated artifacts; none are downloaded or fitted implicitly.
public protocol LearnerPredictor: Sendable {
    var model: LearnerModelID { get }
    var artifactRevision: String { get }
    var readiness: String? { get } // nil means ready; otherwise user-facing reason
    func compatible(_ evidence: LearnerEvidence) -> Bool
    func replay(_ evidence: [LearnerEvidence]) throws -> Data
    func selectHistory(_ evidence: [LearnerEvidence]) -> [LearnerEvidence]
}
public extension LearnerPredictor {
    func selectHistory(_ evidence: [LearnerEvidence]) -> [LearnerEvidence] { evidence }
}

public struct LearnerState: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public private(set) var revision = 0
    public private(set) var configuration = LearnerConfiguration()
    public private(set) var evidence: [LearnerEvidence] = []
    public private(set) var snapshots: [LearnerSnapshot] = []
    public private(set) var prepared: [LearnerPurpose: UUID] = [:]
    public private(set) var current: [LearnerPurpose: UUID] = [:]
    public private(set) var configurations: [LearnerConfiguration] = []
    public init() {}
    public mutating func setPracticePreferences(fixed: Bool, provisionalFeedback: Bool) {
        configurations.append(configuration); configuration.fixedPractice = fixed; configuration.provisionalFeedback = provisionalFeedback
        configuration.revision += 1
    }
    public var latest: [LearnerEvidence] {
        var rows: [String: LearnerEvidence] = [:]
        for event in evidence { rows[event.attemptID] = event }
        return rows.values.sorted { $0.occurredAt == $1.occurredAt ? $0.attemptID < $1.attemptID : $0.occurredAt < $1.occurredAt }
    }
    public mutating func append(_ event: LearnerEvidence) throws {
        try event.validate()
        if let identical = evidence.first(where: { $0.attemptID == event.attemptID && $0.revision == event.revision }) {
            guard identical == event else { throw LearnerError.conflict }; return
        }
        let prior = evidence.last { $0.attemptID == event.attemptID }
        guard event.revision == (prior?.revision ?? 0) + 1 else { throw LearnerError.conflict }
        if let prior {
            guard prior.questionID == event.questionID, prior.questionVersion == event.questionVersion,
                  prior.occurredAt == event.occurredAt, prior.kind == event.kind,
                  (prior.studySeconds == event.studySeconds || prior.studySeconds == nil), prior.delaySeconds == event.delaySeconds,
                  prior.unfamiliar == event.unfamiliar, prior.assessmentID == event.assessmentID,
                  prior.assessmentSessionID == event.assessmentSessionID else { throw LearnerError.conflict }
            guard prior.configuration == event.configuration, prior.policyRevision == event.policyRevision else { throw LearnerError.conflict }
        }
        evidence.append(event); revision += 1; prepared = [:]
        // Preserve snapshots as audit evidence, but stale states cannot influence practice.
        current = [:]
        configurations.append(configuration)
        if configuration.modes.values.contains(.active) { configuration.revision += 1 }
        for purpose in LearnerPurpose.all { if configuration.modes[purpose] == .active { configuration.modes[purpose] = .observe } }
    }
    public mutating func prepare(using predictor: any LearnerPredictor) throws -> LearnerSnapshot {
        guard predictor.readiness == nil, !predictor.artifactRevision.isEmpty else { throw LearnerError.unavailable }
        let history = predictor.selectHistory(latest.filter { $0.acceptance == .accepted && $0.correct != nil && predictor.compatible($0) })
        guard !history.isEmpty else { throw LearnerError.unavailable }
        let snapshot = LearnerSnapshot(model: predictor.model, artifactRevision: predictor.artifactRevision,
            evidenceRevision: revision, compatibleAttempts: history.count, payload: try predictor.replay(history))
        snapshots.append(snapshot); prepared[predictor.model.purpose] = snapshot.id; return snapshot
    }
    /// Call only between attempts/sessions. The caller must prove its lifecycle boundary.
    public mutating func switchModel(to model: LearnerModelID, mode: LearnerMode, betweenAttempts: Bool) throws {
        guard mode == .off || betweenAttempts else { throw LearnerError.conflict }
        let purpose = model.purpose
        if mode != .off {
            guard let id = prepared[purpose], let snapshot = snapshots.first(where: { $0.id == id }),
                  snapshot.model == model, snapshot.evidenceRevision == revision else { throw LearnerError.unavailable }
            current[purpose] = id
        } else { current[purpose] = nil }
        configurations.append(configuration)
        switch purpose { case .skill: configuration.skill = model; case .difficulty: configuration.difficulty = model; case .diagnosis: configuration.diagnosis = model }
        configuration.modes[purpose] = mode; configuration.version = 1
        configuration.revision += 1
    }
    public func validate() throws {
        guard schemaVersion == 1 else { throw LearnerError.unsupportedVersion }
        try configuration.validate()
        var rebuilt = LearnerState()
        for row in evidence { try rebuilt.append(row) }
        guard rebuilt.revision == revision, rebuilt.evidence.count == evidence.count,
              Set(snapshots.map(\.id)).count == snapshots.count,
              snapshots.allSatisfy({ !$0.artifactRevision.isEmpty && $0.evidenceRevision > 0 && $0.evidenceRevision <= revision && $0.compatibleAttempts > 0 }) else { throw LearnerError.invalidEvidence }
        for prior in configurations { try prior.validate() }
        for references in [current, prepared] {
            for (purpose, id) in references {
                guard snapshots.contains(where: { $0.id == id && $0.model.purpose == purpose && $0.evidenceRevision == revision }) else { throw LearnerError.invalidEvidence }
            }
        }
        for purpose in LearnerPurpose.all where configuration.modes[purpose] != .off {
            if configuration.modes[purpose] == .active && current[purpose] == nil { throw LearnerError.invalidEvidence }
        }
    }
}
extension LearnerPurpose { fileprivate static var all: [Self] { [.skill, .difficulty, .diagnosis] } }
