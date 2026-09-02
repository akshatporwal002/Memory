import XCTest
import LearningCore
import StudyApplication
import PersistenceAdapters
import SchedulingAdapters

final class QueueAndMutationTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_788_393_600)

    func testParentDeckReportsChildLearningWait() async throws {
        let app = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let parent = try await app.createDeck(name: "Science")
        let child = try await app.createDeck(name: "Science::Cells")
        _ = try await app.saveNote(NoteDraft(deckID: child.id, front: "Q", back: "A"), now: now)
        let session = try await app.startSession(deckID: parent.id, now: now)
        let item = try XCTUnwrap(session.current)
        let shown = try await app.reveal(sessionID: session.id, presentationID: item.presentationID, now: now)
        try await app.grade(sessionID: session.id, presentationID: item.presentationID, rating: .again, mutationID: "child-again", now: now)
        let saved = try await app.snapshot()
        XCTAssertNil(saved.session?.current)
        XCTAssertEqual(saved.session?.nextLearningDue, shown.outcomes[.again]?.due)
        let refreshed = try await app.refreshSession(now: now.addingTimeInterval(61))
        XCTAssertEqual(refreshed?.current?.card.id, item.card.id)
    }

    func testRenameHierarchyNoOpAndCaseInsensitiveConflict() async throws {
        let app = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let parent = try await app.createDeck(name: "Science")
        _ = try await app.createDeck(name: "Science::Cells")
        try await app.renameDeck(id: parent.id, name: "Science")
        _ = try await app.createDeck(name: "Biology::cells")
        do { try await app.renameDeck(id: parent.id, name: "Biology"); XCTFail("Should reject case-insensitive descendant collision") } catch {}
        let saved = try await app.snapshot()
        XCTAssertTrue(saved.liveDecks.contains { $0.name == "Science::Cells" })
    }

    func testFourGradesAndDuplicatePresentation() async throws {
        for grade in Grade.allCases {
            let app = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
            let deck = try await app.createDeck(name: grade.label)
            _ = try await app.saveNote(NoteDraft(deckID: deck.id, front: "Q", back: "A"), now: now)
            let session = try await app.startSession(deckID: nil, now: now)
            let item = try XCTUnwrap(session.current)
            do { try await app.grade(sessionID: session.id, presentationID: item.presentationID, rating: grade, mutationID: "hidden", now: now); XCTFail("Must reveal first") } catch {}
            let shown = try await app.reveal(sessionID: session.id, presentationID: item.presentationID, now: now)
            async let first: Void = app.grade(sessionID: session.id, presentationID: item.presentationID, rating: grade, mutationID: "first", now: now)
            async let second: Void = app.grade(sessionID: session.id, presentationID: item.presentationID, rating: grade, mutationID: "second", now: now)
            _ = try? await first; _ = try? await second
            let saved = try await app.snapshot()
            XCTAssertEqual(saved.reviews.count, 1)
            XCTAssertEqual(saved.cards.first?.schedule, shown.outcomes[grade])
        }
    }

    func testDayBoundaryUsesPinnedZoneAndDailyLimitsUndo() async throws {
        var settings = StudySettings(timeZoneID: "Australia/Sydney")
        settings.newCardsPerDay = 1
        let app = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        try await app.updateSettings(settings)
        let deck = try await app.createDeck(name: "Daily")
        for index in 0..<2 { _ = try await app.saveNote(NoteDraft(deckID: deck.id, front: "Q \(index)", back: "A"), now: now) }
        let session = try await app.startSession(deckID: nil, now: now)
        XCTAssertEqual(session.queue.count, 1)
        let item = try XCTUnwrap(session.current)
        _ = try await app.reveal(sessionID: session.id, presentationID: item.presentationID, now: now)
        try await app.grade(sessionID: session.id, presentationID: item.presentationID, rating: .easy, mutationID: "limit", now: now)
        let saved = try await app.snapshot()
        XCTAssertEqual(QueuePolicy.dueCards(in: saved, deckID: nil, now: now).count, 0)
        try await app.undo(sessionID: session.id, now: now)
        let undone = try await app.snapshot()
        XCTAssertEqual(QueuePolicy.dueCards(in: undone, deckID: nil, now: now).count, 1)
        let format = ISO8601DateFormatter()
        let before = try XCTUnwrap(format.date(from: "2026-10-03T16:59:00Z")) // 03:59 daylight time
        let after = try XCTUnwrap(format.date(from: "2026-10-03T17:01:00Z"))
        XCTAssertNotEqual(QueuePolicy.dayStart(now: before, settings: settings), QueuePolicy.dayStart(now: after, settings: settings))
    }
}
