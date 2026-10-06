import Foundation

/// Classical single-skill BKT. Multi-skill questions are excluded, not split into fake attempts.
/// Artifact metadata is a readiness declaration from a reviewed calibration process,
/// not evidence that Engram has fitted or validated these parameters itself.
public struct BKTLearnerPredictor: LearnerPredictor {
    public struct Parameters: Codable, Equatable, Sendable {
        public let prior: Double
        public let learn: Double
        public let guess: Double
        public let slip: Double
        public init(prior: Double, learn: Double, guess: Double, slip: Double) {
            self.prior = prior; self.learn = learn; self.guess = guess; self.slip = slip
        }
    }
    public struct Artifact: Codable, Sendable {
        public let revision: String
        public let mappingRevision: String
        public let trainingReport: String
        public let heldOutValidationReport: String
        public let parameters: [String: Parameters]
        public init(revision: String, mappingRevision: String, trainingReport: String,
                    heldOutValidationReport: String, parameters: [String: Parameters]) {
            self.revision = revision; self.mappingRevision = mappingRevision; self.trainingReport = trainingReport
            self.heldOutValidationReport = heldOutValidationReport; self.parameters = parameters
        }
    }
    private let artifact: Artifact
    public let model = LearnerModelID.bkt
    public var artifactRevision: String { artifact.revision }
    public var readiness: String? {
        guard !artifact.revision.isEmpty, !artifact.mappingRevision.isEmpty,
              !artifact.trainingReport.isEmpty, !artifact.heldOutValidationReport.isEmpty,
              !artifact.parameters.isEmpty, artifact.parameters.allSatisfy({ skill, p in
                  !skill.isEmpty && [p.prior, p.learn, p.guess, p.slip].allSatisfy { $0.isFinite && $0 > 0 && $0 < 1 }
                    && p.guess + p.slip < 1
              }) else { return "Reviewed calibration and held-out validation are required." }
        return nil
    }
    public init(artifact: Artifact) { self.artifact = artifact }
    public func compatible(_ evidence: LearnerEvidence) -> Bool {
        guard evidence.acceptance == .accepted, evidence.correct != nil, evidence.assisted == false,
              let mapping = evidence.mapping, mapping.revision == artifact.mappingRevision,
              mapping.skillIDs.count == 1, let skill = mapping.skillIDs.first else { return false }
        return artifact.parameters[skill] != nil
    }
    public func replay(_ evidence: [LearnerEvidence]) throws -> Data {
        guard readiness == nil else { throw LearnerError.unavailable }
        guard Set(evidence.map(\.attemptID)).count == evidence.count else { throw LearnerError.invalidEvidence }
        var mastery: [String: Double] = [:]
        for row in evidence.sorted(by: { $0.occurredAt == $1.occurredAt ? $0.attemptID < $1.attemptID : $0.occurredAt < $1.occurredAt }) {
            try row.validate()
            guard compatible(row), let skill = row.mapping?.skillIDs.first,
                  let p = artifact.parameters[skill], let correct = row.correct else { throw LearnerError.invalidEvidence }
            let prior = mastery[skill] ?? p.prior
            let masteredLikelihood = correct ? 1 - p.slip : p.slip
            let unmasteredLikelihood = correct ? p.guess : 1 - p.guess
            let posterior = prior * masteredLikelihood / (prior * masteredLikelihood + (1 - prior) * unmasteredLikelihood)
            mastery[skill] = posterior + (1 - posterior) * p.learn
        }
        return try JSONEncoder().encode(mastery)
    }
    public func probability(mapping: ReviewedSkillMapping, history payload: Data) throws -> Double {
        try mapping.validate()
        guard readiness == nil, mapping.revision == artifact.mappingRevision, mapping.skillIDs.count == 1,
              let skill = mapping.skillIDs.first, let p = artifact.parameters[skill] else { throw LearnerError.unavailable }
        let mastery = try JSONDecoder().decode([String: Double].self, from: payload)
        guard let learned = mastery[skill], learned.isFinite, (0...1).contains(learned) else { throw LearnerError.unavailable }
        return learned * (1 - p.slip) + (1 - learned) * p.guess
    }
    public func mastery(mapping: ReviewedSkillMapping, history payload: Data) throws -> [String: Double] {
        _ = try probability(mapping: mapping, history: payload)
        let values = try JSONDecoder().decode([String: Double].self, from: payload)
        let skill = mapping.skillIDs[0]
        return [skill: values[skill]!]
    }
}
