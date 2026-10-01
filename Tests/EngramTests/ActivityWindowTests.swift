import XCTest
import LearningCore
import StudyApplication
import SchedulingAdapters
import PersistenceAdapters

final class ActivityWindowTests: XCTestCase {
    func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func testCalendarBucketsAcrossSpringAndAutumnDST() {
        var settings = StudySettings(timeZoneID: "America/New_York"); settings.dayStartsAtHour = 0
        let spring = ActivityWindow(period: .today, offset: 0, now: date("2026-03-08T18:00:00Z"), settings: settings)
        XCTAssertEqual(spring.buckets.count, 23)
        XCTAssertEqual(spring.interval.duration, 23 * 3600)
        let autumn = ActivityWindow(period: .today, offset: 0, now: date("2026-11-01T18:00:00Z"), settings: settings)
        XCTAssertEqual(autumn.buckets.count, 25)
        XCTAssertEqual(autumn.interval.duration, 25 * 3600)
        let previous = ActivityWindow(period: .week, offset: -1, now: date("2026-03-10T18:00:00Z"), settings: settings)
        let current = ActivityWindow(period: .week, offset: 0, now: date("2026-03-10T18:00:00Z"), settings: settings)
        XCTAssertEqual(previous.interval.end, current.interval.start)
        XCTAssertEqual(current.buckets.count, 7)
    }
    func testBeforeStudyBoundaryAndFutureNavigationClamp() {
        var settings = StudySettings(timeZoneID: "Australia/Sydney"); settings.dayStartsAtHour = 4
        let now = date("2026-10-02T16:00:00Z") // 02:00 on 3 October, previous study day
        let window = ActivityWindow(period: .today, offset: 0, now: now, settings: settings)
        XCTAssertEqual(window.interval.start, date("2026-10-01T18:00:00Z"))
        XCTAssertEqual(window, ActivityWindow(period: .today, offset: 1, now: now, settings: settings))
    }
    func testReportCountsRepeatedCardsAndExcludesUndoFutureAndBoundary() throws {
        let fixture = ActivityTests(); let now = fixture.now.addingTimeInterval(3600); var library = try fixture.library()
        library.settings = StudySettings(timeZoneID: "GMT"); library.settings.dayStartsAtHour = 0
        let window = ActivityWindow(period: .today, offset: 0, now: now, settings: library.settings)
        let state = library.cards[0].schedule
        let time = now.addingTimeInterval(-60)
        var marked = fixture.event("marked", grade: .good, time: time, state: state)
        marked.assessment = AnswerAssessment(outcome: .correct, reason: "Matches answer", method: "mcq")
        library.reviews = [marked, fixture.event("manual", grade: .hard, time: time, state: state),
                           fixture.event("undone", grade: .good, time: time, state: state),
                           fixture.event("future", grade: .good, time: now.addingTimeInterval(20), state: state),
                           fixture.event("boundary", grade: .good, time: window.interval.end, state: state)]
        library.corrections = [ReviewCorrection(reviewID: "undone", createdAt: now)]
        let report = ActivityReviewReport.make(in: library, window: window, now: now)
        XCTAssertEqual(report.attempts, 2); XCTAssertEqual(report.cards, 1)
        XCTAssertEqual(report.automatic, 1); XCTAssertEqual(report.manual, 1); XCTAssertEqual(report.recalled, 1)
        XCTAssertEqual(report.points.reduce(0) { $0 + $1.attempts }, 2)
        let bucket = try XCTUnwrap(report.points.first { $0.attempts > 0 })
        let selected = ActivitySummary.make(in: library, period: .today, now: now, estimator: nil, interval: bucket.interval)
        XCTAssertEqual(selected.attemptCount, 2)
        library.cards[0].suspended = true
        XCTAssertEqual(ActivityReviewReport.make(in: library, window: window, now: now).attempts, 0)
    }
    func testEmptyAndLongHistoryHaveFiniteBuckets() {
        let now = date("2026-10-01T12:00:00Z"), settings = StudySettings(timeZoneID: "GMT")
        let window = ActivityWindow(period: .all, offset: 0, now: now, settings: settings, earliestReview: date("2020-01-01T12:00:00Z"))
        XCTAssertLessThan(window.buckets.count, 90)
        XCTAssertEqual(window.buckets.last?.end, window.interval.end)
        XCTAssertEqual(ActivityReviewReport.make(in: LibrarySnapshot(), window: window, now: now).attempts, 0)
    }
    func testPreferenceUpdatesPreserveOtherValuesAndRejectInvalidInput() async throws {
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        try await service.updatePreference(.newCards(42)); try await service.updatePreference(.reviews(99))
        let snapshot = try await service.snapshot()
        XCTAssertEqual(snapshot.settings.newCardsPerDay, 42); XCTAssertEqual(snapshot.settings.reviewsPerDay, 99)
        for preference: StudyPreference in [.newCards(-1), .reviews(100_001), .dayStarts(24), .timeZone("invalid"), .retention(.nan)] {
            do { try await service.updatePreference(preference); XCTFail("Accepted invalid preference") } catch { }
        }
        let after = try await service.snapshot()
        XCTAssertEqual(after, snapshot)
    }
}
