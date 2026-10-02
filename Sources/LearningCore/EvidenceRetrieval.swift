import Foundation

public struct RetrievedEvidence: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var deckID: String
    public var title: String
    public var text: String
    public var version: String
    public var noteID: String?
    public var blockID: String?
    public var page: Int?
}
/// One bounded retrieval entry point. Access filtering belongs to the repository's account projection.
public enum EvidenceRetrieval {
    public static func retrieve(query: String, deckID: String, library: LibrarySnapshot, preferredNoteID: String? = nil, limit: Int = 6) -> [RetrievedEvidence] {
        guard let deck = library.liveDecks.first(where: { $0.id == deckID }) else { return [] }
        let bounded = max(0,min(12,limit))
        let terms = tokens(query)
        var candidates = library.liveNotes.filter { $0.deckID == deckID }.map { note in
            RetrievedEvidence(id:note.id,deckID:deckID,title:String(note.front.prefix(72)),text:String((note.front + "\n" + note.back + "\n" + note.source).prefix(2400)),version:note.modifiedAt.ISO8601Format(),noteID:note.id)
        }
        candidates += NotebookDocument.blocks(for:deck,in:library).filter { $0.kind == .text }.map { block in
            RetrievedEvidence(id:"passage-" + block.id,deckID:deckID,title:String(block.text.split(separator:"\n").first?.prefix(72) ?? "Notebook section"),text:String(block.text.prefix(2400)),version:deck.modifiedAt?.ISO8601Format() ?? "legacy",blockID:block.id)
        }
        if let pdf = deck.pdfLearning {
            candidates += retrieve(source:pdf.source,brief:pdf.brief,query:query,deckID:deckID,limit:bounded)
        }
        return Array(candidates.enumerated().sorted { a,b in
            let ascore = terms.intersection(tokens(a.element.text)).count + (a.element.noteID == preferredNoteID ? 10000 : 0)
            let bscore = terms.intersection(tokens(b.element.text)).count + (b.element.noteID == preferredNoteID ? 10000 : 0)
            return ascore == bscore ? a.offset < b.offset : ascore > bscore
        }.prefix(bounded).map(\.element))
    }
    public static func retrieve(source: PDFLearningSource,brief: PDFLearningBrief,query: String,deckID: String = "pdf-draft",limit: Int = 8) -> [RetrievedEvidence] {
        PDFRetrieval.retrieve(source:source,brief:brief,query:query,limit:max(0,min(12,limit))).map {
            RetrievedEvidence(id:$0.id,deckID:deckID,title:source.filename + " · page " + String($0.page),text:$0.text,version:source.id,noteID:nil,page:$0.page)
        }
    }
    private static func tokens(_ text: String) -> Set<String> { Set(PDFRetrieval.normalize(text).split(separator:" ").map(String.init).filter { $0.count > 3 }) }
}
