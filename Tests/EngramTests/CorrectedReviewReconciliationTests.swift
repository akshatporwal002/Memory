import XCTest
import LearningCore
import SchedulingAdapters

final class CorrectedReviewReconciliationTests: XCTestCase {
    func testRemovingFirstReviewDoesNotRetainItsEffectThroughLaterBeforeState() throws {
        let scheduler = FSRSScheduler(), settings = StudySettings()
        let now = Date(timeIntervalSince1970: 1_788_393_600)
        let initial = try scheduler.initialState(now: now, settings: settings)
        let afterFirst = try XCTUnwrap(scheduler.outcomes(state: initial, history: [], now: now, settings: settings)[.again])
        var first = ReviewEvent(id: "first", cardID: "card", deckID: "deck", sessionID: "session", rating: .again,
            reviewedAt: now, committedAt: now, before: initial, after: afterFirst)
        first.settingsSnapshot = settings
        let laterTime = now.addingTimeInterval(86_400)
        let afterLater = try XCTUnwrap(scheduler.outcomes(state: afterFirst, history: [first], now: laterTime, settings: settings)[.good])
        var later = ReviewEvent(id: "later", cardID: "card", deckID: "deck", sessionID: "session", rating: .good,
            reviewedAt: laterTime, committedAt: laterTime, before: afterFirst, after: afterLater)
        later.settingsSnapshot = settings
        let card = StudyCard(id: "card", noteID: "note", deckID: "deck", schedule: afterLater)
        let correction = ReviewCorrection(reviewID: "first", createdAt: laterTime)
        let expected = try XCTUnwrap(scheduler.outcomes(state: initial, history: [], now: laterTime, settings: settings)[.good])
        let reconciled = try ReviewReconciliation.replay(card: card, allEvents: [later, first], corrections: [correction], settings: settings, scheduler: scheduler)
        XCTAssertEqual(reconciled, expected)
        XCTAssertNotEqual(reconciled, afterLater)
        XCTAssertEqual(try ReviewReconciliation.replay(card: card, allEvents: [first, later], corrections: [], settings: settings, scheduler: scheduler), afterLater)
        XCTAssertEqual(try ReviewReconciliation.replay(card: card, allEvents: [first, later], corrections: [correction, ReviewCorrection(reviewID: "later", createdAt: laterTime)], settings: settings, scheduler: scheduler), initial)
    }
}
