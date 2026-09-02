import XCTest
import LearningCore
import StudyApplication
import SchedulingAdapters
import PersistenceAdapters

final class ImportTransactionTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_788_393_600)
    func candidate() throws -> LibrarySnapshot {
        var result = LibrarySnapshot()
        result.decks = [Deck(id: "source:deck:1", name: "Imported")]
        result.notes = [Note(id: "source:note:guid", deckID: result.decks[0].id, kind: .basic, front: "Original", back: "Answer")]
        result.cards = [StudyCard(id: "source:card:1", noteID: result.notes[0].id, deckID: result.decks[0].id,
            schedule: try FSRSScheduler().initialState(now: now, settings: result.settings))]
        result.importedReviews = [ImportedReview(id: "source:rev:1", cardID: result.cards[0].id, origin: "source", values: ["ease": "0", "ivl": "-60"])]
        result.media = [MediaFile(name: "image.png", data: Data([1, 2, 3]))]
        return result
    }
    func testImportBackupFailureLeavesExistingLibraryUntouched() async throws {
        let app = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        _ = try await app.createDeck(name: "Personal")
        let before = try await app.snapshot()
        do {
            _ = try await app.mergeImport(candidate(), duplicates: .keepExisting, destinationDeckID: nil, expectedRevision: before.revision,
                preImportBackup: { _ in throw EngramError.storage("Backup disk full") })
            XCTFail("Backup must precede import commit")
        } catch {}
        let after = try await app.snapshot()
        XCTAssertEqual(before, after)
    }
    func testRepeatedImportUpdatePreservesLocalGradesAndAddsNoDuplicates() async throws {
        let app = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let original = try candidate()
        let before = try await app.snapshot()
        _ = try await app.mergeImport(original, duplicates: .keepExisting, destinationDeckID: nil, expectedRevision: before.revision, preImportBackup: { _ in })
        let session = try await app.startSession(deckID: nil, now: now)
        let item = try XCTUnwrap(session.current)
        _ = try await app.reveal(sessionID: session.id, presentationID: item.presentationID, now: now)
        try await app.grade(sessionID: session.id, presentationID: item.presentationID, rating: .easy, mutationID: "local-grade", now: now)
        let studied = try await app.snapshot()
        var changed = original; changed.notes[0].front = "Updated"
        let summary = try await app.mergeImport(changed, duplicates: .updateContent, destinationDeckID: nil, expectedRevision: studied.revision, preImportBackup: { _ in })
        let updated = try await app.snapshot()
        XCTAssertEqual(summary.updatedNotes, 1)
        XCTAssertEqual(updated.notes.count, 1)
        XCTAssertEqual(updated.cards.count, 1)
        XCTAssertEqual(updated.importedReviews.count, 1)
        XCTAssertEqual(updated.media.count, 1)
        XCTAssertEqual(updated.notes[0].front, "Updated")
        XCTAssertEqual(updated.cards[0].schedule, studied.cards[0].schedule)
        XCTAssertEqual(updated.reviews, studied.reviews)
        _ = try await app.mergeImport(original, duplicates: .skipExisting, destinationDeckID: nil, expectedRevision: updated.revision, preImportBackup: { _ in })
        let skipped = try await app.snapshot()
        XCTAssertEqual(skipped.notes[0].front, "Updated")
    }
    func testMediaCollisionAndStaleInspectionDoNotMutateLibrary() async throws {
        let app = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let before = try await app.snapshot()
        _ = try await app.mergeImport(candidate(), duplicates: .keepExisting, destinationDeckID: nil, expectedRevision: before.revision, preImportBackup: { _ in })
        let existing = try await app.snapshot()
        var bad = try candidate(); bad.media[0].data = Data([9])
        do { _ = try await app.mergeImport(bad, duplicates: .updateContent, destinationDeckID: nil, expectedRevision: existing.revision, preImportBackup: { _ in }); XCTFail("Conflicting media must not overwrite") } catch {}
        do { _ = try await app.mergeImport(candidate(), duplicates: .keepExisting, destinationDeckID: nil, expectedRevision: before.revision, preImportBackup: { _ in }); XCTFail("Stale inspection") } catch {}
        let after = try await app.snapshot(); XCTAssertEqual(existing, after)
    }
    func testConcurrentChangeDuringBackupIsRetainedAndImportRejected() async throws {
        let app = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let before = try await app.snapshot()
        do {
            _ = try await app.mergeImport(candidate(), duplicates: .keepExisting, destinationDeckID: nil, expectedRevision: before.revision,
                preImportBackup: { saved in
                    XCTAssertEqual(saved, before)
                    _ = try await app.createDeck(name: "Saved while backing up")
                })
            XCTFail("Import must not overwrite a concurrent mutation")
        } catch { XCTAssertEqual(error as? EngramError, .conflict) }
        let after = try await app.snapshot()
        XCTAssertEqual(after.liveDecks.map(\.name), ["Saved while backing up"])
        XCTAssertTrue(after.notes.isEmpty)
    }
    func testCancellationAfterBackupLeavesLibraryUnchanged() async throws {
        let app = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let before = try await app.snapshot(), incoming = try candidate()
        let task = Task {
            try await app.mergeImport(incoming, duplicates: .keepExisting, destinationDeckID: nil, expectedRevision: before.revision,
                preImportBackup: { _ in withUnsafeCurrentTask { $0?.cancel() } })
        }
        do { _ = try await task.value; XCTFail("Cancelled import must not commit") }
        catch { XCTAssertTrue(error is CancellationError) }
        let after = try await app.snapshot(); XCTAssertEqual(after, before)
    }
    func testCommitFailureAfterSuccessfulBackupLeavesLibraryUnchanged() async throws {
        let repository = MemoryRepository()
        let app = StudyService(repository: repository, scheduler: FSRSScheduler())
        let before = try await app.snapshot()
        do {
            _ = try await app.mergeImport(candidate(), duplicates: .keepExisting, destinationDeckID: nil, expectedRevision: before.revision,
                preImportBackup: { saved in XCTAssertEqual(saved, before); await repository.failNextCommit() })
            XCTFail("Failed commit must not change active data")
        } catch {}
        let after = try await app.snapshot(); XCTAssertEqual(after, before)
    }
    func testNativeEvidenceCannotBeSilentlyDroppedByAnkiMerge() async throws {
        let app = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let before = try await app.snapshot()
        var incoming = try candidate()
        let card = incoming.cards[0]
        incoming.reviews = [ReviewEvent(id: "native-grade", cardID: card.id, deckID: card.deckID, sessionID: "native-session", rating: .good,
            reviewedAt: now, committedAt: now, before: card.schedule, after: card.schedule)]
        do {
            _ = try await app.mergeImport(incoming, duplicates: .keepExisting, destinationDeckID: nil, expectedRevision: before.revision, preImportBackup: { _ in })
            XCTFail("Native records require complete restore, not Anki merge")
        } catch {}
        let after = try await app.snapshot(); XCTAssertEqual(after, before)
    }
    func testOwnAnkiExportCannotDuplicateOriginalNativeLibrary() async throws {
        let original = try candidate()
        let app = StudyService(repository: MemoryRepository(initial: original), scheduler: FSRSScheduler())
        var incoming = original
        incoming.notes[0].id += ":reimport"
        incoming.notes[0].origin = ImportOrigin(namespace: "explicit-alternate-name", noteID: "123", guid: "guid",
            metadata: ["engramSourceLibraryID": original.libraryID])
        incoming.cards[0].id += ":reimport"; incoming.cards[0].noteID = incoming.notes[0].id
        incoming.importedReviews[0].id += ":reimport"; incoming.importedReviews[0].cardID = incoming.cards[0].id
        do {
            _ = try await app.mergeImport(incoming, duplicates: .keepExisting, destinationDeckID: nil, expectedRevision: original.revision,
                preImportBackup: { _ in XCTFail("Same-library package should be refused before backup") })
            XCTFail("Own export cannot safely merge native identities/history back into itself")
        } catch { XCTAssertTrue(error.localizedDescription.lowercased().contains("backup")) }
        let after = try await app.snapshot(); XCTAssertEqual(after, original)
    }
}
