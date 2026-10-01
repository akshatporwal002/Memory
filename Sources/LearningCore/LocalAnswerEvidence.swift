import Foundation

public enum LocalAnswerEvidence {
    public struct Passage: Sendable { public let id: String; public let text: String }
    public static func retrieve(note: Note, prompt: String, library: LibrarySnapshot) -> [Passage] {
        let query = Set(prompt.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 3 })
        let related = library.liveNotes.filter { $0.deckID == note.deckID && $0.id != note.id }.map { candidate in
            (candidate, query.intersection(Set((candidate.front + " " + candidate.back).lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))).count)
        }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(3).map(\.0)
        var result = ([note] + related).map { Passage(id: $0.id, text: String(($0.front + "\n" + $0.back + "\n" + $0.source).prefix(2000))) }
        if let deck = library.liveDecks.first(where: { $0.id == note.deckID }) {
            let prose = NotebookDocument.blocks(for: deck, in: library).filter { $0.kind == .text }.map { block in
                (block, query.intersection(Set(block.text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))).count)
            }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(2)
            result += prose.map { Passage(id: "passage-" + $0.0.id, text: String($0.0.text.prefix(2000))) }
        }
        return result
    }
    public static func validate(_ output: String, allowedIDs: Set<String>) throws -> AnswerAssessment {
        struct Result: Decodable { let outcome: AnswerAssessment.Outcome; let reason: String; let evidence_ids: [String] }
        guard let data = output.data(using: .utf8), let result = try? JSONDecoder().decode(Result.self, from: data),
              !result.reason.isEmpty, result.reason.count <= 1500,
              result.evidence_ids.allSatisfy({ allowedIDs.contains($0) }),
              result.outcome == .unclear || !result.evidence_ids.isEmpty else { throw EngramError.invalid("AI feedback was not supported by the supplied evidence. No grade was saved.") }
        var assessment = AnswerAssessment(outcome: result.outcome, reason: result.reason, method: "ai")
        assessment.evidenceIDs = result.evidence_ids
        return assessment
    }
}
