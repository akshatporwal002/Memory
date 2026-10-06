import Foundation

extension LearnerCalibration {
    static func evaluate(model: LearnerModelID, parameters: Data, training: [LearnerTrainingRow],
                         validation: [LearnerTrainingRow], target: String) throws -> [(Double, Bool)] {
        let decoder = JSONDecoder(), encoder = JSONEncoder()
        var result: [(Double, Bool)] = []
        for (learner, heldOut) in Dictionary(grouping: validation, by: \.learnerID).sorted(by: { $0.key < $1.key }) {
            var history = try LearnerMath.ordered(training.filter { $0.learnerID == learner }.map(\.evidence))
            let later = try LearnerMath.ordered(heldOut.map(\.evidence))
            for row in later {
                let probability: Double
                switch model {
                case .bkt:
                    let artifact = try decoder.decode(BKTLearnerPredictor.Artifact.self, from: parameters), predictor = BKTLearnerPredictor(artifact: artifact)
                    guard predictor.compatible(row), let skill = row.mapping?.skillIDs.first, let p = artifact.parameters[skill] else { throw LearnerError.unavailable }
                    let compatible = history.filter { predictor.compatible($0) && $0.mapping?.skillIDs == [skill] }
                    let payload = compatible.isEmpty ? try encoder.encode([skill: p.prior]) : try predictor.replay(compatible)
                    probability = try predictor.probability(mapping: row.mapping!, history: payload)
                case .das3h:
                    guard learner == target else { throw LearnerError.invalidEvidence }
                    let predictor = DAS3HLearnerPredictor(artifact: try decoder.decode(DAS3HLearnerPredictor.Artifact.self, from: parameters))
                    guard predictor.compatible(row) else { throw LearnerError.unavailable }
                    probability = try predictor.probability(mapping: row.mapping!, at: row.occurredAt, history: predictor.replay(history))
                case .dynamicRasch:
                    let predictor = DynamicRaschLearnerPredictor(artifact: try decoder.decode(DynamicRaschLearnerPredictor.Artifact.self, from: parameters))
                    guard predictor.compatible(row), !history.isEmpty else { throw LearnerError.unavailable }
                    probability = try predictor.probability(questionID: row.questionID, questionVersion: row.questionVersion, at: row.occurredAt, history: predictor.replay(history))
                case .dina:
                    let artifact = try decoder.decode(DINALearnerPredictor.Artifact.self, from: parameters), predictor = DINALearnerPredictor(artifact: artifact)
                    guard predictor.compatible(row) else { throw LearnerError.unavailable }
                    let payload = history.isEmpty ? try encoder.encode(artifact.profilePrior) : try predictor.replay(history)
                    probability = try predictor.probability(mapping: row.mapping!, history: payload)
                }
                guard probability.isFinite, (0...1).contains(probability) else { throw LearnerError.invalidEvidence }
                result.append((probability, row.correct!)); history.append(row)
            }
        }
        guard result.count == validation.count else { throw LearnerError.invalidEvidence }
        return result
    }
}
