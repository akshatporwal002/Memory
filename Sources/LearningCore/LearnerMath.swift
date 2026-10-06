import Foundation

enum LearnerMath {
    static func logistic(_ x: Double) -> Double { x >= 0 ? 1 / (1 + exp(-x)) : exp(x) / (1 + exp(x)) }
    static func normalized(_ logWeights: [Double]) throws -> [Double] {
        guard let largest = logWeights.max(), largest.isFinite else { throw LearnerError.invalidEvidence }
        let weights = logWeights.map { exp($0 - largest) }, total = weights.reduce(0, +)
        guard total.isFinite, total > 0 else { throw LearnerError.invalidEvidence }
        return weights.map { $0 / total }
    }
    static func ordered(_ evidence: [LearnerEvidence]) throws -> [LearnerEvidence] {
        guard Set(evidence.map(\.attemptID)).count == evidence.count else { throw LearnerError.invalidEvidence }
        for row in evidence { try row.validate() }
        return evidence.sorted { $0.occurredAt == $1.occurredAt ? $0.attemptID < $1.attemptID : $0.occurredAt < $1.occurredAt }
    }
    static func validateDistribution(_ values: [Double], count: Int) -> Bool {
        values.count == count && values.allSatisfy { $0.isFinite && $0 >= 0 }
            && abs(values.reduce(0, +) - 1) < 1e-8
    }
}

public struct LearnerPrediction: Codable, Equatable, Sendable {
    public let model: LearnerModelID
    public let artifactRevision: String
    public let probabilityCorrect: Double?
    public let skillProbabilities: [String: Double]?
    public let abilityMean: Double?
    public let abilityLower: Double?
    public let abilityUpper: Double?
    public let evidenceRevision: Int
    public let mode: LearnerMode
    public let compatibleAttempts: Int?
    public var label: String { "Model prediction — not an observed outcome" }
    public init(model: LearnerModelID, artifactRevision: String, probabilityCorrect: Double?,
                skillProbabilities: [String: Double]? = nil, abilityMean: Double? = nil,
                abilityLower: Double? = nil, abilityUpper: Double? = nil, evidenceRevision: Int, mode: LearnerMode,
                compatibleAttempts: Int? = nil) {
        self.model = model; self.artifactRevision = artifactRevision; self.probabilityCorrect = probabilityCorrect
        self.skillProbabilities = skillProbabilities; self.abilityMean = abilityMean
        self.abilityLower = abilityLower; self.abilityUpper = abilityUpper; self.evidenceRevision = evidenceRevision; self.mode = mode
        self.compatibleAttempts = compatibleAttempts
    }
}
