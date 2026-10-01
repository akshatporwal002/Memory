import Foundation

public struct PDFPageText: Codable, Equatable, Sendable, Identifiable {
    public var number: Int
    public var text: String
    public var id: Int { number }
    public init(number: Int, text: String) { self.number = number; self.text = text }
}
public struct PDFLearningSource: Codable, Equatable, Sendable {
    public var id: String
    public var filename: String
    public var pages: [PDFPageText]
    public var warnings: [String]
    public init(id: String = UUID().uuidString, filename: String, pages: [PDFPageText], warnings: [String] = []) {
        self.id = id; self.filename = filename; self.pages = pages; self.warnings = warnings
    }
    public func validate() throws {
        guard !filename.isEmpty, (1...300).contains(pages.count),
              Set(pages.map(\.number)).count == pages.count,
              pages.allSatisfy({ $0.number > 0 }),
              pages.reduce(0, { $0 + $1.text.utf8.count }) <= 2_000_000,
              pages.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw EngramError.invalid("Use a readable PDF of up to 300 pages and 2 MB of extracted text.")
        }
    }
    public var chunks: [PDFPassage] {
        pages.flatMap { page in
            let words = page.text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            return stride(from: 0, to: words.count, by: 200).enumerated().map { index, start in
                PDFPassage(id: "p\(page.number)-\(index)", page: page.number,
                           text: words[start..<min(start + 260, words.count)].joined(separator: " "))
            }
        }
    }
}
public struct PDFPassage: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var page: Int
    public var text: String
}
public struct PDFLearningBrief: Codable, Equatable, Sendable {
    public var goal = ""
    public var topics = ""
    public var exclusions = ""
    public var difficulty = "Intermediate"
    public var format = "Mixed"
    public var output = "Questions and notes"
    public var noteDepth = "Condensed"
    public var questionCount = 12
    public var firstPage = 1
    public var lastPage = 1
    public init() {}
    public func validate(source: PDFLearningSource) throws {
        try source.validate()
        guard firstPage >= 1, lastPage >= firstPage,
              lastPage <= (source.pages.map(\.number).max() ?? 0),
              (3...40).contains(questionCount),
              ["Beginner", "Intermediate", "Advanced"].contains(difficulty),
              ["Mixed", "Multiple choice", "Short answer"].contains(format),
              ["Questions and notes", "Questions only", "Notes only"].contains(output),
              ["Condensed", "Detailed"].contains(noteDepth),
              [goal, topics, exclusions].allSatisfy({ $0.count <= 2000 }) else {
            throw EngramError.invalid("Check the page range and learning preferences. Choose 3–40 questions.")
        }
    }
}
public struct PDFCitation: Codable, Equatable, Sendable {
    public var passageID: String
    public var quote: String
    public init(passageID: String, quote: String) { self.passageID = passageID; self.quote = quote }
}
public struct PDFLearningItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var kind: String
    public var topic: String
    public var prompt: String
    public var answer: String
    public var options: [String]
    public var correctIndex: Int
    public var citations: [PDFCitation]
    public var verified: Bool?
    public var userEdited: Bool?
    public init(id: String = UUID().uuidString, kind: String, topic: String, prompt: String,
                answer: String, options: [String] = [], correctIndex: Int = -1, citations: [PDFCitation], verified: Bool? = nil) {
        self.id = id; self.kind = kind; self.topic = topic; self.prompt = prompt; self.answer = answer
        self.options = options; self.correctIndex = correctIndex; self.citations = citations; self.verified = verified
    }
    public var front: String {
        kind == "mcq" ? prompt + " " + options.enumerated().map { "\(String(UnicodeScalar(65 + $0.offset)!))) \($0.element)" }.joined(separator: "; ") : prompt
    }
    public var back: String {
        kind == "mcq" && options.indices.contains(correctIndex) ? "\(String(UnicodeScalar(65 + correctIndex)!))) \(options[correctIndex]). \(answer)" : answer
    }
    public var fingerprint: String { PDFRetrieval.normalize(prompt) }
}
public struct PDFLearningRecord: Codable, Equatable, Sendable {
    public var source: PDFLearningSource
    public var brief: PDFLearningBrief
    public var items: [PDFLearningItem]
    public init(source: PDFLearningSource, brief: PDFLearningBrief, items: [PDFLearningItem]) {
        self.source = source; self.brief = brief; self.items = items
    }
}
public enum PDFRetrieval {
    public static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }
    /// TF/IDF-style lexical ranking with deterministic page diversification. No cloud embeddings.
    public static func retrieve(source: PDFLearningSource, brief: PDFLearningBrief, query: String, limit: Int = 8) -> [PDFPassage] {
        let passages = source.chunks.filter { (brief.firstPage...brief.lastPage).contains($0.page) }
        let terms = Set(normalize(query).split(separator: " ").map(String.init))
        let tokens = passages.map { Set(normalize($0.text).split(separator: " ").map(String.init)) }
        var frequency: [String: Int] = [:]
        for set in tokens { for term in set { frequency[term, default: 0] += 1 } }
        var scored: [(PDFPassage, Double, Int)] = []
        for (index, passage) in passages.enumerated() {
            var score: Double = 0
            for term in terms.intersection(tokens[index]) {
                let occurrences = Double(frequency[term] ?? 1)
                score += log(1.0 + Double(passages.count) / occurrences)
            }
            scored.append((passage, score, index))
        }
        scored.sort { left, right in
            if left.1 == right.1 { return left.2 < right.2 }
            return left.1 > right.1
        }
        if terms.isEmpty || scored.first?.1 == 0 {
            guard !passages.isEmpty else { return [] }
            let count = min(limit, passages.count)
            return (0..<count).map { passages[min(passages.count - 1, $0 * passages.count / count)] }
        }
        var result: [PDFPassage] = []
        // Prefer evidence from multiple pages before adding more of the same page.
        for entry in scored where entry.1 > 0 && !result.contains(where: { $0.page == entry.0.page }) {
            result.append(entry.0); if result.count == limit { return result }
        }
        for entry in scored where entry.1 > 0 && !result.contains(where: { $0.id == entry.0.id }) {
            result.append(entry.0); if result.count == limit { break }
        }
        return result
    }
    public static func validate(_ items: [PDFLearningItem], against passages: [PDFPassage]) throws {
        guard items.count <= 200, items.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 100 }), Set(items.map(\.id)).count == items.count else { throw EngramError.invalid("Generation returned invalid item identities.") }
        let byID = Dictionary(uniqueKeysWithValues: passages.map { ($0.id, $0) })
        for item in items {
            guard ["mcq", "short", "note"].contains(item.kind), !item.prompt.isEmpty, !item.answer.isEmpty,
                  item.prompt.count <= 3000, item.answer.count <= 8000, item.topic.count <= 200,
                  !item.citations.isEmpty, item.citations.count <= 6 else { throw EngramError.invalid("Generated content is incomplete or has no sources.") }
            for citation in item.citations {
                guard let passage = byID[citation.passageID], citation.quote.count >= 12,
                      citation.quote.count <= 2000,
                      passage.text.contains(citation.quote) else { throw EngramError.invalid("A generated citation does not match the PDF. Regenerate this batch.") }
            }
            if item.kind == "mcq" {
                guard (2...6).contains(item.options.count), item.options.indices.contains(item.correctIndex),
                      item.options.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 1500 }),
                      Set(item.options.map(normalize)).count == item.options.count,
                      !item.options.contains(where: { normalize($0).contains("all of the above") || normalize($0).contains("none of the above") }) else {
                    throw EngramError.invalid("Multiple-choice options are invalid or cannot be safely shuffled.")
                }
                guard MultipleChoiceQuestion.parse(front: item.front, back: item.back) != nil else {
                    throw EngramError.invalid("The generated question cannot be safely read as multiple choice.")
                }
            } else if !item.options.isEmpty || item.correctIndex != -1 { throw EngramError.invalid("Unexpected options in generated notes or short answers.") }
        }
    }
}
