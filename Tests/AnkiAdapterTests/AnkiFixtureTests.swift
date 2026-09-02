import XCTest
import LearningCore
import SchedulingAdapters
@testable import AnkiAdapters

final class AnkiFixtureTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL { try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")) }
    private var settings: StudySettings { StudySettings(timeZoneID: "Australia/Sydney") }
    func testDirectExportNativeProvenanceAllowsApplicationToBlockSameLibrary() throws {
        var library = LibrarySnapshot(); library.settings = settings
        let deck = Deck(name: "Native"), noteID = UUID().uuidString
        let note = Note(id: noteID, deckID: deck.id, kind: .basic, front: "Question", back: "Answer")
        let card = StudyCard(noteID: noteID, deckID: deck.id, schedule: try FSRSScheduler().initialState(now: Date(), settings: settings))
        library.decks = [deck]; library.notes = [note]; library.cards = [card]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".apkg")
        defer { try? FileManager.default.removeItem(at: url) }
        try AnkiPackageAdapter.export(snapshot: library, mode: .personalTransfer, to: url)
        let inspection = try AnkiPackageAdapter.inspect(url: url)
        XCTAssertEqual(inspection.sourceLibraryID, library.libraryID)
        let candidate = try inspection.makeLibrary(scheduling: .preserveSource, scheduler: FSRSScheduler(), now: Date(), settings: settings)
        XCTAssertTrue(candidate.notes.allSatisfy { $0.origin?.metadata["engramSourceLibraryID"] == library.libraryID })
        let override = try AnkiPackageAdapter.inspect(url: url, namespace: "explicit-other-source")
        XCTAssertEqual(override.namespace, "explicit-other-source")
        XCTAssertEqual(override.sourceLibraryID, library.libraryID)
        let overrideCandidate = try override.makeLibrary(scheduling: .contentOnly, scheduler: FSRSScheduler(), now: Date(), settings: settings)
        XCTAssertTrue(overrideCandidate.notes.allSatisfy { $0.origin?.metadata["engramSourceLibraryID"] == library.libraryID })
    }
    func testDirectExportImportedProvenanceAndSeparateTargetIdentityRemainStable() throws {
        var library = try AnkiPackageAdapter.inspect(url: fixture("anki-26.8.1-legacy.apkg")).makeLibrary(scheduling: .preserveSource, scheduler: FSRSScheduler(), now: Date(), settings: settings)
        library.libraryID = UUID().uuidString // Represents merging source notes into an existing Engram library.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".apkg")
        defer { try? FileManager.default.removeItem(at: url) }
        try AnkiPackageAdapter.export(snapshot: library, mode: .personalTransfer, to: url)
        let inspection = try AnkiPackageAdapter.inspect(url: url)
        XCTAssertEqual(inspection.sourceLibraryID, library.libraryID)
        let candidate = try inspection.makeLibrary(scheduling: .preserveSource, scheduler: FSRSScheduler(), now: Date(), settings: settings)
        XCTAssertTrue(candidate.notes.allSatisfy { $0.origin?.metadata["engramSourceLibraryID"] == library.libraryID })
        let repeated = try AnkiPackageAdapter.inspect(url: url).makeLibrary(scheduling: .preserveSource, scheduler: FSRSScheduler(), now: Date(), settings: settings)
        XCTAssertEqual(candidate.notes.map(\.id), repeated.notes.map(\.id))
        XCTAssertEqual(candidate.cards.map(\.id), repeated.cards.map(\.id))
        XCTAssertEqual(candidate.importedReviews, repeated.importedReviews)
        XCTAssertEqual(candidate.notes.count, library.notes.count)
        XCTAssertEqual(candidate.cards.count, library.cards.count)
    }
    func testRealLegacyInspectionContentOnlyAndStableIDs() throws {
        let inspection = try AnkiPackageAdapter.inspect(url: fixture("anki-26.8.1-legacy.apkg"))
        XCTAssertTrue(inspection.report.canImport, inspection.report.findings.map(\.message).joined(separator: "\n"))
        XCTAssertEqual(inspection.report.noteCount, 3); XCTAssertEqual(inspection.report.cardCount, 5)
        XCTAssertEqual(inspection.report.mediaCount, 2); XCTAssertEqual(inspection.report.historyCount, 1)
        let now = Date(timeIntervalSince1970: 1_788_390_000)
        let library = try inspection.makeLibrary(scheduling: .contentOnly, scheduler: FSRSScheduler(), now: now, settings: settings)
        XCTAssertEqual(library.notes.count, 3); XCTAssertEqual(library.cards.count, 5)
        XCTAssertEqual(library.importedReviews.count, 1); XCTAssertTrue(library.reviews.isEmpty)
        XCTAssertEqual(library.cards.filter(\.suspended).count, 1)
        XCTAssertTrue(library.cards.allSatisfy { $0.schedule.phase == .new })
        XCTAssertEqual(Set(library.notes.map(\.kind)), Set([.basic, .reversed, .cloze]))
        let again = try AnkiPackageAdapter.inspect(url: fixture("anki-26.8.1-legacy.apkg")).makeLibrary(scheduling: .contentOnly, scheduler: FSRSScheduler(), now: now, settings: settings)
        XCTAssertEqual(library.notes.map(\.id), again.notes.map(\.id))
        XCTAssertEqual(library.cards.map(\.id), again.cards.map(\.id))
    }
    func testPreservationAndExportsForOfficialAnkiRoundtrip() throws {
        let inspection = try AnkiPackageAdapter.inspect(url: fixture("anki-26.8.1-legacy.apkg"))
        XCTAssertTrue(inspection.report.canContinueScheduling)
        let library = try inspection.makeLibrary(scheduling: .preserveSource, scheduler: FSRSScheduler(), now: Date(), settings: settings)
        XCTAssertEqual(library.cards.filter { $0.schedule.phase == .review }.count, 1)
        let mature = try XCTUnwrap(library.cards.first { $0.schedule.phase == .review })
        let memory = try XCTUnwrap(try JSONSerialization.jsonObject(with: mature.schedule.payload) as? [String: Any])
        XCTAssertEqual(memory["stability"] as? Double, 12.3)
        XCTAssertEqual(memory["difficulty"] as? Double, 4.5)
        let directory = ProcessInfo.processInfo.environment["ENGRAM_ROUNDTRIP_DIR"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.temporaryDirectory.appendingPathComponent("engram-roundtrip-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if ProcessInfo.processInfo.environment["ENGRAM_ROUNDTRIP_DIR"] == nil { addTeardownBlock { try? FileManager.default.removeItem(at: directory) } }
        let before = library
        let personal = directory.appendingPathComponent("engram-personal.apkg"), sharing = directory.appendingPathComponent("engram-sharing.apkg")
        try AnkiPackageAdapter.export(snapshot: library, mode: .personalTransfer, to: personal)
        try AnkiPackageAdapter.export(snapshot: library, mode: .sharing, to: sharing)
        XCTAssertEqual(library, before)
        let restored = try AnkiPackageAdapter.inspect(url: personal)
        XCTAssertEqual(restored.namespace, library.libraryID)
        XCTAssertTrue(restored.report.canImport, restored.report.findings.map(\.message).joined(separator: "\n"))
        XCTAssertEqual(restored.report.historyCount, 1)
        let shared = try AnkiPackageAdapter.inspect(url: sharing)
        XCTAssertEqual(shared.report.historyCount, 0)
        let sharedLibrary = try shared.makeLibrary(scheduling: .contentOnly, scheduler: FSRSScheduler(), now: Date(), settings: settings)
        XCTAssertTrue(sharedLibrary.cards.allSatisfy { !$0.suspended })
        let backup = directory.appendingPathComponent("engram-native.engram")
        try NativeBackupAdapter.write(library, to: backup)
        XCTAssertEqual(try NativeBackupAdapter.read(from: backup), library)
        var native = library
        native.notes = native.notes.map { original in var note = original; note.origin = nil; return note }
        try AnkiPackageAdapter.export(snapshot: native, mode: .sharing, to: directory.appendingPathComponent("engram-created-sharing.apkg"))
        var reviewed = library
        let index = try XCTUnwrap(reviewed.cards.firstIndex { $0.schedule.phase == .new && !$0.suspended })
        let current = reviewed.cards[index], stamp = Date()
        let outcome = try XCTUnwrap(FSRSScheduler().outcomes(state: current.schedule, history: [], now: stamp, settings: settings)[.easy])
        reviewed.cards[index].schedule = outcome
        reviewed.reviews.append(ReviewEvent(id: "new-engram-review", cardID: current.id, deckID: current.deckID, sessionID: "test-session", rating: .easy, reviewedAt: stamp, committedAt: stamp, before: current.schedule, after: outcome))
        try AnkiPackageAdapter.export(snapshot: reviewed, mode: .personalTransfer, to: directory.appendingPathComponent("engram-reviewed.apkg"))
    }
    func testExportParentIncludesDescendantsAndRejectsMissingMedia() throws {
        let inspection = try AnkiPackageAdapter.inspect(url: fixture("anki-26.8.1-legacy.apkg"))
        var library = try inspection.makeLibrary(scheduling: .contentOnly, scheduler: FSRSScheduler(), now: Date(), settings: settings)
        let parent = try XCTUnwrap(library.decks.first { $0.name == "Science" })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".apkg")
        defer { try? FileManager.default.removeItem(at: url) }
        try AnkiPackageAdapter.export(snapshot: library, deckIDs: [parent.id], mode: .sharing, to: url)
        XCTAssertEqual(try AnkiPackageAdapter.inspect(url: url).report.cardCount, 5)
        let existing = try Data(contentsOf: url)
        library.media = []
        XCTAssertThrowsError(try AnkiPackageAdapter.export(snapshot: library, mode: .sharing, to: url))
        XCTAssertEqual(try Data(contentsOf: url), existing)
    }
    func testInvalidSchedulerPayloadFailsExportWithoutReplacingDestination() throws {
        let inspection = try AnkiPackageAdapter.inspect(url: fixture("anki-26.8.1-legacy.apkg"))
        var library = try inspection.makeLibrary(scheduling: .preserveSource, scheduler: FSRSScheduler(), now: Date(), settings: settings)
        let index = try XCTUnwrap(library.cards.firstIndex { $0.schedule.phase == .review })
        var value = try XCTUnwrap(try JSONSerialization.jsonObject(with: library.cards[index].schedule.payload) as? [String: Any])
        value["scheduledDays"] = 1e100
        library.cards[index].schedule.payload = try JSONSerialization.data(withJSONObject: value)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".apkg")
        defer { try? FileManager.default.removeItem(at: url) }
        let sentinel = Data("existing export".utf8); try sentinel.write(to: url)
        XCTAssertThrowsError(try AnkiPackageAdapter.export(snapshot: library, mode: .personalTransfer, to: url))
        XCTAssertEqual(try Data(contentsOf: url), sentinel)
    }
    func testCollectionCandidateMissingMediaAndModernRejection() throws {
        let inspection = try AnkiPackageAdapter.inspect(url: fixture("anki-26.8.1-legacy.colpkg"))
        XCTAssertTrue(inspection.report.canImport, inspection.report.findings.map(\.message).joined(separator: "\n"))
        XCTAssertTrue(inspection.report.format.contains("colpkg"))
        XCTAssertEqual(inspection.report.noteCount, 3)
        let missing = try AnkiPackageAdapter.inspect(url: fixture("anki-26.8.1-missing-media.apkg"))
        XCTAssertTrue(missing.report.findings.contains { $0.message.contains("Missing media") })
        XCTAssertThrowsError(try AnkiPackageAdapter.inspect(url: fixture("anki-26.8.1-modern.apkg")))
        XCTAssertThrowsError(try AnkiPackageAdapter.inspect(url: fixture("unsafe-path.apkg")))
    }
    func testUnsupportedTemplatePreservedInInspectionAndRejectedForImport() throws {
        var archive = try SafeArchive.read(fixture("anki-26.8.1-legacy.apkg"))
        let key = archive["collection.anki21"] != nil ? "collection.anki21" : "collection.anki2"
        archive[key] = try withTemporaryDatabase(archive[key]) { _, source in
            // Re-open the private temp fixture writable; production readers remain query-only.
            let db = try PackageDatabase(url: source, create: true)
            let col = try XCTUnwrap(try db.rows("SELECT models FROM col").first)
            var models = try jsonObject(col["models"]!)
            for (id, value) in models {
                var model = value as! [String: Any]; model["css"] = ".card { background: url(https://invalid.example); }"; models[id] = model
            }
            let json = String(decoding: try JSONSerialization.data(withJSONObject: models), as: UTF8.self)
            try db.execute("UPDATE col SET models=?", [json])
            return try Data(contentsOf: source)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".apkg")
        defer { try? FileManager.default.removeItem(at: url) }
        try SafeArchive.write(archive, to: url)
        let inspection = try AnkiPackageAdapter.inspect(url: url)
        XCTAssertFalse(inspection.report.canImport)
        XCTAssertThrowsError(try inspection.makeLibrary(scheduling: .contentOnly, scheduler: FSRSScheduler(), now: Date(), settings: settings))
    }
}
