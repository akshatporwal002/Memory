import Foundation
import LearningCore

public enum AnkiSchedulingTreatment: Sendable { case contentOnly, preserveSource }
public enum AnkiExportMode: Sendable { case sharing, personalTransfer }
public struct CompatibilityFinding: Codable, Equatable, Sendable {
    public enum Severity: String, Codable, Sendable { case warning, blocking }
    public var severity: Severity
    public var message: String
    public init(_ severity: Severity, _ message: String) { self.severity = severity; self.message = message }
}
public struct AnkiCompatibilityReport: Codable, Equatable, Sendable {
    public var format: String
    public var deckCount: Int
    public var noteCount: Int
    public var cardCount: Int
    public var mediaCount: Int
    public var historyCount: Int
    public var findings: [CompatibilityFinding]
    public var canImport: Bool { !findings.contains { $0.severity == .blocking } }
    /// True for new cards and supported FSRS review memory states; future intervals use Engram policy.
    public var canContinueScheduling: Bool
}

public struct AnkiInspection: Sendable {
    public let report: AnkiCompatibilityReport
    public let namespace: String
    fileprivate let collection: [String: String]
    fileprivate let decks: [Deck]
    fileprivate let notes: [Note]
    fileprivate let cardRows: [[String: String]]
    fileprivate let reviewRows: [[String: String]]
    fileprivate let noteIDs: [String: String]
    fileprivate let media: [MediaFile]

    /// Produces a candidate only. The application owns confirmation, backup, merge and durable commit.
    public func makeLibrary(scheduling: AnkiSchedulingTreatment, scheduler: any Scheduler, now: Date, settings: StudySettings) throws -> LibrarySnapshot {
        guard report.canImport else { throw EngramError.unsupported(report.findings.filter { $0.severity == .blocking }.map(\.message).joined(separator: "\n")) }
        if scheduling == .preserveSource && !report.canContinueScheduling {
            throw EngramError.unsupported("This package has learning, legacy SM-2, buried or filtered scheduling that cannot yet be mapped. Choose the explicitly labelled content-only import to start fresh while preserving original scheduling and history in your native backup, or cancel.")
        }
        var snapshot = LibrarySnapshot(); snapshot.libraryID = namespace; snapshot.settings = settings
        snapshot.decks = decks; snapshot.notes = notes; snapshot.media = media
        for row in cardRows {
            guard let sourceID = row["id"], let noteID = noteIDs[row["nid"] ?? ""], let ordinal = Int(row["ord"] ?? "") else { throw EngramError.invalid("Card references an unavailable note or ordinal.") }
            let deckID = namespace + ":deck:" + (row["did"] ?? "")
            let state: ScheduleState
            if scheduling == .preserveSource {
                guard let mapper = scheduler as? any ImportedScheduleMapping else { throw EngramError.unsupported("The selected scheduler cannot import Anki states.") }
                let phase: LearningPhase = row["type"] == "2" ? .review : .new
                var values = row
                if let data = row["data"], let object = try? jsonObject(data) {
                    for (key, value) in object { values[key] = String(describing: value) }
                }
                let due = phase == .new ? now : try importedDue(row: row, collection: collection, settings: settings)
                state = try mapper.importState(due: due, phase: phase, sourceValues: values, settings: settings)
            } else { state = try scheduler.initialState(now: now, settings: settings) }
            var source = row
            for (key, value) in collection { source["collection." + key] = value }
            snapshot.cards.append(StudyCard(id: namespace + ":card:" + sourceID, noteID: noteID, deckID: deckID, ordinal: ordinal,
                schedule: state, suspended: row["queue"] == "-1", sourceCardID: sourceID, sourceSchedule: source))
        }
        for row in reviewRows {
            guard let id = row["id"], let cardID = row["cid"] else { throw EngramError.invalid("Review record has no identity.") }
            snapshot.importedReviews.append(ImportedReview(id: namespace + ":review:" + id, cardID: namespace + ":card:" + cardID, origin: namespace, values: row))
        }
        try LibraryValidation.validate(snapshot)
        return snapshot
    }
}

public enum AnkiPackageAdapter {
    public static func inspect(url: URL, namespace requestedNamespace: String? = nil) throws -> AnkiInspection {
        let archive = try SafeArchive.read(url)
        if archive["meta"] != nil || archive["collection.anki21b"] != nil {
            throw EngramError.unsupported("Modern Anki packages with zstd/protobuf are not supported in this build. In Anki 26.08.1, export with ‘Support older Anki versions’, then try again. Your library was not changed.")
        }
        let member = archive["collection.anki21"] != nil ? "collection.anki21" : "collection.anki2"
        guard let collectionBytes = archive[member] else { throw EngramError.invalid("Package is missing a legacy Anki collection.") }
        let isCollection = url.pathExtension.lowercased() == "colpkg" || url.lastPathComponent.lowercased() == "collection.apkg"
        return try withTemporaryDatabase(collectionBytes) { db, _ in
            let colRows = try db.rows("SELECT * FROM col")
            guard colRows.count == 1, let col = colRows.first, col["ver"] == "11" else { throw EngramError.unsupported("Only Anki legacy collection schema 11 is supported. No data was imported.") }
            guard try db.rows("PRAGMA quick_check").first?.values.first == "ok" else { throw EngramError.invalid("The Anki database failed its integrity check.") }
            let namespace = requestedNamespace ?? "anki-" + (col["crt"] ?? "unknown")
            guard !namespace.isEmpty, namespace.utf8.count <= 200 else { throw EngramError.invalid("Choose a short, stable source namespace.") }
            let models = try jsonObject(col["models"] ?? "{}"), sourceDecks = try jsonObject(col["decks"] ?? "{}")
            let noteRows = try db.rows("SELECT * FROM notes"), cards = try db.rows("SELECT * FROM cards"), reviews = try db.rows("SELECT * FROM revlog")
            guard noteRows.count <= 250_000, cards.count <= 500_000 else { throw EngramError.invalid("The package exceeds the current library limits.") }
            var findings: [CompatibilityFinding] = [], decks: [Deck] = [], notes: [Note] = [], noteIDs: [String: String] = [:]
            for (id, object) in sourceDecks {
                guard let deck = object as? [String: Any], let name = deck["name"] as? String else { throw EngramError.invalid("Anki deck metadata is malformed.") }
                decks.append(Deck(id: namespace + ":deck:" + id, name: name.replacingOccurrences(of: "\u{1f}", with: "::")))
                if (deck["dyn"] as? NSNumber)?.intValue != 0, deck["dyn"] != nil { findings.append(.init(.blocking, "Filtered deck ‘\(name)’ needs to be emptied back into its original decks in Anki before migration.")) }
            }
            let cardsByNote = Dictionary(grouping: cards, by: { $0["nid"] ?? "" })
            for row in noteRows {
                guard let sourceID = row["id"], let guid = row["guid"], !guid.isEmpty,
                      let modelID = row["mid"], let model = models[modelID] as? [String: Any],
                      let noteCards = cardsByNote[sourceID], let firstCard = noteCards.first,
                      let deckID = firstCard["did"] else { throw EngramError.invalid("A note has missing card or note-type references.") }
                let fields = (row["flds"] ?? "").components(separatedBy: "\u{1f}")
                let kind = supportedKind(model, fields: fields)
                if kind == .unsupported { findings.append(.init(.blocking, "Note \(sourceID) uses an unsupported template, CSS, field markup or cloze form. Original data was inspected but not flattened or imported.")) }
                let id = namespace + ":note:" + guid; noteIDs[sourceID] = id
                let modelData = try JSONSerialization.data(withJSONObject: model, options: [.sortedKeys])
                var metadata = row; metadata["collection.crt"] = col["crt"]; metadata["collection.conf"] = col["conf"]; metadata["collection.dconf"] = col["dconf"]
                let origin = ImportOrigin(namespace: namespace, noteID: sourceID, guid: guid, noteTypeJSON: modelData, fields: fields, metadata: metadata)
                let note = Note(id: id, deckID: namespace + ":deck:" + deckID, kind: kind, front: fields.first ?? "", back: fields.count > 1 ? fields[1] : "",
                    tags: (row["tags"] ?? "").split(whereSeparator: { $0.isWhitespace }).map(String.init), origin: origin,
                    modifiedAt: Date(timeIntervalSince1970: Double(row["mod"] ?? "0") ?? 0))
                if kind != .unsupported {
                    let valid = Set((try? CardRenderer.ordinals(for: NoteDraft(note: note))) ?? [])
                    if !noteCards.allSatisfy({ Int($0["ord"] ?? "").map(valid.contains) ?? false }) { findings.append(.init(.blocking, "Note \(sourceID) contains an empty or unsupported generated card ordinal.")) }
                }
                notes.append(note)
            }
            var media: [MediaFile] = [], mediaNames = Set<String>()
            if let manifest = archive["media"] {
                guard let map = try JSONSerialization.jsonObject(with: manifest) as? [String: String] else { throw EngramError.invalid("Legacy media manifest must map entry numbers to filenames.") }
                for (key, name) in map {
                    try LibraryValidation.validateMediaName(name)
                    guard UInt(key) != nil, mediaNames.insert(name.lowercased()).inserted else { throw EngramError.invalid("Duplicate or invalid media mapping.") }
                    if let bytes = archive[key] { media.append(MediaFile(name: name, data: bytes)) }
                    else { findings.append(.init(.warning, "Missing media payload: \(name)")) }
                }
            } else { findings.append(.init(.warning, "This package has no media manifest.")) }
            let canContinue = cards.allSatisfy { row in
                guard (Int(row["odid"] ?? "0") ?? 0) == 0 else { return false }
                if row["type"] == "0" { return ["0", "-1"].contains(row["queue"] ?? "") }
                guard row["type"] == "2", ["2", "-1"].contains(row["queue"] ?? ""),
                      let values = try? jsonObject(row["data"] ?? "{}") else { return false }
                return ["s", "d", "lrt"].allSatisfy { values[$0] is NSNumber }
            }
            if canContinue && cards.contains(where: { $0["type"] == "2" }) {
                findings.append(.init(.warning, "Preserve scheduling retains supported FSRS memory, due calendar date and source history. Future intervals use Engram FSRS-6 defaults and your retention setting, not Anki's custom parameters, fuzz or learning policy. Due calendar dates use your chosen timezone and rollover hour."))
            } else if !canContinue { findings.append(.init(.warning, "Some source scheduling cannot be mapped. Content-only import requires your explicit choice; raw due values, parameters and all review history remain preserved as source evidence.")) }
            if reviews.isEmpty { findings.append(.init(.warning, "No review history is present; it cannot be reconstructed from card content.")) }
            if isCollection { findings.append(.init(.warning, "Collection migration returns a candidate library. Engram must create a pre-import backup and ask for a new-library or merge choice; it must never silently replace existing cards.")) }
            return AnkiInspection(report: AnkiCompatibilityReport(format: isCollection ? "legacy-colpkg-schema11" : "legacy-apkg-schema11", deckCount: decks.count, noteCount: notes.count, cardCount: cards.count,
                mediaCount: media.count, historyCount: reviews.count, findings: findings, canContinueScheduling: canContinue), namespace: namespace, collection: col,
                decks: decks, notes: notes, cardRows: cards, reviewRows: reviews, noteIDs: noteIDs, media: media)
        }
    }
}

func importedDue(row: [String: String], collection: [String: String], settings: StudySettings) throws -> Date {
    guard let epoch = Double(collection["crt"] ?? ""), let day = Int(row["due"] ?? ""), (-100_000...1_000_000).contains(day) else { throw EngramError.invalid("Invalid collection-relative Anki due date.") }
    let conf = try jsonObject(collection["conf"] ?? "{}")
    let minutesWest = (conf["creationOffset"] as? NSNumber)?.intValue ?? 0
    guard let sourceZone = TimeZone(secondsFromGMT: -minutesWest * 60), let targetZone = TimeZone(identifier: settings.timeZoneID) else { throw EngramError.invalid("Invalid source or destination timezone.") }
    var sourceCalendar = Calendar(identifier: .gregorian); sourceCalendar.timeZone = sourceZone
    let sourceDate = sourceCalendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: epoch))
    var targetCalendar = Calendar(identifier: .gregorian); targetCalendar.timeZone = targetZone
    guard let start = targetCalendar.date(from: sourceDate), let dueDay = targetCalendar.date(byAdding: .day, value: day, to: start),
          let due = targetCalendar.date(bySettingHour: settings.dayStartsAtHour, minute: 0, second: 0, of: dueDay) else { throw EngramError.invalid("Anki due date is outside the supported calendar range.") }
    return due
}

func jsonObject(_ text: String) throws -> [String: Any] {
    guard let data = text.data(using: .utf8), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw EngramError.invalid("Invalid Anki JSON metadata.") }
    return object
}
func compactTemplate(_ text: String) -> String { text.components(separatedBy: .whitespacesAndNewlines).joined() }
func supportedKind(_ model: [String: Any], fields: [String]) -> NoteKind {
    guard let definitions = model["flds"] as? [[String: Any]], definitions.count == fields.count, fields.count >= 2,
          let first = definitions[0]["name"] as? String, let second = definitions[1]["name"] as? String,
          let templates = model["tmpls"] as? [[String: Any]], !templates.isEmpty,
          fields.allSatisfy(safeFieldMarkup) else { return .unsupported }
    let css = compactTemplate((model["css"] as? String ?? "").lowercased())
    let allowedCSS = ["", ".card{font-family:arial;font-size:20px;text-align:center;color:black;background-color:white;}", ".card{font-family:arial;font-size:20px;text-align:center;color:black;background-color:white;}.cloze{font-weight:bold;color:blue;}.nightmode.cloze{color:lightblue;}"]
    guard allowedCSS.contains(css.replacingOccurrences(of: "line-height:1.5;", with: "")) else { return .unsupported }
    let q = "{{\(first)}}", back = "{{\(second)}}"
    func matches(_ template: [String: Any], question: String, answer: String) -> Bool {
        let actualQ = compactTemplate(template["qfmt"] as? String ?? "")
        let actualA = compactTemplate(template["afmt"] as? String ?? "")
        return actualQ == compactTemplate(question) && [answer, "{{FrontSide}}<hrid=answer>" + answer, "{{FrontSide}}<hrid=\"answer\">" + answer].map(compactTemplate).contains(actualA)
    }
    if (model["type"] as? NSNumber)?.intValue == 1 {
        let cloze = "{{cloze:\(first)}}"
        guard templates.count == 1, (try? Cloze.parse(fields[0])) != nil,
              compactTemplate(templates[0]["qfmt"] as? String ?? "") == compactTemplate(cloze),
              [cloze + "<br>" + back, cloze + back].map(compactTemplate).contains(compactTemplate(templates[0]["afmt"] as? String ?? "")) else { return .unsupported }
        return .cloze
    }
    guard matches(templates[0], question: q, answer: back) else { return .unsupported }
    if templates.count == 1 { return .basic }
    if templates.count == 2, matches(templates[1], question: back, answer: q) { return .reversed }
    return .unsupported
}
func safeFieldMarkup(_ field: String) -> Bool {
    guard field.utf8.count <= 1_000_000 else { return false }
    let pattern = #"(?is)<\s*/?\s*(script|iframe|object|embed|style|svg|form|input|button|link|meta)\b|\bon\w+\s*=|javascript\s*:|data\s*:|https?\s*://|\[latex\]|\\\("#
    return field.range(of: pattern, options: .regularExpression) == nil
}
