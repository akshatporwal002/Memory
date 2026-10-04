import Foundation

public enum MathInputMode: String, Codable, CaseIterable, Sendable {
    case off, basic, advanced
    public var title: String { rawValue.capitalized }
}
public extension Note {
    /// Explicit tags keep domain separate from question format, e.g. maths MCQ.
    var declaredSubject: String? {
        if let tag = tags.sorted().first(where: { $0.hasPrefix("subject:") && $0.count > 8 }) { return String(tag.dropFirst(8)) }
        if tags.contains(where: { ["math", "maths", "equation"].contains($0.lowercased()) }) || canonicalQuestionType == "equation" { return "maths" }
        return nil
    }
    var declaredQuestionSubtype: String? {
        tags.sorted().first(where: { $0.hasPrefix("subtype:") && $0.count > 8 }).map { String($0.dropFirst(8)) }
    }
    var canonicalQuestionType: String {
        if let questionType { return questionType }
        if mcq != nil { return "mcq" }
        if kind == .cloze { return "cloze" }
        if tags.contains(where: { ["math", "maths", "equation"].contains($0.lowercased()) }) { return "equation" }
        return "short-answer"
    }
    var acceptsMathInput: Bool {
        ["equation", "numeric", "number-with-units"].contains(canonicalQuestionType)
    }
}
