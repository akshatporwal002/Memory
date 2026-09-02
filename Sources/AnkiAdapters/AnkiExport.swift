import Foundation
import LearningCore

extension AnkiPackageAdapter {
    /// Writes a legacy schema11 APKG. Sharing omits all personal scheduling and history.
    public static func export(snapshot: LibrarySnapshot, deckIDs: Set<String>? = nil, mode: AnkiExportMode, to url: URL) throws {
        try LibraryValidation.validate(snapshot)
        let selectedNames = snapshot.liveDecks.filter { deckIDs?.contains($0.id) == true }.map(\.name)
        let expandedDeckIDs = Set(snapshot.liveDecks.filter { deck in deckIDs == nil || selectedNames.contains { name in deck.name.caseInsensitiveCompare(name) == .orderedSame || deck.name.lowercased().hasPrefix(name.lowercased() + "::") } }.map(\.id))
        let selected = snapshot.liveCards.filter { expandedDeckIDs.contains($0.deckID) }
        guard !selected.isEmpty else { throw EngramError.invalid("Choose at least one supported card to export.") }
        let noteSet = Set(selected.map(\.noteID))
        let notes = snapshot.liveNotes.filter { noteSet.contains($0.id) }
        // Preserve all sibling cards of selected notes: the export dialog must disclose note-level scope.
        let cards = snapshot.liveCards.filter { noteSet.contains($0.noteID) }
        guard notes.allSatisfy({ $0.kind != .unsupported && safeFieldMarkup($0.front) && safeFieldMarkup($0.back) }) else { throw EngramError.unsupported("This selection contains unsupported content. Use a complete native backup to retain it.") }
        let deckSet = Set(cards.map(\.deckID))
        let cardDeckNames = snapshot.liveDecks.filter { deckSet.contains($0.id) }.map { $0.name.lowercased() }
        let decks = snapshot.liveDecks.filter { deck in deckIDs == nil || expandedDeckIDs.contains(deck.id) || deckSet.contains(deck.id) || cardDeckNames.contains { $0.hasPrefix(deck.name.lowercased() + "::") } }
        let deckMap = numericIDs(decks.map { ($0.id, $0.id.components(separatedBy: ":deck:").count == 2 ? $0.id.components(separatedBy: ":deck:").last : nil) })
        let noteMap = numericIDs(notes.map { ($0.id, $0.origin?.noteID) })
        let cardMap = numericIDs(cards.map { ($0.id, $0.sourceCardID) })
        let guids = notes.map { $0.origin?.guid ?? $0.id }
        guard Set(guids).count == guids.count else { throw EngramError.unsupported("This selection contains colliding source GUIDs from different libraries. Export the libraries separately.") }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: snapshot.settings.timeZoneID)!
        let creation = calendar.date(from: DateComponents(year: 2020, month: 1, day: 1))!
        var models: [String: Any] = [:], modelKeys: [Data: String] = [:], noteModel: [String: String] = [:]
        for note in notes {
            if let origin = note.origin, !origin.noteTypeJSON.isEmpty {
                guard let original = try JSONSerialization.jsonObject(with: origin.noteTypeJSON) as? [String: Any],
                      supportedKind(original, fields: origin.fields) == note.kind else { throw EngramError.unsupported("An imported note changed its note type. Its original schema cannot be exported faithfully; retain a complete native backup and resolve the note-type conversion before Anki export.") }
            }
            let raw = note.origin?.noteTypeJSON ?? Data(note.kind.rawValue.utf8)
            let modelID: String
            if let existing = modelKeys[raw] { modelID = existing }
            else {
                modelID = String(1_600_000_000_000 + modelKeys.count)
                var model: [String: Any]
                if let origin = note.origin, !origin.noteTypeJSON.isEmpty,
                   let original = try JSONSerialization.jsonObject(with: origin.noteTypeJSON) as? [String: Any] { model = original }
                else { model = standardModel(kind: note.kind) }
                model["id"] = Int64(modelID)!; model["mod"] = Int(Date().timeIntervalSince1970); model["usn"] = -1
                models[modelID] = model; modelKeys[raw] = modelID
            }
            noteModel[note.id] = modelID
        }
        var deckJSON: [String: Any] = [:]
        for deck in decks {
            let id = deckMap[deck.id]!
            deckJSON[id] = ["id": Int64(id)!, "name": deck.name, "mod": 0, "usn": -1, "desc": "", "dyn": 0, "collapsed": false, "browserCollapsed": false,
                            "conf": 1, "extendNew": 0, "extendRev": 0, "newToday": [0, 0], "revToday": [0, 0], "lrnToday": [0, 0], "timeToday": [0, 0]] as [String: Any]
        }
        var archive: [String: Data] = [:]
        archive["meta"] = Data([8, 2]) // PackageMetadata version = Legacy2; independently encoded protobuf scalar.
        var mediaMap: [String: String] = [:]
        let referencedMedia = Set(notes.flatMap { note -> [String] in
            var fields = note.origin?.fields ?? [note.front, note.back]
            if fields.count >= 2 { fields[0] = note.front; fields[1] = note.back }
            return fields.flatMap { SafeCardMarkup.inspect($0).mediaNames }
        })
        let missing = referencedMedia.subtracting(Set(snapshot.media.map(\.name)))
        guard missing.isEmpty else { throw EngramError.invalid("Export has missing referenced media: \(missing.sorted().joined(separator: ", ")). Restore these files before Anki export; a native backup can retain the current incomplete library.") }
        for (index, item) in snapshot.media.filter({ referencedMedia.contains($0.name) }).enumerated() { archive[String(index)] = item.data; mediaMap[String(index)] = item.name }
        archive["media"] = try JSONSerialization.data(withJSONObject: mediaMap, options: [.sortedKeys])
        archive["collection.anki21"] = try withTemporaryDatabase(nil) { db, dbURL in
            for sql in schemaStatements { try db.execute(sql) }
            try db.execute("BEGIN IMMEDIATE")
            let conf: [String: Any] = ["schedVer": 2, "creationOffset": -calendar.timeZone.secondsFromGMT(for: creation) / 60,
                "rollover": snapshot.settings.dayStartsAtHour, "curDeck": Int64(deckMap[decks[0].id]!)!, "activeDecks": decks.map { Int64(deckMap[$0.id]!)! }, "nextPos": cards.count + 1, "fsrs": true, "engramLibraryID": snapshot.libraryID]
            try db.execute("INSERT INTO col VALUES (1, ?, 0, 0, 11, 0, -1, 0, ?, ?, ?, ?, '{}')", [String(Int(creation.timeIntervalSince1970)), try jsonString(conf), try jsonString(models), try jsonString(deckJSON), try jsonString(["1": defaultDeckConfig()])])
            for note in notes {
                var fields = note.origin?.fields ?? [note.front, note.back]
                guard fields.count >= 2 else { throw EngramError.invalid("An exported note has fewer than two fields.") }
                fields[0] = note.front; fields[1] = note.back
                let tags = mode == .sharing ? note.tags.filter { !["marked", "leech"].contains($0.lowercased()) } : note.tags
                try db.execute("INSERT INTO notes VALUES (?, ?, ?, ?, -1, ?, ?, ?, 0, 0, '')", [noteMap[note.id]!, note.origin?.guid ?? note.id, noteModel[note.id]!, String(Int(note.modifiedAt.timeIntervalSince1970)), " " + tags.joined(separator: " ") + " ", fields.joined(separator: "\u{1f}"), note.front])
            }
            for (position, card) in cards.enumerated() {
                let values = try exportedSchedule(card, mode: mode, position: position + 1, creation: creation, calendar: calendar, retention: snapshot.settings.desiredRetention)
                try db.execute("INSERT INTO cards VALUES (?, ?, ?, ?, 0, -1, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, 0, ?)", [cardMap[card.id]!, noteMap[card.noteID]!, deckMap[card.deckID]!, String(card.ordinal)] + values)
            }
            if mode == .personalTransfer {
                let imported = snapshot.importedReviews.filter { cardMap[$0.cardID] != nil }
                let active = snapshot.activeReviews.filter { cardMap[$0.cardID] != nil }
                var usedReviewIDs = Set<String>()
                for review in imported {
                    let row = review.values
                    let id = uniqueReviewID(row["id"] ?? "0", used: &usedReviewIDs)
                    try db.execute("INSERT INTO revlog VALUES (?, ?, -1, ?, ?, ?, ?, ?, ?)", [id, cardMap[review.cardID]!, row["ease"] ?? "0", row["ivl"] ?? "0", row["lastIvl"] ?? "0", row["factor"] ?? "0", row["time"] ?? "0", row["type"] ?? "0"])
                }
                for review in active {
                    let id = uniqueReviewID(String(Int64(review.reviewedAt.timeIntervalSince1970 * 1000)), used: &usedReviewIDs)
                    let after = try fsrsPayload(review.after), before = try fsrsPayload(review.before)
                    let interval = review.after.phase == .review ? Int(after.scheduledDays.rounded()) : -max(1, Int(review.after.due.timeIntervalSince(review.reviewedAt)))
                    let previous = review.before.phase == .review ? Int(before.scheduledDays.rounded()) : 0
                    let kind = review.before.phase == .new || review.before.phase == .learning ? 0 : review.before.phase == .relearning ? 2 : 1
                    let difficulty = Int(((after.difficulty - 1) / 9 + 0.1) * 1000)
                    try db.execute("INSERT INTO revlog VALUES (?, ?, -1, ?, ?, ?, ?, 0, ?)", [id, cardMap[review.cardID]!, String(review.rating.rawValue), String(interval), String(previous), String(max(0, difficulty)), String(kind)])
                }
            }
            try db.execute("COMMIT")
            return try Data(contentsOf: dbURL)
        }
        // Current Anki discovers this schema11 package from the collection.anki21 member.
        try SafeArchive.write(archive, to: url)
    }
}

private struct FSRSPayload: Decodable {
    var stability: Double; var difficulty: Double; var scheduledDays: Double
    var reps: Int; var lapses: Int; var learningSteps: Int; var lastReview: Date?
}
private func fsrsPayload(_ state: ScheduleState) throws -> FSRSPayload {
    guard state.schedulerID == "fsrs-6", state.schemaVersion == 1, state.implementationVersion == "swift-fsrs-4fbaf201" else { throw EngramError.unsupported("Personal-transfer export cannot map this scheduler. Choose sharing for content only, and retain a native backup for complete state.") }
    let value = try JSONDecoder().decode(FSRSPayload.self, from: state.payload)
    guard value.stability.isFinite, (0...1_000_000_000).contains(value.stability), value.difficulty.isFinite, (0...10).contains(value.difficulty),
          value.scheduledDays.isFinite, (0...36_500).contains(value.scheduledDays), (0...100_000_000).contains(value.reps),
          (0...100_000_000).contains(value.lapses), (0...1_000).contains(value.learningSteps),
          value.lastReview.map({ $0.timeIntervalSince1970.isFinite && abs($0.timeIntervalSince1970) < 100_000_000_000 }) ?? true else { throw EngramError.invalid("Saved scheduler values are outside the supported export range.") }
    return value
}
private func exportedSchedule(_ card: StudyCard, mode: AnkiExportMode, position: Int, creation: Date, calendar: Calendar, retention: Double) throws -> [String] {
    if mode == .sharing { return ["0", "0", String(position), "0", "0", "0", "0", "0", ""] }
    if card.schedule.phase == .new { return ["0", card.suspended ? "-1" : "0", String(position), "0", "0", "0", "0", "0", ""] }
    let payload = try fsrsPayload(card.schedule)
    let phase = card.schedule.phase == .review ? 2 : card.schedule.phase == .learning ? 1 : 3
    let queue = card.suspended ? -1 : phase == 2 ? 2 : 1
    let due: Int
    if phase == 2 { due = calendar.dateComponents([.day], from: calendar.startOfDay(for: creation), to: calendar.startOfDay(for: card.schedule.due)).day! }
    else { due = Int(card.schedule.due.timeIntervalSince1970) }
    var metadata: [String: Any] = ["s": payload.stability, "d": payload.difficulty, "dr": retention]
    if let last = payload.lastReview { metadata["lrt"] = Int(last.timeIntervalSince1970) }
    // Engram's step index maps to the remaining configured [1m,10m]/[10m] steps.
    let remaining = max(0, (phase == 3 ? 1 : 2) - payload.learningSteps)
    return [String(phase), String(queue), String(due), String(max(1, Int(payload.scheduledDays.rounded()))), "0", String(payload.reps), String(payload.lapses), String(phase == 2 ? 0 : remaining * 1001), try jsonString(metadata)]
}
private func numericIDs(_ entries: [(String, String?)]) -> [String: String] {
    var result: [String: String] = [:], used = Set<Int64>()
    for (key, preferred) in entries.sorted(by: { $0.0 < $1.0 }) {
        var hash: UInt64 = 14695981039346656037
        for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        var id = preferred.flatMap(Int64.init).flatMap { $0 > 0 ? $0 : nil } ?? 1_600_000_000_000 + Int64(hash % 100_000_000)
        while used.contains(id) { id += 1 }; used.insert(id); result[key] = String(id)
    }
    return result
}
private func uniqueReviewID(_ candidate: String, used: inout Set<String>) -> String {
    var id = max(1, Int64(candidate) ?? 1)
    while used.contains(String(id)) { id += 1 }; used.insert(String(id)); return String(id)
}
private func jsonString(_ value: Any) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self) }
private func standardModel(kind: NoteKind) -> [String: Any] {
    let names = kind == .cloze ? ["Text", "Back Extra"] : ["Front", "Back"]
    let templates: [[String: Any]]
    if kind == .cloze { templates = [["name": "Cloze", "ord": 0, "qfmt": "{{cloze:Text}}", "afmt": "{{cloze:Text}}<br>{{Back Extra}}", "bqfmt": "", "bafmt": "", "did": NSNull()]] }
    else {
        templates = (kind == .reversed ? [0, 1] : [0]).map { ordinal in
            let front = ordinal == 0 ? "Front" : "Back", back = ordinal == 0 ? "Back" : "Front"
            return ["name": "Card \(ordinal + 1)", "ord": ordinal, "qfmt": "{{\(front)}}", "afmt": "{{FrontSide}}<hr id=answer>{{\(back)}}", "bqfmt": "", "bafmt": "", "did": NSNull()]
        }
    }
    return ["id": 0, "name": "Engram \(kind.rawValue.capitalized)", "type": kind == .cloze ? 1 : 0, "mod": 0, "usn": -1, "sortf": 0, "did": 1,
        "css": "", "latexPre": "", "latexPost": "", "latexsvg": false,
        "flds": names.enumerated().map { ["name": $0.element, "ord": $0.offset, "sticky": false, "rtl": false, "font": "Arial", "size": 20] as [String: Any] }, "tmpls": templates,
        "req": kind == .cloze ? [] : templates.indices.map { [$0, "all", [$0]] as [Any] }]
}
private func defaultDeckConfig() -> [String: Any] {
    ["id": 1, "name": "Engram transfer", "mod": 0, "usn": -1, "maxTaken": 60, "autoplay": true, "timer": 0, "replayq": true,
     "new": ["delays": [1, 10], "ints": [1, 4], "initialFactor": 2500, "order": 1, "perDay": 20, "bury": false] as [String: Any],
     "rev": ["perDay": 200, "ease4": 1.3, "fuzz": 0.05, "ivlFct": 1, "maxIvl": 36500, "bury": false, "hardFactor": 1.2] as [String: Any],
     "lapse": ["delays": [10], "mult": 0, "minInt": 1, "leechFails": 8, "leechAction": 0] as [String: Any]]
}
private let schemaStatements = [
    "CREATE TABLE col (id INTEGER PRIMARY KEY, crt INTEGER NOT NULL, mod INTEGER NOT NULL, scm INTEGER NOT NULL, ver INTEGER NOT NULL, dty INTEGER NOT NULL, usn INTEGER NOT NULL, ls INTEGER NOT NULL, conf TEXT NOT NULL, models TEXT NOT NULL, decks TEXT NOT NULL, dconf TEXT NOT NULL, tags TEXT NOT NULL)",
    "CREATE TABLE notes (id INTEGER PRIMARY KEY, guid TEXT NOT NULL, mid INTEGER NOT NULL, mod INTEGER NOT NULL, usn INTEGER NOT NULL, tags TEXT NOT NULL, flds TEXT NOT NULL, sfld INTEGER NOT NULL, csum INTEGER NOT NULL, flags INTEGER NOT NULL, data TEXT NOT NULL)",
    "CREATE TABLE cards (id INTEGER PRIMARY KEY, nid INTEGER NOT NULL, did INTEGER NOT NULL, ord INTEGER NOT NULL, mod INTEGER NOT NULL, usn INTEGER NOT NULL, type INTEGER NOT NULL, queue INTEGER NOT NULL, due INTEGER NOT NULL, ivl INTEGER NOT NULL, factor INTEGER NOT NULL, reps INTEGER NOT NULL, lapses INTEGER NOT NULL, left INTEGER NOT NULL, odue INTEGER NOT NULL, odid INTEGER NOT NULL, flags INTEGER NOT NULL, data TEXT NOT NULL)",
    "CREATE TABLE revlog (id INTEGER PRIMARY KEY, cid INTEGER NOT NULL, usn INTEGER NOT NULL, ease INTEGER NOT NULL, ivl INTEGER NOT NULL, lastIvl INTEGER NOT NULL, factor INTEGER NOT NULL, time INTEGER NOT NULL, type INTEGER NOT NULL)",
    "CREATE TABLE graves (usn INTEGER NOT NULL, oid INTEGER NOT NULL, type INTEGER NOT NULL)",
    "CREATE INDEX ix_cards_sched ON cards(did,queue,due)", "CREATE INDEX ix_cards_nid ON cards(nid)", "CREATE INDEX ix_notes_csum ON notes(csum)", "CREATE INDEX ix_revlog_cid ON revlog(cid)",
    "CREATE INDEX ix_notes_usn ON notes(usn)", "CREATE INDEX ix_cards_usn ON cards(usn)", "CREATE INDEX ix_revlog_usn ON revlog(usn)"
]
