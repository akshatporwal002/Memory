import Foundation
import LearningCore

public struct MemoryCardEstimate: Identifiable, Sendable {
    public let id: String
    public let prompt: String
    public let probabilities: [Double]
}

public struct DeckMemoryOutlook: Sendable {
    public let target: Double
    public let inheritsTarget: Bool
    public let aboveTarget: Int
    public let belowTarget: Int
    public let newCount: Int
    public let unavailableCount: Int
    public let average: [Double]
    public let cards: [MemoryCardEstimate]

    public static func make(deck: Deck, library: LibrarySnapshot, now: Date, estimator: (any MemoryEstimating)?) -> Self {
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
            let points = (0...7).compactMap { day -> Double? in
                let date = now.addingTimeInterval(Double(day) * 86_400)
                return estimator?.recallProbability(state: card.schedule, now: date, settings: settings)
            }
            guard points.count == 8 else { unavailable += 1; continue }
            estimated.append(MemoryCardEstimate(id: card.id, prompt: notes[card.noteID]?.front ?? "Question", probabilities: points))
        }
        let average = (0...7).map { day in estimated.isEmpty ? 0 : estimated.reduce(0) { $0 + $1.probabilities[day] } / Double(estimated.count) }
        return Self(target: target, inheritsTarget: deck.desiredRetention == nil,
                    aboveTarget: estimated.filter { $0.probabilities[0] >= target }.count,
                    belowTarget: estimated.filter { $0.probabilities[0] < target }.count,
                    newCount: newCount, unavailableCount: unavailable,
                    average: average, cards: estimated)
    }
}
