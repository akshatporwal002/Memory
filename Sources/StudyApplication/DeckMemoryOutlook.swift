import Foundation
import LearningCore

public struct MemoryCardEstimate: Identifiable, Sendable {
    public let id: String
    public let prompt: String
    public let probabilities: [Double]
}

public struct DeckMemoryOutlook: Sendable {
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
            estimated.append(MemoryCardEstimate(id: card.id, prompt: notes[card.noteID]?.front ?? "Question", probabilities: points))
        }
        let average = dates.indices.map { day in estimated.isEmpty ? 0 : estimated.reduce(0) { $0 + $1.probabilities[day] } / Double(estimated.count) }
        let scheduled = cards.filter { $0.schedule.phase != .new }.map(\.schedule.due)
        return Self(sampleDates: dates, target: target, inheritsTarget: deck.desiredRetention == nil,
                    aboveTarget: estimated.filter { $0.probabilities[0] >= target }.count,
                    belowTarget: estimated.filter { $0.probabilities[0] < target }.count,
                    newCount: newCount, unavailableCount: unavailable,
                    average: average, cards: estimated,
                    nextPlannedReview: scheduled.min(),
                    scheduledWithinWeek: scheduled.filter { $0 <= now.addingTimeInterval(7 * 86_400) }.count)
    }
    public static func forecastEnd(examDate: Date?, now: Date, calendar: Calendar = .current) -> Date {
        if let examDate, examDate > now { return examDate }
        return calendar.dateInterval(of: .year, for: now)?.end.addingTimeInterval(-1) ?? now.addingTimeInterval(365 * 86_400)
    }

}
