import Foundation
import XCTest
import LearningCore
import StudyApplication
import PersistenceAdapters
import SchedulingAdapters

final class DeckMemoryOutlookTests: XCTestCase {
    private struct ConstantEstimator: MemoryEstimating {
        func recallProbability(state: ScheduleState, now: Date, settings: StudySettings) -> Double? { 0.91 }
    }

    func testOlderDeckWithoutTargetStillDecodes() throws {
        let data = Data(#"{"id":"deck","name":"Cloud","deleted":false}"#.utf8)
        let deck = try JSONDecoder().decode(Deck.self, from: data)
        XCTAssertNil(deck.desiredRetention)
    }

    func testOutlookUsesDeckTargetAndAccountsForAllCards() throws {
        let now = Date(timeIntervalSince1970: 1_788_393_600)
        var library = LibrarySnapshot()
        var deck = Deck(id: "deck", name: "Cloud")
        deck.desiredRetention = 0.95
        library.decks = [deck]
        library.notes = [Note(id: "one", deckID: deck.id, kind: .basic, front: "What is S3?", back: "Object storage"),
                         Note(id: "two", deckID: deck.id, kind: .basic, front: "What is EC2?", back: "Compute")]
        let initial = try FSRSScheduler().initialState(now: now, settings: library.settings)
        var reviewed = initial
        reviewed.phase = .review
        reviewed.due = now.addingTimeInterval(2 * 86_400)
        library.cards = [StudyCard(id: "studied", noteID: "one", deckID: deck.id, schedule: reviewed),
                         StudyCard(id: "new", noteID: "two", deckID: deck.id, schedule: initial)]
        let outlook = DeckMemoryOutlook.make(deck: deck, library: library, now: now, estimator: ConstantEstimator())
        XCTAssertEqual(outlook.target, 0.95)
        XCTAssertFalse(outlook.inheritsTarget)
        XCTAssertEqual(outlook.aboveTarget, 0)
        XCTAssertEqual(outlook.belowTarget, 1)
        XCTAssertEqual(outlook.newCount, 1)
        XCTAssertEqual(outlook.average.count, outlook.sampleDates.count)
        XCTAssertLessThanOrEqual(outlook.average.count, 65)
        XCTAssertEqual(outlook.sampleDates.first, now)
        XCTAssertEqual(outlook.sampleDates.last, DeckMemoryOutlook.forecastEnd(examDate: nil, now: now))
        XCTAssertEqual(outlook.cards.first?.prompt, "What is S3?")
        XCTAssertEqual(outlook.nextPlannedReview,reviewed.due)
        XCTAssertEqual(outlook.scheduledWithinWeek,1)
        let activity = ActivitySummary.make(in: library, period: .all, now: now, estimator: ConstantEstimator())
        XCTAssertEqual(activity.decks.first?.counts[.belowTarget], 1)
    }

    func testCalendarMonthWindowsAndBoundaries() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3))!
        let start = calendar.date(byAdding: .month, value: -1, to: now)!
        let end = calendar.date(byAdding: .year, value: 1, to: now)!
        let first = MemoryGraphWindow.interval(anchor: now, months: 2, start: start, end: end, calendar: calendar)
        XCTAssertEqual(first.start, now)
        XCTAssertEqual(first.end, calendar.date(from: DateComponents(year: 2026, month: 12, day: 3)))
        let next = MemoryGraphWindow.interval(anchor: first.end, months: 2, start: start, end: end, calendar: calendar)
        XCTAssertEqual(next.start, first.end)
        XCTAssertEqual(next.end, calendar.date(from: DateComponents(year: 2027, month: 2, day: 3)))
        let last = MemoryGraphWindow.interval(anchor: end, months: 2, start: start, end: end, calendar: calendar)
        XCTAssertEqual(last.end, end)
        XCTAssertLessThan(last.start, last.end)
        XCTAssertEqual(MemoryGraphWindow.interval(anchor: start.addingTimeInterval(-100), months: 2, start: start, end: end, calendar: calendar).start, start)
        XCTAssertEqual(MemoryGraphWindow.interval(anchor: now, months: 0, start: start, end: end, calendar: calendar), DateInterval(start: start, end: end))
    }

    func testPlateauAxisZoomAndSafeFallback() {
        XCTAssertEqual(DeckMemoryOutlook.recallAxisDomain(plateau: 0.95), 85...100)
        XCTAssertEqual(DeckMemoryOutlook.recallAxisDomain(plateau: 1), 90...100)
        XCTAssertEqual(DeckMemoryOutlook.recallAxisDomain(plateau: 0.05), 0...100)
        XCTAssertEqual(DeckMemoryOutlook.recallAxisDomain(plateau: .nan), 0...100)
        XCTAssertEqual(DeckMemoryOutlook.recallAxisDomain(plateau: nil), 0...100)
    }

    func testPlannedReviewsRaiseRecallWithoutChangingStoredSchedule() throws {
        let now = Date()
        let scheduler = FSRSScheduler()
        var library = LibrarySnapshot()
        let deck = Deck(id: "d", name: "Forecast")
        library.decks = [deck]
        library.notes = [Note(id: "n", deckID: "d", kind: .basic, front: "Question", back: "Answer")]
        let initial = try scheduler.initialState(now: now.addingTimeInterval(-10 * 86_400), settings: library.settings)
        let state = try XCTUnwrap(scheduler.outcomes(state: initial, history: [], now: now.addingTimeInterval(-10 * 86_400), settings: library.settings)[.easy])
        library.cards = [StudyCard(id: "c", noteID: "n", deckID: "d", schedule: state)]
        let outlook = DeckMemoryOutlook.make(deck: deck, library: library, now: now, estimator: scheduler, scheduler: scheduler)
        let date = try XCTUnwrap(outlook.reviewDates.first)
        let before = try XCTUnwrap(outlook.projection.last { $0.date < date })
        let after = try XCTUnwrap(outlook.projection.first { $0.date == date })
        XCTAssertGreaterThan(after.probability, before.probability)
        XCTAssertEqual(after.probability, 1, accuracy: 0.001)
        XCTAssertEqual(library.cards[0].schedule, state)
        XCTAssertTrue(library.reviews.isEmpty)
        library.decks[0].studySuspended = true
        let paused = DeckMemoryOutlook.make(deck: library.decks[0], library: library, now: now, estimator: scheduler, scheduler: scheduler)
        XCTAssertTrue(paused.reviewDates.isEmpty)
    }

    func testHistoryBeginsWithRecordedEvidence() throws {
        let now = Date()
        let created = now.addingTimeInterval(-30 * 86_400)
        let reviewedAt = now.addingTimeInterval(-10 * 86_400)
        let deck = Deck(id: "d", name: "History", createdAt: created)
        var library = LibrarySnapshot(); library.decks = [deck]
        library.notes = [Note(id: "n", deckID: deck.id, kind: .basic, front: "Q", back: "A")]
        var state = try FSRSScheduler().initialState(now: reviewedAt, settings: library.settings)
        state.phase = .review
        library.cards = [StudyCard(id: "c", noteID: "n", deckID: deck.id, schedule: state)]
        library.reviews = [ReviewEvent(id: "r", cardID: "c", deckID: deck.id, sessionID: "s", rating: .good, reviewedAt: reviewedAt, committedAt: reviewedAt, before: state, after: state)]
        let outlook = DeckMemoryOutlook.make(deck: deck, library: library, now: now, estimator: ConstantEstimator())
        XCTAssertEqual(outlook.startDate, created)
        XCTAssertEqual(outlook.history.map(\.date), [reviewedAt])
        XCTAssertEqual(outlook.cards.first?.history.first?.date, reviewedAt)
        XCTAssertEqual(outlook.sampleDates.first, now)
    }
    func testRollingYearAndCreationStart() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3))!
        XCTAssertEqual(DeckMemoryOutlook.forecastEnd(examDate: nil, now: now, calendar: calendar), calendar.date(from: DateComponents(year: 2027, month: 10, day: 3)))
        var deck = Deck(id: "d", name: "Created", createdAt: now.addingTimeInterval(-30 * 86_400))
        var library = LibrarySnapshot(); library.decks = [deck]
        let outlook = DeckMemoryOutlook.make(deck: deck, library: library, now: now, estimator: ConstantEstimator())
        XCTAssertEqual(outlook.startDate, deck.createdAt)
        XCTAssertTrue(outlook.history.isEmpty)
        deck.createdAt = nil
        XCTAssertEqual(DeckMemoryOutlook.make(deck: deck, library: library, now: now, estimator: nil).startDate, now)
    }
    func testDeckSuspensionPreservesCardsAndDescendants() async throws {
        let now = Date()
        let repository = MemoryRepository()
        let app = StudyService(repository: repository, scheduler: FSRSScheduler())
        let parent = try await app.createDeck(name: "Cloud")
        let child = try await app.createDeck(name: "Cloud::AWS")
        var library = try await app.snapshot()
        let note = Note(id: "n", deckID: child.id, kind: .basic, front: "Question", back: "Answer")
        library.notes = [note]
        let state = try FSRSScheduler().initialState(now: now, settings: library.settings)
        library.cards = [StudyCard(id: "active", noteID: note.id, deckID: child.id, schedule: state), StudyCard(id: "paused", noteID: note.id, deckID: child.id, schedule: state, suspended: true)]
        try await repository.commit(library, expectedRevision: library.revision)
        _ = try await app.startSession(deckID: nil, now: now)
        try await app.setDeckSuspended(id: parent.id, suspended: true)
        var snapshot = try await app.snapshot()
        XCTAssertTrue(QueuePolicy.dueCards(in: snapshot, deckID: nil, now: now).isEmpty)
        XCTAssertNil(snapshot.session?.current)
        XCTAssertEqual(snapshot.cards, library.cards)
        try await app.setDeckSuspended(id: parent.id, suspended: false)
        snapshot = try await app.snapshot()
        XCTAssertEqual(QueuePolicy.dueCards(in: snapshot, deckID: nil, now: now).map(\.id), ["active"])
        XCTAssertTrue(snapshot.cards.first(where: { $0.id == "paused" })!.suspended)
    }

    func testExamDateHorizonAndPersistence() async throws {
        let now = Date(timeIntervalSince1970: 1_788_393_600)
        let future = now.addingTimeInterval(120 * 86_400)
        XCTAssertEqual(DeckMemoryOutlook.forecastEnd(examDate: future, now: now), future)
        XCTAssertEqual(DeckMemoryOutlook.forecastEnd(examDate: now.addingTimeInterval(-1), now: now), DeckMemoryOutlook.forecastEnd(examDate: nil, now: now))
        let app = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let deck = try await app.createDeck(name: "Exam")
        try await app.setDeckExamDate(id: deck.id, date: future)
        var snapshot = try await app.snapshot()
        XCTAssertEqual(snapshot.decks.first?.examDate, future)
        try await app.setDeckExamDate(id: deck.id, date: nil)
        snapshot = try await app.snapshot()
        XCTAssertNil(snapshot.decks.first?.examDate)
    }

    func testDeckRetentionPersistsAndCanReturnToDefault() async throws {
        let app = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let deck = try await app.createDeck(name: "Cloud")
        try await app.setDeckRetention(id: deck.id, desiredRetention: 0.94)
        var snapshot = try await app.snapshot()
        XCTAssertEqual(snapshot.decks.first?.desiredRetention, 0.94)
        try await app.setDeckRetention(id: deck.id, desiredRetention: nil)
        snapshot = try await app.snapshot()
        XCTAssertNil(snapshot.decks.first?.desiredRetention)
        do { try await app.setDeckRetention(id: deck.id, desiredRetention: 1.0); XCTFail("Expected invalid target") }
        catch {
            snapshot = try await app.snapshot()
            XCTAssertNil(snapshot.decks.first?.desiredRetention)
        }
    }
}
