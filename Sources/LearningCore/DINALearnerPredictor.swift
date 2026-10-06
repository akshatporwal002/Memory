import Foundation

/// DINA posterior inference for a single explicitly identified supported assessment.
/// No learning transitions: pooling attempts across assessments would give misleading diagnoses.
public struct DINALearnerPredictor: LearnerPredictor {
    public struct Item: Codable, Sendable {
        public let mapping: ReviewedSkillMapping
        public let slip: Double
        public let guess: Double
        public init(mapping: ReviewedSkillMapping, slip: Double, guess: Double) { self.mapping = mapping; self.slip = slip; self.guess = guess }
    }
    public struct Artifact: Codable, Sendable {
        public let revision: String
        public let assessmentID: String
        public let trainingReport: String
        public let heldOutValidationReport: String
        public let skillIDs: [String]
        /// Binary profile bit i refers to skillIDs[i]. All 2^K profiles are represented.
        public let profilePrior: [Double]
        public let items: [Item]
        public init(revision: String, assessmentID: String, trainingReport: String, heldOutValidationReport: String,
                    skillIDs: [String], profilePrior: [Double], items: [Item]) {
            self.revision = revision; self.assessmentID = assessmentID; self.trainingReport = trainingReport
            self.heldOutValidationReport = heldOutValidationReport; self.skillIDs = skillIDs; self.profilePrior = profilePrior; self.items = items
        }
    }
    private let artifact: Artifact
    public let model = LearnerModelID.dina
    public var artifactRevision: String { artifact.revision }
    public init(artifact: Artifact) { self.artifact = artifact }
    public var readiness: String? {
        guard !artifact.revision.isEmpty, !artifact.assessmentID.isEmpty, !artifact.trainingReport.isEmpty,
              !artifact.heldOutValidationReport.isEmpty, (1...10).contains(artifact.skillIDs.count),
              Set(artifact.skillIDs).count == artifact.skillIDs.count, artifact.skillIDs.allSatisfy({ !$0.isEmpty }),
              LearnerMath.validateDistribution(artifact.profilePrior, count: 1 << artifact.skillIDs.count),
              !artifact.items.isEmpty, artifact.items.allSatisfy({ item in
                  (try? item.mapping.validate()) != nil && Set(item.mapping.skillIDs).isSubset(of: Set(artifact.skillIDs))
                    && item.slip.isFinite && item.guess.isFinite && item.slip > 0 && item.guess > 0
                    && item.slip < 1 && item.guess < 1 && item.slip + item.guess < 1
              }), artifact.items.enumerated().allSatisfy({ index, item in
                  !artifact.items.prefix(index).contains { $0.mapping.questionID == item.mapping.questionID }
              }), Self.identifiable(skillIDs: artifact.skillIDs, mappings: artifact.items.map(\.mapping))
        else { return "A supported identifiable assessment, reviewed Q-matrix and calibrated item/profile parameters are required." }
        return nil
    }
    /// Conservative gate for a known Q: identity block, >=3 measurements per skill,
    /// and distinct remaining Q columns. Structural checks do not establish task validity.
    public static func identifiable(skillIDs: [String], mappings: [ReviewedSkillMapping]) -> Bool {
        guard !skillIDs.isEmpty, Set(skillIDs).count == skillIDs.count else { return false }
        var identity: Set<Int> = []
        for skill in skillIDs {
            guard let index = mappings.indices.first(where: { mappings[$0].skillIDs == [skill] }) else { return false }
            identity.insert(index)
            guard mappings.filter({ $0.skillIDs.contains(skill) }).count >= 3 else { return false }
        }
        let remaining = mappings.indices.filter { !identity.contains($0) }
        let columns = skillIDs.map { skill in remaining.map { mappings[$0].skillIDs.contains(skill) ? "1" : "0" }.joined() }
        return Set(columns).count == columns.count
    }
    public func compatible(_ row: LearnerEvidence) -> Bool {
        row.acceptance == .accepted && row.correct != nil && row.assisted == false && row.assessmentID == artifact.assessmentID
            && row.assessmentSessionID?.isEmpty == false
            && artifact.items.contains { $0.mapping == row.mapping }
    }
    public func selectHistory(_ evidence: [LearnerEvidence]) -> [LearnerEvidence] {
        guard let latest = evidence.max(by: { $0.occurredAt == $1.occurredAt ? $0.attemptID < $1.attemptID : $0.occurredAt < $1.occurredAt }),
              let session = latest.assessmentSessionID else { return [] }
        return evidence.filter { $0.assessmentSessionID == session }
    }
    public func replay(_ evidence: [LearnerEvidence]) throws -> Data {
        guard readiness == nil else { throw LearnerError.unavailable }
        let rows = try LearnerMath.ordered(evidence)
        guard !rows.isEmpty, Set(rows.map(\.questionID)).count == rows.count,
              Set(rows.compactMap(\.assessmentSessionID)).count == 1 else { throw LearnerError.invalidEvidence }
        var logs = artifact.profilePrior.map { $0 > 0 ? log($0) : -Double.infinity }
        for row in rows {
            guard compatible(row), let item = artifact.items.first(where: { $0.mapping == row.mapping }) else { throw LearnerError.invalidEvidence }
            for profile in logs.indices {
                let p = responseProbability(profile: profile, item: item)
                logs[profile] += log(row.correct == true ? p : 1 - p)
            }
        }
        return try JSONEncoder().encode(LearnerMath.normalized(logs))
    }
    public func skillProbabilities(history payload: Data) throws -> [String: Double] {
        let posterior = try decoded(payload)
        return Dictionary(uniqueKeysWithValues: artifact.skillIDs.enumerated().map { index, skill in
            (skill, posterior.indices.filter { $0 & (1 << index) != 0 }.reduce(0) { $0 + posterior[$1] })
        })
    }
    public func probability(mapping: ReviewedSkillMapping, history payload: Data) throws -> Double {
        guard let item = artifact.items.first(where: { $0.mapping == mapping }) else { throw LearnerError.unavailable }
        let posterior = try decoded(payload)
        return posterior.indices.reduce(0) { $0 + posterior[$1] * responseProbability(profile: $1, item: item) }
    }
    private func decoded(_ payload: Data) throws -> [Double] {
        guard readiness == nil else { throw LearnerError.unavailable }
        let values = try JSONDecoder().decode([Double].self, from: payload)
        guard LearnerMath.validateDistribution(values, count: 1 << artifact.skillIDs.count) else { throw LearnerError.invalidEvidence }
        return values
    }
    private func responseProbability(profile: Int, item: Item) -> Double {
        let mastered = item.mapping.skillIDs.allSatisfy { skill in
            guard let index = artifact.skillIDs.firstIndex(of: skill) else { return false }
            return profile & (1 << index) != 0
        }
        return mastered ? 1 - item.slip : item.guess
    }
}
