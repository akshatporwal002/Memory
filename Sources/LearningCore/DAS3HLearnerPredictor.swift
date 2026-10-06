import Foundation

/// DAS3H logistic (embedding dimension zero) inference, per Choffin et al. (2019), Eq. 3–4.
/// Coefficients, learner ability, item difficulty and windows must come from a reviewed fit.
/// This is an inference adapter, not a fitting pipeline or evidence of learning benefit.
public struct DAS3HLearnerPredictor: LearnerPredictor {
    public struct Skill: Codable, Sendable {
        public let easiness: Double
        public let wins: [Double]
        public let attempts: [Double]
        public init(easiness: Double, wins: [Double], attempts: [Double]) {
            self.easiness = easiness; self.wins = wins; self.attempts = attempts
        }
    }
    public struct Item: Codable, Sendable {
        public let questionID: String
        public let questionVersion: Int
        public let difficulty: Double
        public init(questionID: String, questionVersion: Int, difficulty: Double) {
            self.questionID = questionID; self.questionVersion = questionVersion; self.difficulty = difficulty
        }
    }
    public struct Artifact: Codable, Sendable {
        public let revision: String
        public let mappingRevision: String
        public let trainingReport: String
        public let heldOutValidationReport: String
        public let ability: Double
        /// Expanding windows in seconds; nil is the final all-history window.
        public let windows: [Double?]
        public let skills: [String: Skill]
        public let items: [Item]
        public init(revision: String, mappingRevision: String, trainingReport: String, heldOutValidationReport: String,
                    ability: Double, windows: [Double?], skills: [String: Skill], items: [Item]) {
            self.revision = revision; self.mappingRevision = mappingRevision; self.trainingReport = trainingReport
            self.heldOutValidationReport = heldOutValidationReport; self.ability = ability; self.windows = windows
            self.skills = skills; self.items = items
        }
    }
    private let artifact: Artifact
    public let model = LearnerModelID.das3h
    public var artifactRevision: String { artifact.revision }
    public init(artifact: Artifact) { self.artifact = artifact }
    public var readiness: String? {
        let finiteWindows = artifact.windows.compactMap { $0 }
        guard !artifact.revision.isEmpty, !artifact.mappingRevision.isEmpty,
              !artifact.trainingReport.isEmpty, !artifact.heldOutValidationReport.isEmpty,
              artifact.ability.isFinite, !artifact.windows.isEmpty, artifact.windows.last! == nil,
              finiteWindows.count == artifact.windows.count - 1,
              finiteWindows.allSatisfy({ $0.isFinite && $0 > 0 }),
              zip(finiteWindows, finiteWindows.dropFirst()).allSatisfy({ $0 < $1 }),
              !artifact.skills.isEmpty, artifact.skills.allSatisfy({ key, skill in
                  !key.isEmpty && skill.easiness.isFinite && skill.wins.count == artifact.windows.count
                    && skill.attempts.count == artifact.windows.count && (skill.wins + skill.attempts).allSatisfy(\.isFinite)
              }), !artifact.items.isEmpty,
              artifact.items.allSatisfy({ !$0.questionID.isEmpty && $0.questionVersion >= 0 && $0.difficulty.isFinite }),
              artifact.items.enumerated().allSatisfy({ index, item in
                  !artifact.items.prefix(index).contains { $0.questionID == item.questionID && $0.questionVersion == item.questionVersion }
              }) else { return "Reviewed coefficients, item calibration and held-out validation are required." }
        return nil
    }
    public func compatible(_ evidence: LearnerEvidence) -> Bool {
        evidence.acceptance == .accepted && evidence.correct != nil && evidence.assisted == false
            && evidence.mapping.map { $0.revision == artifact.mappingRevision && $0.skillIDs.allSatisfy { artifact.skills[$0] != nil } } == true
    }
    public func replay(_ evidence: [LearnerEvidence]) throws -> Data {
        guard readiness == nil else { throw LearnerError.unavailable }
        for row in evidence { try row.validate(); guard compatible(row) else { throw LearnerError.invalidEvidence } }
        guard Set(evidence.map(\.attemptID)).count == evidence.count else { throw LearnerError.invalidEvidence }
        return try JSONEncoder().encode(evidence)
    }
    /// Model prediction, never an observed outcome. Unknown item difficulty returns unavailable.
    /// The target's outcome and simultaneous/future attempts are excluded to prevent leakage.
    public func probability(mapping: ReviewedSkillMapping, at time: Date, history payload: Data) throws -> Double {
        try mapping.validate()
        guard readiness == nil, time.timeIntervalSince1970.isFinite, mapping.revision == artifact.mappingRevision,
              let item = artifact.items.first(where: { $0.questionID == mapping.questionID && $0.questionVersion == mapping.questionVersion }) else { throw LearnerError.unavailable }
        let rows = try JSONDecoder().decode([LearnerEvidence].self, from: payload)
        _ = try replay(rows)
        var logit = artifact.ability - item.difficulty
        for skillID in mapping.skillIDs {
            guard let skill = artifact.skills[skillID] else { throw LearnerError.unavailable }
            logit += skill.easiness
            let history = rows.filter { $0.occurredAt < time && $0.mapping?.skillIDs.contains(skillID) == true }
            for (index, window) in artifact.windows.enumerated() {
                let within = history.filter { row in window.map { time.timeIntervalSince(row.occurredAt) <= $0 } ?? true }
                logit += skill.wins[index] * log1p(Double(within.filter { $0.correct == true }.count))
                    - skill.attempts[index] * log1p(Double(within.count))
            }
        }
        guard logit.isFinite else { throw LearnerError.invalidEvidence }
        return logit >= 0 ? 1 / (1 + exp(-logit)) : exp(logit) / (1 + exp(logit))
    }
}
