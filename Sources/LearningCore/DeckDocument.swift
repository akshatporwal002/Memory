import Foundation

/// A local, resumable creation draft. Its ID also makes creation retries idempotent.
public struct DeckCreationDraft: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var subject: String
    public var document: String
    public init(id: String = UUID().uuidString, title: String = "", subject: String = "", document: String = "") {
        self.id = id; self.title = title; self.subject = subject; self.document = document
    }
    public var isEmpty: Bool { title.isEmpty && subject.isEmpty && document.isEmpty }
    public var deckName: String {
        [subject, title].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: "::")
    }
}

public struct DeckDocument: Equatable, Sendable {
    public struct Question: Equatable, Sendable {
        public let line: Int
        public let front: String
        public let back: String
    }
    public struct Issue: Equatable, Sendable, Identifiable {
        public let line: Int
        public let message: String
        public var id: Int { line }
    }
    public let questions: [Question]
    public let issues: [Issue]
    public static let byteLimit = 1_024 * 1_024

    /// One Q&A per line. Colon-space is the preferred separator; legacy arrows remain supported.
    /// Card fields are escaped because this editor accepts plain text, not HTML.
    public static func parse(_ source: String, allowsColon: Bool = true) -> DeckDocument {
        guard source.utf8.count <= byteLimit else {
            return Self(questions: [], issues: [Issue(line: 0, message: "Keep a deck document under 1 MB.")])
        }
        var questions: [Question] = []
        var issues: [Issue] = []
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for (offset, raw) in normalized.components(separatedBy: "\n").enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let heading = line.hasPrefix("#") && line.drop(while: { $0 == "#" }).first?.isWhitespace == true
            guard !heading, !line.hasPrefix("\\") else { continue }
            let arrows = [line.range(of: "->"), line.range(of: "→")].compactMap { $0 }
            let colon = allowsColon ? line.indices.first(where: { index in
                guard line[index] == ":" else { return false }
                let next = line.index(after: index)
                let previousIsColon = index > line.startIndex && line[line.index(before: index)] == ":"
                return !previousIsColon && (next == line.endIndex || line[next].isWhitespace)
            }).map { $0..<line.index(after: $0) } : nil
            // Arrows take precedence to preserve legacy questions that already contain colons.
            guard let arrow = arrows.min(by: { $0.lowerBound < $1.lowerBound }) ?? colon else { continue }
            let front = String(line[..<arrow.lowerBound]).trimmingCharacters(in: .whitespaces)
            let back = String(line[arrow.upperBound...]).trimmingCharacters(in: .whitespaces)
            if front.isEmpty || back.isEmpty {
                issues.append(Issue(line: offset + 1, message: "Add both a question and an answer."))
            } else {
                questions.append(Question(line: offset + 1, front: front, back: back))
            }
        }
        if questions.count > 1_000 { issues.append(Issue(line: 0, message: "Create up to 1,000 questions at a time.")) }
        return Self(questions: questions, issues: issues)
    }

    public static func cardText(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
