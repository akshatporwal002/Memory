import Foundation

/// A finite-grid Bayesian Rasch filter with a Gaussian random-walk transition.
/// One-dimensional ability, fixed calibrated item difficulty, no assumed positive learning drift.
/// Grid quadrature is an approximation, not the full Wang/Berger/Burdick DIR model.
public struct DynamicRaschLearnerPredictor: LearnerPredictor {
    public struct Artifact: Codable, Sendable {
        public let revision: String
        public let trainingReport: String
        public let heldOutValidationReport: String
        public let scaleAnchor: String
        public let grid: [Double]
        public let prior: [Double]
        public let variancePerDay: Double
        public let items: [DAS3HLearnerPredictor.Item]
        public init(revision: String, trainingReport: String, heldOutValidationReport: String, scaleAnchor: String,
                    grid: [Double], prior: [Double], variancePerDay: Double, items: [DAS3HLearnerPredictor.Item]) {
            self.revision = revision; self.trainingReport = trainingReport; self.heldOutValidationReport = heldOutValidationReport
            self.scaleAnchor = scaleAnchor; self.grid = grid; self.prior = prior; self.variancePerDay = variancePerDay; self.items = items
        }
    }
    public struct Posterior: Codable, Equatable, Sendable {
        public let time: Date
        public let probabilities: [Double]
        public init(time: Date, probabilities: [Double]) { self.time = time; self.probabilities = probabilities }
    }
    private let artifact: Artifact
    public let model = LearnerModelID.dynamicRasch
    public var artifactRevision: String { artifact.revision }
    public init(artifact: Artifact) { self.artifact = artifact }
    public var readiness: String? {
        guard !artifact.revision.isEmpty, !artifact.trainingReport.isEmpty, !artifact.heldOutValidationReport.isEmpty,
              !artifact.scaleAnchor.isEmpty, (5...201).contains(artifact.grid.count), artifact.grid.allSatisfy(\.isFinite),
              zip(artifact.grid, artifact.grid.dropFirst()).allSatisfy({ $0 < $1 }),
              LearnerMath.validateDistribution(artifact.prior, count: artifact.grid.count),
              artifact.variancePerDay.isFinite, artifact.variancePerDay >= 0, !artifact.items.isEmpty,
              artifact.items.allSatisfy({ !$0.questionID.isEmpty && $0.questionVersion >= 0 && $0.difficulty.isFinite }),
              artifact.items.enumerated().allSatisfy({ index, item in !artifact.items.prefix(index).contains { $0.questionID == item.questionID && $0.questionVersion == item.questionVersion } })
        else { return "Calibrated item difficulty, an identified scale, transition variance and held-out validation are required." }
        return nil
    }
    public func compatible(_ row: LearnerEvidence) -> Bool {
        row.acceptance == .accepted && row.correct != nil && row.assisted == false
            && artifact.items.contains { $0.questionID == row.questionID && $0.questionVersion == row.questionVersion }
    }
    public func replay(_ evidence: [LearnerEvidence]) throws -> Data {
        guard readiness == nil else { throw LearnerError.unavailable }
        let rows = try LearnerMath.ordered(evidence)
        guard let first = rows.first else { throw LearnerError.unavailable }
        var state = startingPosterior(at: first.occurredAt)
        for row in rows {
            state = try observe(row, prior: state)
        }
        return try JSONEncoder().encode(state)
    }
    public func startingPosterior(at time: Date) -> Posterior { Posterior(time: time, probabilities: artifact.prior) }
    public func observe(_ row: LearnerEvidence, prior: Posterior) throws -> Posterior {
        try row.validate()
        guard readiness == nil, compatible(row), prior.time.timeIntervalSince1970.isFinite,
              LearnerMath.validateDistribution(prior.probabilities, count: artifact.grid.count),
              let item = artifact.items.first(where: { $0.questionID == row.questionID && $0.questionVersion == row.questionVersion }) else { throw LearnerError.invalidEvidence }
        let weights = try advanced(prior.probabilities, seconds: row.occurredAt.timeIntervalSince(prior.time))
        let posterior = try LearnerMath.normalized(zip(weights, artifact.grid).map { weight, ability in
            let probability = LearnerMath.logistic(ability - item.difficulty)
            return log(max(weight, Double.leastNormalMagnitude)) + log(max(Double.leastNormalMagnitude, row.correct == true ? probability : 1 - probability))
        })
        return Posterior(time: row.occurredAt, probabilities: posterior)
    }
    public func posterior(at time: Date, history payload: Data) throws -> Posterior {
        guard readiness == nil else { throw LearnerError.unavailable }
        let saved = try JSONDecoder().decode(Posterior.self, from: payload)
        guard saved.time.timeIntervalSince1970.isFinite, time.timeIntervalSince1970.isFinite,
              LearnerMath.validateDistribution(saved.probabilities, count: artifact.grid.count) else { throw LearnerError.invalidEvidence }
        return Posterior(time: time, probabilities: try advanced(saved.probabilities, seconds: time.timeIntervalSince(saved.time)))
    }
    public func probability(questionID: String, questionVersion: Int, at time: Date, history payload: Data) throws -> Double {
        guard let item = artifact.items.first(where: { $0.questionID == questionID && $0.questionVersion == questionVersion }) else { throw LearnerError.unavailable }
        let state = try posterior(at: time, history: payload)
        return zip(state.probabilities, artifact.grid).reduce(0) { $0 + $1.0 * LearnerMath.logistic($1.1 - item.difficulty) }
    }
    public func ability(at time: Date, history payload: Data) throws -> (mean: Double, lower: Double, upper: Double) {
        let state = try posterior(at: time, history: payload)
        var cumulative = 0.0, lower = artifact.grid[0], upper = artifact.grid.last!
        var foundLower = false
        for (ability, weight) in zip(artifact.grid, state.probabilities) {
            cumulative += weight
            if !foundLower && cumulative >= 0.025 { lower = ability; foundLower = true }
            if cumulative >= 0.975 { upper = ability; break }
        }
        return (zip(artifact.grid, state.probabilities).reduce(0) { $0 + $1.0 * $1.1 }, lower, upper)
    }
    private func advanced(_ weights: [Double], seconds: Double) throws -> [Double] {
        guard seconds.isFinite, seconds >= 0 else { throw LearnerError.conflict }
        let variance = artifact.variancePerDay * seconds / 86400
        guard variance.isFinite else { throw LearnerError.invalidEvidence }
        if variance == 0 { return weights }
        var result = Array(repeating: 0.0, count: artifact.grid.count)
        for (index, source) in artifact.grid.enumerated() {
            // Cell-width quadrature supports nonuniform grids; endpoints are explicitly truncated.
            let transition = try LearnerMath.normalized(artifact.grid.enumerated().map { j, target in
                let width: Double
                if j == 0 { width = (artifact.grid[1] - target) / 2 }
                else if j == artifact.grid.count - 1 { width = (target - artifact.grid[j - 1]) / 2 }
                else { width = (artifact.grid[j + 1] - artifact.grid[j - 1]) / 2 }
                return -(target - source) * (target - source) / (2 * variance) + log(width)
            })
            for j in result.indices { result[j] += weights[index] * transition[j] }
        }
        return result
    }
}
