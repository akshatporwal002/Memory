import Foundation

/// Only explicit whole-utterance commands may mutate review scheduling.
public enum VoiceReviewCommand: Equatable, Sendable {
    case stop, repeatCard, grade(Grade), answer
    public static func parse(_ text: String) -> Self {
        let value = text.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        if ["stop", "pause", "stop voice", "pause voice"].contains(value) { return .stop }
        if ["repeat", "repeat question", "repeat answer"].contains(value) { return .repeatCard }
        let grades: [String: Grade] = ["grade again": .again, "grade hard": .hard, "grade good": .good, "grade easy": .easy]
        return grades[value].map(Self.grade) ?? .answer
    }
}
