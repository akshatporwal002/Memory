import Foundation

public struct MultipleChoiceQuestion: Codable, Equatable, Sendable {
    public struct Choice: Codable, Equatable, Identifiable, Sendable {
        public let id: String
        public let text: String
        public init(id: String, text: String) { self.id = id; self.text = text }
    }
    public let prompt: String
    public let choices: [Choice]
    public let correctID: String
    public let explanation: String
    /// Stable per presentation, including resumed sessions. Choice IDs retain their canonical identity.
    public func ordered(for presentationID: String) -> Self {
        var seed: UInt64 = 14695981039346656037
        for byte in presentationID.utf8 { seed = (seed ^ UInt64(byte)) &* 1099511628211 }
        var ordered = choices
        guard ordered.count > 1 else { return self }
        for index in stride(from: ordered.count - 1, through: 1, by: -1) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            ordered.swapAt(index, Int(seed % UInt64(index + 1)))
        }
        return Self(prompt: prompt, choices: ordered, correctID: correctID, explanation: explanation)
    }
    public func displayLetter(for choiceID: String) -> String {
        guard let index = choices.firstIndex(where: { $0.id == choiceID }) else { return choiceID }
        return String(UnicodeScalar(65 + index)!)
    }
    public var displayedExplanation: String {
        guard explanation.hasPrefix(correctID + ")") else { return explanation }
        return displayLetter(for: correctID) + explanation.dropFirst(correctID.count)
    }
    public func resolvePresented(_ speech: String) -> String? {
        let displayed = Self(prompt: prompt, choices: choices.enumerated().map {
            Choice(id: String(UnicodeScalar(65 + $0.offset)!), text: $0.element.text)
        }, correctID: displayLetter(for: correctID), explanation: displayedExplanation)
        guard let letter = displayed.resolve(speech), let index = displayed.choices.firstIndex(where: { $0.id == letter }) else { return nil }
        return choices[index].id
    }
    public static func parse(front: String, back: String) -> Self? {
        let front = NotebookDocument.plainText(front), back = NotebookDocument.plainText(back)
        guard let expression = try? NSRegularExpression(pattern: #"(?:^|\s|;)([A-Z])\)\s+"#) else { return nil }
        let range = NSRange(front.startIndex..., in: front)
        let matches = expression.matches(in: front, range: range)
        guard (2...8).contains(matches.count), let first = matches.first,
              let firstRange = Range(first.range, in: front) else { return nil }
        let prompt = String(front[..<firstRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        var choices: [Choice] = []
        for (index, match) in matches.enumerated() {
            guard let label = Range(match.range(at: 1), in: front), let full = Range(match.range, in: front) else { return nil }
            let end = index + 1 < matches.count ? Range(matches[index + 1].range, in: front)!.lowerBound : front.endIndex
            let text = String(front[full.upperBound..<end]).trimmingCharacters(in: CharacterSet(charactersIn: "; ").union(.whitespacesAndNewlines))
            guard !text.isEmpty else { return nil }
            choices.append(Choice(id: String(front[label]), text: text))
        }
        guard !prompt.isEmpty, choices.map(\.id) == Array(["A", "B", "C", "D", "E", "F", "G", "H"].prefix(choices.count)),
              back.count > 3, back.dropFirst().hasPrefix(") "), let correct = back.first.map(String.init),
              choices.contains(where: { $0.id == correct }) else { return nil }
        return Self(prompt: prompt, choices: choices, correctID: correct, explanation: back)
    }
    public func resolve(_ speech: String) -> String? {
        let text = Self.normalize(speech)
        let words = text.split(separator: " ").map(String.init)
        // Negation and unclear multi-choice utterances require clarification.
        guard !words.contains(where: { ["not", "never", "neither", "except"].contains($0) }) else { return nil }
        let corrected = text.components(separatedBy: "actually ").last ?? text
        let aliases = ["a": "A", "ay": "A", "alpha": "A", "b": "B", "bee": "B", "bravo": "B", "c": "C", "see": "C", "charlie": "C", "d": "D", "dee": "D", "delta": "D", "e": "E", "echo": "E", "f": "F", "foxtrot": "F", "g": "G", "gee": "G", "golf": "G", "h": "H", "aitch": "H", "hotel": "H"]
        let selection = corrected.replacingOccurrences(of: "option ", with: "").replacingOccurrences(of: "answer ", with: "").replacingOccurrences(of: "choice ", with: "")
        if let letter = aliases[selection], choices.contains(where: { $0.id == letter }) { return letter }
        let exact = choices.filter { Self.normalize($0.text) == corrected }
        if exact.count == 1 { return exact[0].id }
        let excluded: Set<String> = ["a", "an", "the", "is", "it", "i", "think", "amazon", "aws", "service", "for", "of", "and", "to", "with"]
        let query = Set(corrected.split(separator: " ").map(String.init)).subtracting(excluded)
        guard !query.isEmpty else { return nil }
        let scored = choices.map { choice -> (String, Double) in
            let tokens = Set(Self.normalize(choice.text).split(separator: " ").map(String.init)).subtracting(excluded)
            let overlap = query.intersection(tokens).count
            let score = Double(overlap) / Double(max(query.count, tokens.count))
            return (choice.id, score)
        }.sorted { $0.1 > $1.1 }
        guard scored[0].1 >= 0.6, scored[0].1 - scored[1].1 >= 0.3 else { return nil }
        return scored[0].0
    }
    private static func normalize(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .split(separator: " ").joined(separator: " ")
    }
}

public struct AnswerAssessment: Codable, Equatable, Sendable {
    public enum Outcome: String, Codable, Sendable { case correct, partial, incorrect, unclear }
    public var outcome: Outcome
    public var reason: String
    public var choiceID: String?
    public var method: String
    public var evidenceIDs: [String]?
    public var annotations: [AnswerAnnotation]?
    public var additions: [AnswerAddition]?
    public var proposedAnswer: String?
    public init(outcome: Outcome, reason: String, choiceID: String? = nil, method: String) {
        self.outcome = outcome; self.reason = reason; self.choiceID = choiceID; self.method = method
    }
    public var rating: Grade? { switch outcome { case .correct: .good; case .partial: .hard; case .incorrect: .again; case .unclear: nil } }
}
