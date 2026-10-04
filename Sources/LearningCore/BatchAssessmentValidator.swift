import Foundation

public enum BatchAssessmentValidator {
    public static func decode(_ text: String, attempts: [AnswerAttempt]) throws -> [String: AnswerAssessment] {
        guard let data = text.data(using: .utf8), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = object["results"] as? [[String: Any]], results.count <= attempts.count else { throw EngramError.invalid("The marking response was incomplete or invalid.") }
        guard Set(attempts.map(\.id)).count == attempts.count else { throw EngramError.invalid("Duplicate submitted answers.") }
        let known = Dictionary(uniqueKeysWithValues: attempts.map { ($0.id, $0) })
        var decoded: [String: AnswerAssessment] = [:]
        var seen: Set<String> = []
        for result in results {
            guard let id = result["attempt_id"] as? String, let attempt = known[id], seen.insert(id).inserted else {
                throw EngramError.invalid("The marking response contains an unknown or repeated answer.")
            }
            // A malformed item never displaces another answer's result.
            let encoded = try JSONSerialization.data(withJSONObject: result)
            if let assessment = try? LocalAnswerEvidence.validate(String(decoding: encoded, as: UTF8.self), allowedIDs: Set(attempt.evidence.map(\.id))) {
                decoded[id] = assessment
            }
        }
        return decoded
    }
}
