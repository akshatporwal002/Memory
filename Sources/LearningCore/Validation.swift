import Foundation

public enum LibraryValidation {
    public static func validate(_ library: LibrarySnapshot) throws {
        guard library.schemaVersion == 1 else { throw EngramError.unsupported("Library schema \(library.schemaVersion) needs a newer Engram. Your file was not changed.") }
        guard library.notes.count <= 250_000, library.cards.count <= 500_000 else { throw EngramError.invalid("This library exceeds the current 250,000 note / 500,000 card limit.") }
        try unique(library.decks.map(\.id), "deck")
        try unique(library.notes.map(\.id), "note")
        try unique(library.cards.map(\.id), "card")
        try unique(library.reviews.map(\.id), "review")
        try unique(library.importedReviews.map(\.id), "imported review")
        try unique(library.corrections.map(\.id), "correction")
        try unique(library.corrections.map(\.reviewID), "undone review")
        try unique(library.media.map(\.name), "media filename")
        let decks = Set(library.decks.map(\.id)), notes = Set(library.notes.map(\.id)), cards = Set(library.cards.map(\.id))
        let reviews = Set(library.reviews.map(\.id))
        guard library.notes.allSatisfy({ decks.contains($0.deckID) }),
              library.cards.allSatisfy({ notes.contains($0.noteID) && decks.contains($0.deckID) && $0.schedule.due.timeIntervalSince1970.isFinite }),
              library.reviews.allSatisfy({ cards.contains($0.cardID) }),
              library.importedReviews.allSatisfy({ cards.contains($0.cardID) }),
              library.corrections.allSatisfy({ reviews.contains($0.reviewID) }) else { throw EngramError.invalid("The library has missing references or invalid dates. Restore a complete backup.") }
        let settings = library.settings
        guard (0...10_000).contains(settings.newCardsPerDay), (0...100_000).contains(settings.reviewsPerDay),
              (0...23).contains(settings.dayStartsAtHour), TimeZone(identifier: settings.timeZoneID) != nil,
              settings.desiredRetention.isFinite, (0.7...0.99).contains(settings.desiredRetention) else { throw EngramError.invalid("Study settings are outside supported limits.") }
        var total = 0
        let mediaNames = Set(library.media.map(\.name))
        for deck in library.decks {
            if let learning = deck.pdfLearning {
                try learning.brief.validate(source: learning.source)
                try PDFRetrieval.validate(learning.items, against: learning.source.chunks)
            }
            guard deck.desiredRetention.map({ $0.isFinite && (0.8...0.97).contains($0) }) ?? true else {
                throw EngramError.invalid("A deck has an invalid desired retention.")
            }
            guard (deck.sourceDocument?.utf8.count ?? 0) <= DeckDocument.byteLimit else {
                throw EngramError.invalid("A deck document exceeds the 1 MB limit.")
            }
            if let name = deck.coverMediaName {
                try validateMediaName(name)
                guard mediaNames.contains(name) else { throw EngramError.invalid("A deck cover is missing from the library.") }
            }
            guard [deck.createdAt, deck.modifiedAt].compactMap({ $0 }).allSatisfy({ $0.timeIntervalSince1970.isFinite }) else {
                throw EngramError.invalid("A deck has an invalid date.")
            }
        }
        for media in library.media {
            try validateMediaName(media.name)
            guard media.data.count <= 50 * 1_024 * 1_024 else { throw EngramError.invalid("Media files must be 50 MB or smaller.") }
            total += media.data.count
            guard total <= 512 * 1_024 * 1_024 else { throw EngramError.invalid("This library exceeds the 512 MB media limit.") }
        }
    }
    public static func validateMediaName(_ name: String) throws {
        guard !name.isEmpty, name.utf8.count <= 240, !name.contains("/"), !name.contains("\\"), !name.contains(":"), name != ".", name != "..", !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw EngramError.invalid("Unsafe media filename: \(name.prefix(80))") }
    }
    private static func unique(_ values: [String], _ type: String) throws {
        guard Set(values).count == values.count, values.allSatisfy({ !$0.isEmpty }) else { throw EngramError.invalid("Duplicate or empty \(type) identifiers.") }
    }
}

public struct ClozeMarker: Sendable {
    public let ordinal: Int
    public let answer: String
    public let hint: String?
    public let range: NSRange
}
public enum Cloze {
    public static func parse(_ text: String) throws -> [ClozeMarker] {
        let expression = try NSRegularExpression(pattern: #"\{\{c([1-9][0-9]*)::([^{}]+?)\}\}"#)
        let source = text as NSString
        let matches = expression.matches(in: text, range: NSRange(location: 0, length: source.length))
        var remainder = text
        var result: [ClozeMarker] = []
        for match in matches {
            guard let number = Int(source.substring(with: match.range(at: 1))), number <= 500 else { throw EngramError.invalid("Cloze numbers must be between 1 and 500.") }
            let components = source.substring(with: match.range(at: 2)).components(separatedBy: "::")
            guard components.count <= 2, !components[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw EngramError.invalid("Give each cloze a non-empty answer and at most one hint.") }
            result.append(ClozeMarker(ordinal: number - 1, answer: components[0], hint: components.count == 2 ? components[1] : nil, range: match.range))
        }
        for match in matches.reversed() { if let range = Range(match.range, in: remainder) { remainder.replaceSubrange(range, with: "") } }
        guard !result.isEmpty, !remainder.contains("{{"), !remainder.contains("}}") else { throw EngramError.invalid("Use {{c1::answer}} or {{c1::answer::hint}}. Nested and comma-separated clozes are not supported in this build.") }
        return result
    }
    public static func render(_ text: String, ordinal: Int, revealed: Bool) throws -> String {
        let markers = try parse(text)
        guard markers.contains(where: { $0.ordinal == ordinal }) else { throw EngramError.invalid("This cloze card no longer has a matching deletion.") }
        var result = text
        for marker in markers.reversed() {
            let replacement = marker.ordinal == ordinal && !revealed ? "[\(marker.hint?.isEmpty == false ? marker.hint! : "…")]" : marker.answer
            if let range = Range(marker.range, in: result) { result.replaceSubrange(range, with: replacement) }
        }
        return result
    }
}
public struct RenderedCard: Sendable {
    public let prompt: String
    public let answer: String?
    public let source: String?
}
public enum CardRenderer {
    public static func ordinals(for draft: NoteDraft) throws -> [Int] {
        guard draft.front.utf8.count <= 1_000_000, draft.back.utf8.count <= 1_000_000 else { throw EngramError.invalid("Card fields must be smaller than 1 MB.") }
        try validateMarkup(draft.front, required: true, field: "question or cloze text")
        try validateMarkup(draft.back, required: draft.kind == .basic || draft.kind == .reversed, field: "answer")
        switch draft.kind {
        case .basic, .reversed:
            return draft.kind == .basic ? [0] : [0, 1]
        case .cloze:
            let markers = try Cloze.parse(draft.front)
            for marker in markers { try validateMarkup(marker.answer, required: true, field: "cloze answer") }
            return Array(Set(markers.map(\.ordinal))).sorted()
        case .unsupported: throw EngramError.unsupported("This imported note type is preserved for export, but cannot be edited or studied here.")
        }
    }
    private static func validateMarkup(_ text: String, required: Bool, field: String) throws {
        let document = SafeCardMarkup.inspect(text)
        guard document.isSupported else {
            throw EngramError.invalid("The \(field) contains unsupported formatting. \(document.findings.joined(separator: " ")) To show literal HTML tags, escape < and > as &lt; and &gt;.")
        }
        if required && document.mediaNames.isEmpty && document.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw EngramError.invalid("Add visible text or supported media to the \(field) before saving.")
        }
    }
    public static func render(note: Note, card: StudyCard, revealed: Bool) throws -> RenderedCard {
        switch note.kind {
        case .basic, .reversed:
            let reversed = note.kind == .reversed && card.ordinal == 1
            return RenderedCard(prompt: reversed ? note.back : note.front, answer: revealed ? (reversed ? note.front : note.back) : nil, source: revealed ? note.source : nil)
        case .cloze:
            return RenderedCard(prompt: try Cloze.render(note.front, ordinal: card.ordinal, revealed: false), answer: revealed ? try Cloze.render(note.front, ordinal: card.ordinal, revealed: true) + (note.back.isEmpty ? "" : "\n\n" + note.back) : nil, source: revealed ? note.source : nil)
        case .unsupported: throw EngramError.unsupported("This card's template is not supported for study.")
        }
    }
}
