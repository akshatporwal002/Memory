import XCTest
import LearningCore
import StudyApplication
import SchedulingAdapters

final class ActivityTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_788_393_600)
    struct Estimate: MemoryEstimating {
        let value: Double?
        func recallProbability(state: ScheduleState, now: Date, settings: StudySettings) -> Double? { value }
    }
    func library() throws -> LibrarySnapshot {
        var result = LibrarySnapshot()
        result.decks = [Deck(id: "parent", name: "AWS"), Deck(id: "child", name: "AWS::Storage")]
        result.notes = [Note(id: "note", deckID: "child", kind: .basic, front: "Question", back: "Answer")]
        result.cards = [StudyCard(id: "card", noteID: "note", deckID: "child", schedule: try FSRSScheduler().initialState(now: now, settings: result.settings))]
        return result
    }
    func event(_ id: String, grade: Grade, time: Date, state: ScheduleState) -> ReviewEvent {
        ReviewEvent(id: id, cardID: "card", deckID: "child", sessionID: "session", rating: grade,
                    reviewedAt: time, committedAt: time, before: state, after: state)
    }
    func testBucketsThresholdsAndOwnDeckCounts() throws {
        var data = try library()
        data.cards[0].schedule.phase = .review
        for (value, expected): (Double?, MemoryBucket) in [(0.9, .atTarget), (0.899, .belowTarget), (nil, .unavailable), (.nan, .unavailable), (1.1, .unavailable)] {
            let result = ActivitySummary.make(in: data, period: .today, now: now, estimator: Estimate(value: value))
            XCTAssertEqual(result.decks.first?.id, "child")
            XCTAssertEqual(result.decks.first?.counts[expected], 1)
            XCTAssertEqual(result.decks.last?.questions.count, 0)
            XCTAssertEqual(result.dueCount, 1)
        }
        data.cards[0].schedule.phase = .new
        var result = ActivitySummary.make(in: data, period: .today, now: now, estimator: nil)
        XCTAssertEqual(result.dueCount, 0)
        XCTAssertEqual(result.decks.first { $0.id == "child" }?.counts[.unstudied], 1)
        data.cards[0].schedule.phase = .relearning
        result = ActivitySummary.make(in: data, period: .today, now: now, estimator: nil)
        XCTAssertEqual(result.decks.first?.counts[.learning], 1)
    }
    func testAttemptsUndoFiltersAndImportedEvidence() throws {
        var data = try library()
        data.cards[0].schedule.phase = .review
        let state = data.cards[0].schedule
        data.reviews = [event("again", grade: .again, time: now.addingTimeInterval(-30), state: state),
                        event("good", grade: .good, time: now.addingTimeInterval(-20), state: state),
                        event("undo", grade: .easy, time: now.addingTimeInterval(-10), state: state),
                        event("future", grade: .hard, time: now.addingTimeInterval(20), state: state)]
        data.corrections = [ReviewCorrection(reviewID: "undo", createdAt: now)]
        data.importedReviews = [ImportedReview(id: "import", cardID: "card", origin: "Anki", values: ["ease": "1"])]
        data.settings.reviewsPerDay = 0
        let result = ActivitySummary.make(in: data, period: .today, now: now, estimator: nil)
        XCTAssertEqual(result.reviewedCount, 1)
        XCTAssertEqual(result.attemptCount, 2)
        let question = try XCTUnwrap(result.decks.first?.questions.first)
        XCTAssertEqual(question.attempts.map(\.id), ["good", "again"])
        XCTAssertEqual(question.outcome, "Recalled")
        XCTAssertTrue(question.matches(.all)); XCTAssertTrue(question.matches(.due)); XCTAssertTrue(question.matches(.reviewed))
        XCTAssertFalse(question.matches(.unstudied)); XCTAssertEqual(result.dueCount, 1)
    }
    func testExcludedCardsAndEmptyLibrary() throws {
        var data = try library()
        data.cards[0].suspended = true
        var result = ActivitySummary.make(in: data, period: .all, now: now, estimator: nil)
        XCTAssertEqual(result.decks.first { $0.id == "child" }?.suspendedCount, 1)
        XCTAssertEqual(result.decks.flatMap(\.questions).count, 0)
        data.cards[0].suspended = false; data.notes[0].deleted = true
        result = ActivitySummary.make(in: data, period: .all, now: now, estimator: nil)
        XCTAssertEqual(result.decks.flatMap(\.questions).count, 0)
        XCTAssertTrue(ActivitySummary.make(in: LibrarySnapshot(), period: .today, now: now, estimator: nil).decks.isEmpty)
    }
    func testPeriodsUseStudyDayAcrossDST() throws {
        let formatter = ISO8601DateFormatter()
        let date = try XCTUnwrap(formatter.date(from: "2026-03-09T07:30:00Z")) // 03:30 New York, before 04:00 boundary
        var settings = StudySettings(); settings.timeZoneID = "America/New_York"; settings.dayStartsAtHour = 4
        XCTAssertEqual(ActivityPeriod.today.start(now: date, settings: settings), formatter.date(from: "2026-03-08T08:00:00Z"))
        XCTAssertEqual(ActivityPeriod.week.start(now: date, settings: settings), formatter.date(from: "2026-03-02T09:00:00Z"))
        XCTAssertEqual(ActivityPeriod.month.start(now: date, settings: settings), formatter.date(from: "2026-02-07T09:00:00Z"))
        XCTAssertEqual(ActivityPeriod.all.start(now: date, settings: settings), .distantPast)
    }
    func testPeriodChangesHistoryWithoutChangingCurrentMemory() throws {
        var data = try library()
        data.cards[0].schedule.phase = .review
        let yesterday = ActivityPeriod.today.start(now: now, settings: data.settings).addingTimeInterval(-1)
        data.reviews = [event("old", grade: .hard, time: yesterday, state: data.cards[0].schedule)]
        let today = ActivitySummary.make(in: data, period: .today, now: now, estimator: Estimate(value: 0.95))
        let week = ActivitySummary.make(in: data, period: .week, now: now, estimator: Estimate(value: 0.95))
        XCTAssertEqual(today.attemptCount, 0); XCTAssertEqual(week.attemptCount, 1)
        XCTAssertEqual(today.decks.first?.counts, week.decks.first?.counts)
        XCTAssertEqual(today.dueCount, week.dueCount)
        XCTAssertEqual(today.decks.first?.questions.first?.outcome, "Not reviewed in this period")
        XCTAssertEqual(week.decks.first?.questions.first?.outcome, "Recalled with difficulty")
    }
    func testLargeDeckKeepsEveryCardAndRendersClozeAndReverse() throws {
        var data = try library()
        let state = data.cards[0].schedule
        data.notes[0].kind = .reversed
        data.cards = (0..<61).map { StudyCard(id: "card-\($0)", noteID: "note", deckID: "child", ordinal: $0 % 2, schedule: state) }
        var result = ActivitySummary.make(in: data, period: .all, now: now, estimator: nil)
        let questions = try XCTUnwrap(result.decks.first { $0.id == "child" }?.questions)
        XCTAssertEqual(questions.count, 61)
        XCTAssertEqual(questions.first { $0.id == "card-1" }?.prompt, "Answer")
        XCTAssertEqual(questions.first { $0.id == "card-1" }?.answer, "Question")
        data.cards = [StudyCard(id: "cloze", noteID: "note", deckID: "child", ordinal: 0, schedule: state)]
        data.notes[0].kind = .cloze; data.notes[0].front = "S3 stores {{c1::objects}}."
        result = ActivitySummary.make(in: data, period: .all, now: now, estimator: nil)
        let cloze = try XCTUnwrap(result.decks.first { $0.id == "child" }?.questions.first)
        XCTAssertFalse(cloze.prompt.contains("objects"))
        XCTAssertTrue(cloze.answer.contains("objects"))
    }

    func testRealEstimatorDeclinesNewInvalidAndFutureStates() throws {
        let scheduler = FSRSScheduler(), settings = StudySettings()
        let initial = try scheduler.initialState(now: now, settings: settings)
        XCTAssertNil(scheduler.recallProbability(state: initial, now: now, settings: settings))
        let review = try XCTUnwrap(scheduler.outcomes(state: initial, history: [], now: now, settings: settings)[.easy])
        XCTAssertEqual(try XCTUnwrap(scheduler.recallProbability(state: review, now: now, settings: settings)), 1, accuracy: 0.0001)
        XCTAssertLessThan(try XCTUnwrap(scheduler.recallProbability(state: review, now: now.addingTimeInterval(86400 * 100), settings: settings)), 0.9)
        XCTAssertNil(scheduler.recallProbability(state: review, now: now.addingTimeInterval(-1), settings: settings))
        var invalid = review; invalid.payload = Data()
        XCTAssertNil(scheduler.recallProbability(state: invalid, now: now, settings: settings))
        invalid = review; invalid.implementationVersion = "unknown"
        XCTAssertNil(scheduler.recallProbability(state: invalid, now: now, settings: settings))
        let imported = try scheduler.importState(due: now, phase: .review,
            sourceValues: ["s": "10", "d": "5", "lrt": String(now.timeIntervalSince1970 - 86400)], settings: settings)
        XCTAssertNotNil(scheduler.recallProbability(state: imported, now: now, settings: settings))
    }
}
