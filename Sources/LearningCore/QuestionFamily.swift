import Foundation

public enum QuestionApproach: String, Codable, CaseIterable, Sendable {
    case explain, compare, apply, evaluate
}
/// Intended same-level practice, not empirically calibrated difficulty or mastery evidence.
public struct QuestionVariant: Codable, Equatable, Identifiable, Sendable {
    public var revision: Int?
    public var validation: VariantValidation?
    public var id: String
    public var approach: QuestionApproach
    public var front: String
    public var back: String
    public var objective: String
    public var rubric: String
    public var evidence: [AttemptEvidence]
    public init(id: String = UUID().uuidString, approach: QuestionApproach, front: String, back: String,
                objective: String, rubric: String, evidence: [AttemptEvidence]) {
        self.id = id; self.approach = approach; self.front = front; self.back = back
        self.objective = objective; self.rubric = rubric; self.evidence = evidence
    }
    public func validate() throws {
        guard !id.isEmpty, id.utf8.count <= 200, revision.map({ $0 > 0 }) ?? true,
              [front, back, objective, rubric].allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 20000 }),
              !evidence.isEmpty, evidence.count <= 8, Set(evidence.map(\.id)).count == evidence.count,
              evidence.allSatisfy({ !$0.id.isEmpty && !$0.version.isEmpty && !$0.text.isEmpty && $0.text.utf8.count <= 6000 }) else {
            throw EngramError.invalid("Variants need a question, answer, objective, rubric and current source evidence.")
        }
    }
}
public struct QuestionFamily: Codable, Equatable, Sendable {
    public var originalFront: String
    public var originalBack: String
    public var variants: [QuestionVariant]
    public var reviewedAt: Date
    /// Browsing shows the answer: exposure is separate from scored attempts and FSRS.
    public var exposedVariantIDs: [String: Date] = [:]
    public init(originalFront: String, originalBack: String, variants: [QuestionVariant], reviewedAt: Date) {
        self.originalFront = originalFront; self.originalBack = originalBack; self.variants = variants; self.reviewedAt = reviewedAt
    }
    public func available(in library: LibrarySnapshot, note: Note) -> [QuestionVariant] {
        guard originalFront == note.front, originalBack == note.back else { return [] }
        return variants.filter { variant in
            (try? variant.validate()) != nil && variant.evidence.allSatisfy { EvidenceRetrieval.isCurrent($0, in: library) }
        }
    }
}
