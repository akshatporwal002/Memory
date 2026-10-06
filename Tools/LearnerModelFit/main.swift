import Foundation
import LearningCore

/// Local-only JSON fitting entry point. This creates a candidate, never an active model.
@main struct LearnerModelFit {
    struct Request: Codable {
        let permittedData: Bool
        let model: LearnerModelID
        let account: UUID
        let library: String
        let targetLearner: String
        let evidenceRevision: Int
        let options: LearnerFitOptions?
        let training: [LearnerTrainingRow]
        let validation: [LearnerTrainingRow]
    }
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw NSError(domain: "LearnerFit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Usage: EngramLearnerFit input.json output.json"])
        }
        let input = URL(fileURLWithPath: CommandLine.arguments[1]), output = URL(fileURLWithPath: CommandLine.arguments[2])
        guard !FileManager.default.fileExists(atPath: output.path) else { throw LearnerError.conflict }
        let bytes = try Data(contentsOf: input)
        guard bytes.count <= 20000000 else { throw LearnerError.invalidEvidence }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let request = try decoder.decode(Request.self, from: bytes)
        guard request.permittedData else { throw LearnerError.unavailable }
        let candidate = try LearnerCalibration.fit(model: request.model, training: request.training, validation: request.validation,
            targetLearner: request.targetLearner, account: request.account, library: request.library, evidenceRevision: request.evidenceRevision,
            options: request.options ?? LearnerFitOptions())
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(candidate).write(to: output, options: .atomic)
        print("Fitted candidate: \(candidate.report.model.rawValue); held-out attempts: \(candidate.report.validationAttempts); eligible for review: \(candidate.report.eligibleForReview)")
        print("No model was activated. This report does not establish learning superiority.")
    }
}
