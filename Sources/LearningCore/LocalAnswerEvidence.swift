import Foundation

public enum LocalAnswerEvidence {
    public struct Passage: Sendable { public let id: String; public let text: String; public let version: String }
    public static func retrieve(note: Note, prompt: String, library: LibrarySnapshot) -> [Passage] {
        EvidenceRetrieval.retrieve(query:prompt,deckID:note.deckID,library:library,preferredNoteID:note.id).map {
            Passage(id:$0.id,text:$0.text,version:$0.version)
        }
    }
    public static func validate(_ output: String, allowedIDs: Set<String>) throws -> AnswerAssessment {
        struct Result: Decodable {
            let outcome: AnswerAssessment.Outcome; let reason: String; let evidence_ids: [String]
            let annotations: [AnswerAnnotation]?; let additions: [AnswerAddition]?; let proposedAnswer: String?
        }
        guard let data = output.data(using: .utf8), let result = try? JSONDecoder().decode(Result.self, from: data),
              !result.reason.isEmpty, result.reason.count <= 1500,
              result.evidence_ids.allSatisfy({ allowedIDs.contains($0) }),
              result.outcome == .unclear || !result.evidence_ids.isEmpty else { throw EngramError.invalid("AI feedback was not supported by the supplied evidence. No grade was saved.") }
        var assessment = AnswerAssessment(outcome: result.outcome, reason: result.reason, method: "ai")
        assessment.evidenceIDs = result.evidence_ids
        assessment.annotations = result.annotations
        assessment.additions = result.additions?.filter { !$0.text.isEmpty && $0.text.count <= 3000 && !$0.evidenceIDs.isEmpty && Set($0.evidenceIDs).isSubset(of:allowedIDs) }
        assessment.proposedAnswer = result.proposedAnswer.flatMap { $0.count <= 10_000 ? $0 : nil }
        return assessment
    }
}
