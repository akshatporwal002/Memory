import Foundation
import LearningCore

extension StudyService {
    /// Read-only illustration of the real planner. Suspended demo cards are used
    /// only in this preview; no goal, evidence or forecast enters the learner store.
    public func deadlineLearningSample(deckID: String, deadline: Date? = nil, target: Double = 0.8,
                                       dailyMinutes: Int = 5, now: Date = Date()) async throws -> DeadlineRecord? {
        let snapshot = try await repository.read()
        guard let deck = snapshot.liveDecks.first(where: { $0.id == deckID }), LearningAnalyticsDemo.isDemo(deck) else { return nil }
        let analytics = try LearningAnalyticsDemo.analytics(deck: deck, snapshot: snapshot, scheduler: scheduler, now: now)
        let items = LearningAnalyticsDemo.prompts.indices.map { i in
            DeadlineGoal.Item(id: deckID + "-q\(i)-card", prompt: LearningAnalyticsDemo.prompts[i], answer: LearningAnalyticsDemo.answers[i], questionType: "Short answer", questionVersion: 1)
        }
        let goal = DeadlineGoal(deckID: deckID, createdAt: now.addingTimeInterval(-7 * 86400),
            deadline: deadline ?? now.addingTimeInterval(14 * 86400), target: target, dailyMinutes: dailyMinutes, items: items)
        let forecasts = try (-6...0).map { day in
            let date = now.addingTimeInterval(Double(day) * 86400)
            return try DeadlinePlanner.make(goal: goal, evidence: analytics.evidence, evidenceRevision: analytics.evidence.filter { $0.occurredAt <= date }.count, now: date)
        }
        return DeadlineRecord(goal: goal, forecasts: forecasts)
    }
}
