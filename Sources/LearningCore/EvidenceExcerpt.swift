import Foundation

public enum EvidenceExcerpt {
    /// Display verbatim sentences/lines; never paraphrase a citation or expose a
    /// whole notebook chunk. Selection affects display only, not grading evidence.
    public static func relevantText(_ source: String, question: String, claim: String) -> String {
        let terms = Set((question + " " + claim).lowercased().split { !$0.isLetter && !$0.isNumber }.filter { $0.count > 3 }.map(String.init))
        let paragraphs = source.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("http") && !$0.hasPrefix("Reference:") && !$0.hasPrefix("#") }
        let expression = try? NSRegularExpression(pattern: #"[^.!?]+(?:[.!?]+|$)"#)
        var lines: [String] = []
        for paragraph in paragraphs {
            let ranges = expression?.matches(in: paragraph, range: NSRange(paragraph.startIndex..., in: paragraph)) ?? []
            for match in ranges {
                if let range = Range(match.range, in: paragraph) { lines.append(String(paragraph[range]).trimmingCharacters(in: .whitespaces)) }
            }
        }
        var ranked: [(Int, String, Int)] = []
        for (index, line) in lines.enumerated() {
            let words = line.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
            let score = Set(words).intersection(terms).count
            if score > 0 { ranked.append((index, line, score)) }
        }
        ranked.sort { $0.2 == $1.2 ? $0.0 < $1.0 : $0.2 > $1.2 }
        let scored = ranked.prefix(3).sorted { $0.0 < $1.0 }
        let selected = scored.isEmpty ? Array(lines.prefix(1)) : scored.map { $0.1 }
        return selected.map { $0.count > 1200 ? String($0.prefix(1200)) + "… [excerpt shortened]" : $0 }.joined(separator: "\n\n")
    }
}
