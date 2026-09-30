import Foundation

/// Stable block identities make edits and reordering independent of card scheduling.
public struct NotebookBlock: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable { case text, question }
    public var id: String
    public var kind: Kind
    public var text: String
    public var answer: String
    public var noteID: String?
    public init(id: String = UUID().uuidString, kind: Kind = .text, text: String = "", answer: String = "", noteID: String? = nil) {
        self.id = id; self.kind = kind; self.text = text; self.answer = answer; self.noteID = noteID
    }
}

public enum NotebookDocument {
    public static func plainText(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
    public static func supports(_ note: Note) -> Bool {
        note.kind == .basic && SafeCardMarkup.inspect(note.front).mediaNames.isEmpty && SafeCardMarkup.inspect(note.back).mediaNames.isEmpty && DeckDocument.cardText(plainText(note.front)) == note.front &&
            DeckDocument.cardText(plainText(note.back)) == note.back
    }
    public static func source(_ blocks: [NotebookBlock]) -> String {
        blocks.map { $0.kind == .text ? $0.text : "\($0.text) → \($0.answer)" }.joined(separator: "\n\n")
    }
    /// Explicit conversion preserves prose and does not reinterpret ordinary writing while typing.
    public static func expandWriting(_ source: String) throws -> [NotebookBlock] {
        let parsed = DeckDocument.parse(source)
        if let issue = parsed.issues.first { throw EngramError.invalid("Line \(issue.line): \(issue.message)") }
        let byLine = Dictionary(uniqueKeysWithValues: parsed.questions.map { ($0.line, $0) })
        var result: [NotebookBlock] = []
        var prose: [String] = []
        func flush() {
            if !prose.isEmpty { result.append(NotebookBlock(text: prose.joined(separator: "\n"))); prose = [] }
        }
        for (offset, line) in source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n").enumerated() {
            if let question = byLine[offset + 1] {
                flush(); result.append(NotebookBlock(kind: .question, text: question.front, answer: question.back))
            } else { prose.append(line) }
        }
        flush()
        return result
    }
    /// Old documents used deterministic note IDs; resolve those, never match by wording.
    /// Current note content always wins over the original creation copy.
    public static func blocks(for deck: Deck, in library: LibrarySnapshot) -> [NotebookBlock] {
        let notes = library.liveNotes.filter { $0.deckID == deck.id }
        let byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        var blocks: [NotebookBlock]
        if let saved = deck.notebookBlocks { blocks = saved }
        else {
            let source = deck.sourceDocument ?? ""
            let questions = DeckDocument.parse(source, allowsColon: deck.documentFormatVersion == 2).questions
            let byLine = Dictionary(uniqueKeysWithValues: questions.enumerated().map { ($0.element.line, $0.offset) })
            var prose: [String] = []
            blocks = []
            func flush() {
                if !prose.isEmpty {
                    blocks.append(NotebookBlock(id: "\(deck.id)-text-\(blocks.count)", text: prose.joined(separator: "\n")))
                    prose = []
                }
            }
            for (offset, line) in source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n").enumerated() {
                if let ordinal = byLine[offset + 1] {
                    flush()
                    let id = "\(deck.id)-note-\(ordinal)"
                    // Deleted/moved cards must not be resurrected from old source text.
                    if let note = byID[id], supports(note) {
                        blocks.append(NotebookBlock(id: id, kind: .question, text: plainText(note.front), answer: plainText(note.back), noteID: id))
                    }
                } else { prose.append(line) }
            }
            flush()
        }
        blocks = blocks.compactMap { block in
            guard block.kind == .question, let id = block.noteID else { return block }
            guard let note = byID[id], supports(note) else { return nil }
            var current = block
            current.text = plainText(note.front); current.answer = plainText(note.back)
            return current
        }
        let linked = Set(blocks.compactMap(\.noteID))
        for note in notes where supports(note) && !linked.contains(note.id) {
            blocks.append(NotebookBlock(id: note.id, kind: .question, text: plainText(note.front), answer: plainText(note.back), noteID: note.id))
        }
        return blocks
    }
}
