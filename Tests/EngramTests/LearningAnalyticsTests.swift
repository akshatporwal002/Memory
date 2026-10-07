import XCTest
import LearningCore
import StudyApplication
import SchedulingAdapters
import PersistenceAdapters

final class LearningAnalyticsTests: XCTestCase {
    func testDemoRunsEveryModelWithoutMutatingLearningHistory() async throws {
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let id = try await service.importLearningAnalyticsDemo(now: now)
        let before = try await service.snapshot()
        let charts = try await service.notebookAnalytics(deckID: id, now: now)
        XCTAssertTrue(charts.isDemo)
        XCTAssertEqual(charts.observed.acceptedAttempts, 252)
        XCTAssertEqual(Set(charts.components.map(\.description.model)), Set(LearnerModelID.allCases))
        XCTAssertEqual(charts.recallForecast.count, 15)
        XCTAssertGreaterThan(charts.observed.delayedRecall.attempts, 0)
        XCTAssertGreaterThan(charts.observed.unfamiliarQuestions.attempts, 0)
        XCTAssertFalse(charts.observed.skillErrors.isEmpty)
        for component in charts.components {
            XCTAssertEqual(component.questions.count, 9)
            for q in component.questions {
                let p = try XCTUnwrap(q.prediction?.probabilityCorrect)
                XCTAssertTrue((0...1).contains(p))
            }
        }
        let irt = try XCTUnwrap(charts.components.first { $0.description.model == .dynamicRasch })
        XCTAssertGreaterThan(irt.abilityHistory.count, 1)
        for point in irt.abilityHistory {
            XCTAssertLessThanOrEqual(try XCTUnwrap(point.lower), point.value)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(point.upper), point.value)
        }
        let dina = try XCTUnwrap(charts.components.first { $0.description.model == .dina })
        XCTAssertEqual(dina.questions.first?.prediction?.compatibleAttempts, 9)
        XCTAssertTrue(before.activeReviews.isEmpty)
        XCTAssertTrue(before.liveCards.allSatisfy(\.suspended))
        let after = try await service.snapshot()
        XCTAssertEqual(before, after)
        XCTAssertTrue(QueuePolicy.dueCards(in: after, deckID: nil, now: now).isEmpty)
    }
    func testDeadlineSampleHasHistoryAndRespectsBudgetWithoutSavingAGoal() async throws {
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let id = try await service.importLearningAnalyticsDemo(now: now)
        let before = try await service.snapshot()
        let preview = try await service.deadlineLearningSample(deckID: id, dailyMinutes: 3, now: now)
        let record = try XCTUnwrap(preview)
        XCTAssertEqual(record.forecasts.count, 7)
        let plan = try XCTUnwrap(record.forecasts.last)
        XCTAssertEqual(plan.observations, 252)
        XCTAssertGreaterThan(plan.forecast, plan.baseline)
        XCTAssertFalse(plan.actions.isEmpty)
        for date in Set(plan.actions.map(\.date)) {
            XCTAssertLessThanOrEqual(plan.actions.filter { $0.date == date }.reduce(0) { $0 + $1.seconds }, 180)
        }
        let after = try await service.snapshot()
        XCTAssertEqual(before, after)
        XCTAssertTrue(after.activeReviews.isEmpty)
        let other = try await service.deadlineLearningSample(deckID: "missing", now: now)
        XCTAssertNil(other)
    }
    func testRepeatImportPreservesDemoAndDeletion() async throws {
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let id = try await service.importLearningAnalyticsDemo()
        let before = try await service.snapshot()
        _ = try await service.importLearningAnalyticsDemo()
        let after = try await service.snapshot()
        XCTAssertEqual(before, after)
        try await service.deleteDeck(id: id)
        _ = try await service.importLearningAnalyticsDemo()
        let deleted = try await service.snapshot()
        XCTAssertFalse(deleted.liveDecks.contains { $0.id == id })
    }
}
