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
    public var documentID: String? = nil
}
/// One bounded retrieval entry point. Access filtering belongs to the repository's account projection.
public enum EvidenceRetrieval {
    public static func retrieveLibrary(query: String,library: LibrarySnapshot,limit: Int = 8) -> [RetrievedEvidence] {
        let terms = tokens(query), bounded = max(0,min(12,limit))
        guard !terms.isEmpty,bounded > 0 else { return [] }
        // Rank deck context before retrieving passages, keeping library-wide work bounded.
        let ranked = library.liveDecks.enumerated().sorted { a,b in
            func score(_ deck: Deck) -> Int {
                terms.intersection(tokens(deck.name)).count * 4 +
                (deck.documents ?? []).reduce(0) { $0 + terms.intersection(tokens($1.name + " " + $1.pages.prefix(3).map(\.text).joined(separator:" "))).count } +
                library.liveNotes.filter { $0.deckID == deck.id }.reduce(0) { $0 + terms.intersection(tokens($1.front + " " + $1.back)).count }
            }
            let lhs = score(a.element),rhs = score(b.element)
            return lhs == rhs ? a.offset < b.offset : lhs > rhs
        }.prefix(6)
        let candidates = ranked.flatMap { retrieve(query:query,deckID:$0.element.id,library:library,limit:bounded) }
        return Array(candidates.enumerated().sorted { a,b in
            let lhs = terms.intersection(tokens(a.element.text)).count,rhs = terms.intersection(tokens(b.element.text)).count
            return lhs == rhs ? a.offset < b.offset : lhs > rhs
        }.prefix(bounded).map(\.element))
    }
    public static func retrieve(query: String, deckID: String, library: LibrarySnapshot, preferredNoteID: String? = nil, limit: Int = 6) -> [RetrievedEvidence] {
        guard let deck = library.liveDecks.first(where: { $0.id == deckID }) else { return [] }
        let bounded = max(0,min(12,limit))
        let terms = tokens(query)
        var candidates = library.liveNotes.filter { $0.deckID == deckID }.map { note in
            RetrievedEvidence(id:note.id,deckID:deckID,title:String(note.front.prefix(72)),text:String((note.front + "\n" + note.back + "\n" + note.source).prefix(2400)),version:String(note.modifiedAt.timeIntervalSince1970),noteID:note.id)
        }
        candidates += NotebookDocument.blocks(for:deck,in:library).filter { $0.kind == .text && !$0.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }.map { block in
            RetrievedEvidence(id:"passage-" + block.id,deckID:deckID,title:String(block.text.split(separator:"\n").first?.prefix(72) ?? "Notebook section"),text:String(block.text.prefix(2400)),version:deck.modifiedAt.map { String($0.timeIntervalSince1970) } ?? "legacy",blockID:block.id)
        }
        if let pdf = deck.pdfLearning {
            candidates += retrieve(source:pdf.source,brief:pdf.brief,query:query,deckID:deckID,limit:bounded)
        }
        for document in deck.documents ?? [] {
            let source = PDFLearningSource(id:document.id,filename:document.name,pages:document.pages)
            var brief = PDFLearningBrief()
            brief.lastPage = document.pages.map(\.number).max() ?? 1
            candidates += retrieve(source:source,brief:brief,query:query,deckID:deckID,limit:bounded).map { item in
                var result = item
                result.id = document.id + ":" + item.id
                result.documentID = document.id
                return result
            }
        }
        return Array(candidates.enumerated().sorted { a,b in
            let ascore = terms.intersection(tokens(a.element.text)).count + (preferredNoteID != nil && a.element.noteID == preferredNoteID ? 10000 : 0)
            let bscore = terms.intersection(tokens(b.element.text)).count + (preferredNoteID != nil && b.element.noteID == preferredNoteID ? 10000 : 0)
            return ascore == bscore ? a.offset < b.offset : ascore > bscore
        }.prefix(bounded).map(\.element))
    }
    public static func isCurrent(_ evidence: AttemptEvidence,in library: LibrarySnapshot) -> Bool {
        if let note = library.liveNotes.first(where: { $0.id == evidence.id }) {
            return evidence.version == String(note.modifiedAt.timeIntervalSince1970)
        }
        for deck in library.liveDecks {
            if NotebookDocument.blocks(for:deck,in:library).contains(where: { "passage-" + $0.id == evidence.id }) {
                return evidence.version == (deck.modifiedAt.map { String($0.timeIntervalSince1970) } ?? "legacy")
            }
            if let source = deck.pdfLearning?.source,source.chunks.contains(where: { $0.id == evidence.id }) { return evidence.version == source.id }
            if let documents = deck.documents {
                for document in documents where evidence.id.hasPrefix(document.id + ":") {
                    return evidence.version == document.id
                }
            }
        }
        return false
    }
    public static func retrieve(source: PDFLearningSource,brief: PDFLearningBrief,query: String,deckID: String = "pdf-draft",limit: Int = 8) -> [RetrievedEvidence] {
        PDFRetrieval.retrieve(source:source,brief:brief,query:query,limit:max(0,min(12,limit))).map {
            RetrievedEvidence(id:$0.id,deckID:deckID,title:source.filename + " · page " + String($0.page),text:$0.text,version:source.id,noteID:nil,page:$0.page)
        }
    }
    private static func tokens(_ text: String) -> Set<String> { Set(PDFRetrieval.normalize(text).split(separator:" ").map(String.init).filter { $0.count > 3 }) }
}
