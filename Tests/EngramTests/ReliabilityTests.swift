import Foundation
import XCTest
import LearningCore
import StudyApplication
import PersistenceAdapters
import SchedulingAdapters

/// Independent acceptance checks for persisted learning state and adapter failure recovery.
final class ReliabilityTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_788_393_600)

    func testLearningGraduationLapseAndRelearningThroughApplication() async throws {
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let deck = try await service.createDeck(name: "Transitions")
        _ = try await service.saveNote(NoteDraft(deckID: deck.id, front: "Question", back: "Answer"), now: epoch)
        let initial = try await service.startSession(deckID: deck.id, now: epoch)
        let cardID = try XCTUnwrap(initial.current?.card.id)
        let cases: [(Grade, LearningPhase)] = [(.again, .learning), (.good, .learning), (.good, .review), (.again, .relearning), (.good, .review)]
        var time = epoch
        for (index, step) in cases.enumerated() {
            let refreshed = try await service.refreshSession(now: time)
            let session = try XCTUnwrap(refreshed)
            let presentation = try XCTUnwrap(session.current)
            XCTAssertEqual(session.id, initial.id)
            XCTAssertEqual(presentation.card.id, cardID)
            let preview = try await service.reveal(sessionID: session.id, presentationID: presentation.presentationID, now: time)
            let expected = try XCTUnwrap(preview.outcomes[step.0])
            try await service.grade(sessionID: session.id, presentationID: presentation.presentationID,
                rating: step.0, mutationID: "transition-\(index)", now: time)
            let saved = try await service.snapshot()
            let card = try XCTUnwrap(saved.cards.first)
            XCTAssertEqual(card.schedule, expected, "Preview and committed schedule must agree")
            XCTAssertEqual(card.schedule.phase, step.1)
            XCTAssertGreaterThan(card.schedule.due, time)
            XCTAssertEqual(saved.reviews.count, index + 1)
            XCTAssertEqual(saved.reviews.last?.before, presentation.card.schedule)
            XCTAssertEqual(saved.reviews.last?.after, expected)
            XCTAssertEqual(saved.reviews.last?.rating, step.0)
            XCTAssertTrue(QueuePolicy.dueCards(in: saved, deckID: deck.id, now: card.schedule.due.addingTimeInterval(-0.001)).isEmpty)
            XCTAssertEqual(QueuePolicy.dueCards(in: saved, deckID: deck.id, now: card.schedule.due).map(\.id), [cardID])
            if step.1 == .learning || step.1 == .relearning {
                XCTAssertEqual(saved.session?.nextLearningDue, card.schedule.due)
            }
            time = card.schedule.due
        }
    }

    func testSchedulerRejectsBackwardClockAndUnknownStateVersions() throws {
        let scheduler = FSRSScheduler()
        let settings = StudySettings(timeZoneID: "UTC")
        let initial = try scheduler.initialState(now: epoch, settings: settings)
        let reviewed = try XCTUnwrap(scheduler.outcomes(state: initial, history: [], now: epoch, settings: settings)[.easy])
        XCTAssertThrowsError(try scheduler.outcomes(state: reviewed, history: [], now: epoch.addingTimeInterval(-1), settings: settings)) { error in
            guard case EngramError.invalid = error else { return XCTFail("Expected backward-clock validation; got \(error)") }
        }
        var unknownID = reviewed; unknownID.schedulerID = "future-algorithm"
        var unknownSchema = reviewed; unknownSchema.schemaVersion = 999
        var unknownImplementation = reviewed; unknownImplementation.implementationVersion = "future-version"
        for state in [unknownID, unknownSchema, unknownImplementation] {
            XCTAssertThrowsError(try scheduler.outcomes(state: state, history: [], now: reviewed.due, settings: settings)) { error in
                guard case EngramError.unsupported = error else { return XCTFail("Unsupported state must require an explicit migration; got \(error)") }
            }
        }
    }

    func testUnsupportedSavedSchedulerCannotResetOrMutateLibraryOnReveal() async throws {
        let repository = MemoryRepository()
        let service = StudyService(repository: repository, scheduler: FSRSScheduler())
        let deck = try await service.createDeck(name: "Unknown scheduler")
        _ = try await service.saveNote(NoteDraft(deckID: deck.id, front: "Q", back: "A"), now: epoch)
        var library = try await repository.read()
        library.cards[0].schedule.schemaVersion = 999
        try await repository.commit(library, expectedRevision: library.revision)
        let session = try await service.startSession(deckID: nil, now: epoch)
        let presentation = try XCTUnwrap(session.current)
        let before = try await repository.read()
        do {
            _ = try await service.reveal(sessionID: session.id, presentationID: presentation.presentationID, now: epoch)
            XCTFail("Unsupported saved scheduler state must not silently become new")
        } catch {
            guard case EngramError.unsupported = error else { return XCTFail("Unexpected error: \(error)") }
        }
        let after = try await repository.read()
        XCTAssertEqual(after, before)
        XCTAssertEqual(after.cards[0].schedule.schemaVersion, 999)
        XCTAssertTrue(after.reviews.isEmpty)
    }

    func testReopenResumesExactRevealedPresentationAndRetainsPriorGrade() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.json")
        let service = StudyService(repository: try AtomicFileRepository(url: url), scheduler: FSRSScheduler())
        let deck = try await service.createDeck(name: "Resume")
        for index in 0..<2 {
            _ = try await service.saveNote(NoteDraft(deckID: deck.id, front: "Question \(index)", back: "Answer \(index)"), now: epoch)
        }
        let firstSession = try await service.startSession(deckID: deck.id, now: epoch)
        let first = try XCTUnwrap(firstSession.current)
        _ = try await service.reveal(sessionID: firstSession.id, presentationID: first.presentationID, now: epoch)
        try await service.grade(sessionID: firstSession.id, presentationID: first.presentationID, rating: .easy, mutationID: "saved-before-exit", now: epoch)
        let intermediate = try await service.snapshot()
        let second = try XCTUnwrap(intermediate.session?.current)
        let revealed = try await service.reveal(sessionID: firstSession.id, presentationID: second.presentationID, now: epoch.addingTimeInterval(10))
        let saved = try await service.snapshot()
        let reopened = StudyService(repository: try AtomicFileRepository(url: url), scheduler: FSRSScheduler())
        let resumed = try await reopened.startSession(deckID: deck.id, now: epoch.addingTimeInterval(30))
        XCTAssertEqual(resumed, saved.session)
        XCTAssertEqual(resumed.current, revealed)
        XCTAssertEqual(resumed.completed, 1)
        let beforeSecondGrade = try await reopened.snapshot()
        XCTAssertEqual(beforeSecondGrade.reviews.map(\.id), ["saved-before-exit"])
        try await reopened.grade(sessionID: resumed.id, presentationID: revealed.presentationID, rating: .good,
            mutationID: "saved-after-reopen", now: epoch.addingTimeInterval(30))
        let final = try await reopened.snapshot()
        XCTAssertEqual(final.reviews.count, 2)
        XCTAssertEqual(final.reviews.last?.after, revealed.outcomes[.good])
        XCTAssertEqual(final.reviews.first, saved.reviews.first)
    }

    func testProductionWriteFailureLeavesGradeAndScheduleUntouchedAndCanRetry() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("active", isDirectory: true)
        let rescuedDirectory = root.appendingPathComponent("preserved", isDirectory: true)
        let url = directory.appendingPathComponent("library.json")
        let repository = try AtomicFileRepository(url: url)
        let service = StudyService(repository: repository, scheduler: FSRSScheduler())
        let deck = try await service.createDeck(name: "Disk failure")
        _ = try await service.saveNote(NoteDraft(deckID: deck.id, front: "Q", back: "A"), now: epoch)
        let session = try await service.startSession(deckID: nil, now: epoch)
        let item = try XCTUnwrap(session.current)
        _ = try await service.reveal(sessionID: session.id, presentationID: item.presentationID, now: epoch)
        let before = try await service.snapshot()
        let originalBytes = try Data(contentsOf: url)
        // All paths are descendants of a unique test-owned temp directory. A regular file
        // in place of the parent directory forces a real filesystem write error on every OS.
        try FileManager.default.moveItem(at: directory, to: rescuedDirectory)
        try Data("intentional filesystem blocker".utf8).write(to: directory)
        do {
            try await service.grade(sessionID: session.id, presentationID: item.presentationID, rating: .good, mutationID: "retryable-grade", now: epoch)
            XCTFail("A grade must not be acknowledged when its durable write fails")
        } catch { /* The exact Foundation error code varies by platform. */ }
        let failed = try await repository.read()
        XCTAssertEqual(failed, before, "Failed IO must not advance the in-memory transaction")
        XCTAssertEqual(try Data(contentsOf: rescuedDirectory.appendingPathComponent("library.json")), originalBytes)
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.moveItem(at: rescuedDirectory, to: directory)
        try await service.grade(sessionID: session.id, presentationID: item.presentationID, rating: .good, mutationID: "retryable-grade", now: epoch)
        let recovered = try await AtomicFileRepository(url: url).read()
        XCTAssertEqual(recovered.reviews.map(\.id), ["retryable-grade"])
        XCTAssertEqual(recovered.cards.first?.schedule, before.session?.current?.outcomes[.good])
        XCTAssertEqual(recovered.revision, before.revision + 1)
    }

    func testCorruptDiskFileIsNeverOverwrittenByOpenOrStaleCommit() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.json")
        let repository = try AtomicFileRepository(url: url)
        var original = try await repository.read()
        original.decks.append(Deck(name: "Keep evidence"))
        try await repository.commit(original, expectedRevision: original.revision)
        let before = try await repository.read()
        let corrupt = Data("{\"schemaVersion\":1,\"decks\":[truncated".utf8)
        try corrupt.write(to: url)
        XCTAssertThrowsError(try AtomicFileRepository(url: url))
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
        var changed = before; changed.decks.append(Deck(name: "Must not overwrite"))
        do {
            try await repository.commit(changed, expectedRevision: before.revision)
            XCTFail("A stale process must not overwrite a corrupt library")
        } catch {}
        let after = try await repository.read()
        XCTAssertEqual(after, before)
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }

    func testClozeRetirementRestorationAndMovePreserveSchedulesAndHistory() async throws {
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let originalDeck = try await service.createDeck(name: "Original")
        let destinationDeck = try await service.createDeck(name: "Destination")
        let text = "{{c1::Paris}} is in {{c2::France}}."
        let note = try await service.saveNote(NoteDraft(deckID: originalDeck.id, kind: .cloze, front: text), now: epoch)
        let session = try await service.startSession(deckID: originalDeck.id, now: epoch)
        let reviewed = try XCTUnwrap(session.current)
        _ = try await service.reveal(sessionID: session.id, presentationID: reviewed.presentationID, now: epoch)
        try await service.grade(sessionID: session.id, presentationID: reviewed.presentationID, rating: .easy, mutationID: "cloze-history", now: epoch)
        let graded = try await service.snapshot()
        let gradedCard = try XCTUnwrap(graded.cards.first { $0.id == reviewed.card.id })
        let remaining = reviewed.card.ordinal == 0 ? "Paris is in {{c2::France}}." : "{{c1::Paris}} is in France."
        _ = try await service.saveNote(NoteDraft(id: note.id, deckID: originalDeck.id, kind: .cloze, front: remaining), now: epoch)
        let retired = try await service.snapshot()
        XCTAssertEqual(retired.cards.first { $0.id == gradedCard.id }?.retired, true)
        XCTAssertEqual(retired.cards.first { $0.id == gradedCard.id }?.schedule, gradedCard.schedule)
        XCTAssertEqual(retired.reviews, graded.reviews)
        XCTAssertFalse(QueuePolicy.dueCards(in: retired, deckID: nil, now: gradedCard.schedule.due).contains { $0.id == gradedCard.id })
        _ = try await service.saveNote(NoteDraft(id: note.id, deckID: destinationDeck.id, kind: .cloze, front: text + " Updated.", tags: ["geography"], source: "Atlas p. 2"), now: epoch)
        let restored = try await service.snapshot()
        XCTAssertEqual(Set(restored.cards.map(\.id)), Set(graded.cards.map(\.id)))
        XCTAssertTrue(restored.cards.allSatisfy { !$0.retired && $0.deckID == destinationDeck.id })
        XCTAssertEqual(restored.cards.first { $0.id == gradedCard.id }?.schedule, gradedCard.schedule)
        XCTAssertEqual(restored.reviews, graded.reviews)
        XCTAssertEqual(restored.notes.first?.source, "Atlas p. 2")
        XCTAssertTrue(QueuePolicy.dueCards(in: restored, deckID: originalDeck.id, now: gradedCard.schedule.due).isEmpty)
    }

    func testEditingThenDeletingPresentedNoteRejectsStaleGradesWithoutLosingHistory() async throws {
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let deck = try await service.createDeck(name: "Invalidated presentation")
        let note = try await service.saveNote(NoteDraft(deckID: deck.id, front: "Q", back: "A"), now: epoch)
        let session = try await service.startSession(deckID: nil, now: epoch)
        let item = try XCTUnwrap(session.current)
        _ = try await service.reveal(sessionID: session.id, presentationID: item.presentationID, now: epoch)
        _ = try await service.saveNote(NoteDraft(id: note.id, deckID: deck.id, front: "Edited Q", back: "Edited A"), now: epoch)
        let edited = try await service.snapshot()
        XCTAssertEqual(edited.cards.first?.schedule, item.card.schedule)
        do {
            try await service.grade(sessionID: session.id, presentationID: item.presentationID, rating: .good, mutationID: "stale-edit", now: epoch)
            XCTFail("An old revealed prompt cannot grade newly edited content")
        } catch {}
        let afterStaleEdit = try await service.snapshot()
        XCTAssertEqual(afterStaleEdit, edited)
        let refreshed = try await service.refreshSession(now: epoch)
        let newItem = try XCTUnwrap(refreshed?.current)
        _ = try await service.reveal(sessionID: session.id, presentationID: newItem.presentationID, now: epoch)
        try await service.grade(sessionID: session.id, presentationID: newItem.presentationID, rating: .again, mutationID: "preserved-history", now: epoch)
        let reviewed = try await service.snapshot()
        let due = try XCTUnwrap(reviewed.cards.first?.schedule.due)
        let nextSession = try await service.refreshSession(now: due)
        let nextItem = try XCTUnwrap(nextSession?.current)
        _ = try await service.reveal(sessionID: session.id, presentationID: nextItem.presentationID, now: due)
        try await service.deleteNote(id: note.id)
        let deleted = try await service.snapshot()
        do {
            try await service.grade(sessionID: session.id, presentationID: nextItem.presentationID, rating: .good, mutationID: "stale-delete", now: due)
            XCTFail("A deleted card must not receive another grade")
        } catch {}
        let final = try await service.snapshot()
        XCTAssertEqual(final, deleted)
        XCTAssertEqual(final.reviews, reviewed.reviews)
        XCTAssertEqual(final.notes.first?.deleted, true)
        XCTAssertTrue(final.cards.allSatisfy(\.retired))
        XCTAssertTrue(QueuePolicy.dueCards(in: final, deckID: nil, now: due).isEmpty)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("EngramReliability-" + UUID().uuidString, isDirectory: true)
    }
}
