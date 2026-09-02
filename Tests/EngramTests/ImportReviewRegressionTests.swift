import XCTest
import LearningCore
import StudyApplication
import SchedulingAdapters
import PersistenceAdapters

/// Independent regressions from IMPORT-REVIEW.md. Written before implementation remediation.
final class ImportReviewRegressionTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_788_393_600)

    private func candidate(cloze: Bool = false) throws -> LibrarySnapshot {
        var result = LibrarySnapshot()
        let deck = Deck(id: "review-source:deck:1", name: "Imported")
        let note = Note(id: "review-source:note:guid", deckID: deck.id, kind: cloze ? .cloze : .basic,
            front: cloze ? "{{c1::First}} and {{c2::Second}}" : "Question", back: cloze ? "" : "Answer",
            origin: ImportOrigin(namespace: "review-source", noteID: "10", guid: "guid"))
        result.decks = [deck]; result.notes = [note]
        for ordinal in 0..<(cloze ? 2 : 1) {
            result.cards.append(StudyCard(id: "review-source:card:\(ordinal)", noteID: note.id, deckID: deck.id,
                ordinal: ordinal, schedule: try FSRSScheduler().initialState(now: now, settings: result.settings),
                sourceCardID: String(ordinal)))
            result.importedReviews.append(ImportedReview(id: "review-source:review:\(ordinal)",
                cardID: result.cards[ordinal].id, origin: "review-source", values: ["ease": "3", "ivl": "1"]))
        }
        return result
    }
    private func merge(_ candidate: LibrarySnapshot, into app: StudyService, policy: DuplicateImportPolicy = .updateContent) async throws {
        let revision = try await app.snapshot().revision
        _ = try await app.mergeImport(candidate, duplicates: policy, destinationDeckID: nil,
            expectedRevision: revision, preImportBackup: { _ in })
    }

    func testRecreatedSourceCardIDForSameOrdinalIsExplicitConflict() async throws {
        let app = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let initial = try candidate()
        try await merge(initial, into: app)
        let before = try await app.snapshot()
        var replacement = initial
        replacement.cards[0].id = "review-source:card:replacement"
        replacement.cards[0].sourceCardID = "replacement"
        replacement.importedReviews[0].id = "review-source:review:replacement"
        replacement.importedReviews[0].cardID = replacement.cards[0].id
        do {
            try await merge(replacement, into: app)
            XCTFail("A recreated source ID for an occupied note/ordinal must be refused before it duplicates a study card")
        } catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        let after = try await app.snapshot()
        XCTAssertEqual(after, before, "Conflict must leave note content, progress and history unchanged")
    }

    func testChangedHistoricalPayloadWithSameIDIsExplicitConflict() async throws {
        let app = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let initial = try candidate()
        try await merge(initial, into: app)
        let before = try await app.snapshot()
        var changed = initial
        changed.importedReviews[0].values["ease"] = "1"
        do {
            try await merge(changed, into: app)
            XCTFail("Changed history under the same ID must not be silently treated as an identical duplicate")
        } catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        let after = try await app.snapshot()
        XCTAssertEqual(after, before, "Rejected source evidence must not mutate the active library")
    }

    func testUpdateReactivatesReintroducedSourceSiblingAndPreservesProgress() async throws {
        let app = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let original = try candidate(cloze: true)
        try await merge(original, into: app)
        let session = try await app.startSession(deckID: nil, now: now)
        for index in 0..<2 {
            let snapshot = try await app.snapshot()
            let item = try XCTUnwrap(snapshot.session?.current)
            _ = try await app.reveal(sessionID: session.id, presentationID: item.presentationID, now: now)
            try await app.grade(sessionID: session.id, presentationID: item.presentationID, rating: .easy,
                mutationID: "local-progress-\(index)", now: now)
        }
        let studied = try await app.snapshot()
        let preserved = try XCTUnwrap(studied.cards.first { $0.ordinal == 1 }).schedule
        var removed = original
        removed.notes[0].front = "{{c1::First}} only"
        removed.cards.removeAll { $0.ordinal == 1 }
        removed.importedReviews.removeAll { $0.cardID == original.cards[1].id }
        try await merge(removed, into: app)
        let retired = try await app.snapshot()
        XCTAssertTrue(try XCTUnwrap(retired.cards.first { $0.ordinal == 1 }).retired)
        try await merge(original, into: app)
        let restored = try await app.snapshot()
        let sibling = try XCTUnwrap(restored.cards.first { $0.ordinal == 1 })
        XCTAssertFalse(sibling.retired, "A source sibling reintroduced by accepted content update must become live again")
        XCTAssertEqual(sibling.schedule, preserved, "Reactivation must not reset local learning progress")
        XCTAssertEqual(restored.reviews, studied.reviews)
    }

    func testKeepExistingRejectsNewSourceSiblingInsteadOfDroppingItsHistory() async throws {
        let app = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let expanded = try candidate(cloze: true)
        var initial = expanded
        initial.notes[0].front = "{{c1::First}} only"
        initial.cards.removeAll { $0.ordinal == 1 }
        initial.importedReviews.removeAll { $0.cardID == expanded.cards[1].id }
        try await merge(initial, into: app)
        let before = try await app.snapshot()
        do {
            try await merge(expanded, into: app, policy: .keepExisting)
            XCTFail("Keep-existing cannot silently drop a newly generated card and its source history; require update or skip")
        } catch {
            let message = error.localizedDescription.lowercased()
            XCTAssertTrue(message.contains("update") || message.contains("skip"), "The error must explain the available import choices")
        }
        let after = try await app.snapshot()
        XCTAssertEqual(after, before)
    }

    func testExactSourceDeckIDTakesPrecedenceOverAnotherDeckWithTheOldName() async throws {
        let app = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let original = try candidate()
        try await merge(original, into: app)
        try await app.renameDeck(id: original.decks[0].id, name: "Z renamed locally")
        let unrelated = try await app.createDeck(name: "Imported")
        try await merge(original, into: app)
        let result = try await app.snapshot()
        let note = try XCTUnwrap(result.notes.first { $0.id == original.notes[0].id })
        let card = try XCTUnwrap(result.cards.first { $0.id == original.cards[0].id })
        XCTAssertEqual(note.deckID, original.decks[0].id, "A stable deck ID must win over an unrelated matching name")
        XCTAssertEqual(card.deckID, original.decks[0].id)
        XCTAssertNotEqual(note.deckID, unrelated.id)
    }

    func testDeletedSourceDeckCannotSilentlyMapToUnrelatedRecreatedName() async throws {
        let app = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let original = try candidate()
        try await merge(original, into: app)
        try await app.deleteDeck(id: original.decks[0].id)
        _ = try await app.createDeck(name: "Imported")
        let before = try await app.snapshot()
        var incoming = original
        incoming.notes[0].id = "review-source:note:new-guid"
        incoming.notes[0].origin?.guid = "new-guid"
        incoming.notes[0].origin?.noteID = "new-id"
        incoming.cards[0].id = "review-source:card:new"
        incoming.cards[0].noteID = incoming.notes[0].id
        incoming.cards[0].sourceCardID = "new"
        incoming.importedReviews[0].id = "review-source:review:new"
        incoming.importedReviews[0].cardID = incoming.cards[0].id
        do {
            try await merge(incoming, into: app)
            XCTFail("A tombstoned source deck requires an explicit destination decision, even if its old name exists")
        } catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        let after = try await app.snapshot()
        XCTAssertEqual(after, before)
    }
}
