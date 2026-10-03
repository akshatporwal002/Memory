import Foundation
import LearningCore

public struct MemoryHistoryPoint: Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let probability: Double
}

public struct MemoryCardEstimate: Identifiable, Sendable {
    public let id: String
    public let prompt: String
    public let probabilities: [Double]
    public let history: [MemoryHistoryPoint]
}

public struct DeckMemoryOutlook: Sendable {
    public let startDate: Date
    public let history: [MemoryHistoryPoint]
    public let sampleDates: [Date]
    public let target: Double
    public let inheritsTarget: Bool
    public let aboveTarget: Int
    public let belowTarget: Int
    public let newCount: Int
    public let unavailableCount: Int
    public let average: [Double]
    public let cards: [MemoryCardEstimate]
    public let nextPlannedReview: Date?
    public let scheduledWithinWeek: Int

    public static func make(deck: Deck, library: LibrarySnapshot, now: Date, estimator: (any MemoryEstimating)?) -> Self {
        let reviews = library.activeReviews.filter { $0.deckID == deck.id && $0.reviewedAt <= now }.sorted { $0.reviewedAt < $1.reviewedAt }
        let start = min(deck.createdAt ?? reviews.first?.reviewedAt ?? now, now)
        let end = forecastEnd(examDate: deck.examDate, now: now)
        let duration = max(1, end.timeIntervalSince(now))
        let intervals = max(1, Int(min(64, ceil(duration / 86_400))))
        let dates = (0...intervals).map { index in now.addingTimeInterval(duration * pow(Double(index) / Double(intervals), 2)) }
        let target = deck.desiredRetention ?? library.settings.desiredRetention
        var settings = library.settings
        settings.desiredRetention = target
        let notes = Dictionary(uniqueKeysWithValues: library.liveNotes.map { ($0.id, $0) })
        let cards = library.liveCards.filter { $0.deckID == deck.id && !$0.suspended && notes[$0.noteID] != nil }
        var estimated: [MemoryCardEstimate] = []
        var newCount = 0
        var unavailable = 0
        for card in cards {
            if card.schedule.phase == .new { newCount += 1; continue }
            let points = dates.compactMap { date -> Double? in
                return estimator?.recallProbability(state: card.schedule, now: date, settings: settings)
            }
            guard points.count == dates.count else { unavailable += 1; continue }
            let history = reviews.filter { $0.cardID == card.id && $0.reviewedAt >= start }.compactMap { review -> MemoryHistoryPoint? in
                guard let probability = estimator?.recallProbability(state: review.after, now: review.reviewedAt, settings: settings) else { return nil }
                return MemoryHistoryPoint(date: review.reviewedAt, probability: probability)
            }
            estimated.append(MemoryCardEstimate(id: card.id, prompt: notes[card.noteID]?.front ?? "Question", probabilities: points, history: history))
        }
        let average = dates.indices.map { day in estimated.isEmpty ? 0 : estimated.reduce(0) { $0 + $1.probabilities[day] } / Double(estimated.count) }
        let scheduled = cards.filter { $0.schedule.phase != .new }.map(\.schedule.due)
        let knownCards = Set(estimated.map(\.id))
        let historyDates = Array(Set(reviews.filter { knownCards.contains($0.cardID) && $0.reviewedAt >= start }.map(\.reviewedAt))).sorted()
        let strideSize = max(1, Int(ceil(Double(historyDates.count) / 128)))
        let history = historyDates.enumerated().filter { $0.offset % strideSize == 0 || $0.offset == historyDates.count - 1 }.compactMap { _, date -> MemoryHistoryPoint? in
            var states: [String: ScheduleState] = [:]
            for review in reviews where review.reviewedAt <= date && knownCards.contains(review.cardID) { states[review.cardID] = review.after }
            let probabilities = states.values.compactMap { estimator?.recallProbability(state: $0, now: date, settings: settings) }
            guard !probabilities.isEmpty else { return nil }
            return MemoryHistoryPoint(date: date, probability: probabilities.reduce(0, +) / Double(probabilities.count))
        }
        return Self(startDate: start, history: history, sampleDates: dates, target: target, inheritsTarget: deck.desiredRetention == nil,
                    aboveTarget: estimated.filter { $0.probabilities[0] >= target }.count,
                    belowTarget: estimated.filter { $0.probabilities[0] < target }.count,
                    newCount: newCount, unavailableCount: unavailable,
                    average: average, cards: estimated,
                    nextPlannedReview: scheduled.min(),
                    scheduledWithinWeek: scheduled.filter { $0 <= now.addingTimeInterval(7 * 86_400) }.count)
    }
    public static func forecastEnd(examDate: Date?, now: Date, calendar: Calendar = .current) -> Date {
        if let examDate, examDate > now { return examDate }
        return calendar.date(byAdding: .year, value: 1, to: now) ?? now.addingTimeInterval(365 * 86_400)
    }

}
