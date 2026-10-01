import Foundation
import LearningCore

public enum ActivityPeriod: String, CaseIterable, Identifiable, Sendable {
    case today = "Today", week = "7 days", month = "30 days", all = "All time"
    public var id: String { rawValue }
    public func start(now: Date, settings: StudySettings) -> Date {
        guard self != .all else { return .distantPast }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: settings.timeZoneID) ?? .gmt
        return calendar.date(byAdding: .day, value: self == .week ? -6 : self == .month ? -29 : 0,
            to: QueuePolicy.dayStart(now: now, settings: settings)) ?? now
    }
}
public enum MemoryBucket: String, CaseIterable, Identifiable, Sendable {
    case atTarget = "At target", belowTarget = "Below target", learning = "Learning", unstudied = "Unstudied", unavailable = "Unavailable"
    public var id: String { rawValue }
}
public enum ActivityCardFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All", due = "Due", reviewed = "Reviewed", unstudied = "Unstudied"
    public var id: String { rawValue }
}
public struct ActivityQuestion: Identifiable, Sendable {
    public let id: String
    public let prompt: String
    public let answer: String
    public let due: Date
    public let isDue: Bool
    public let bucket: MemoryBucket
    public let attempts: [ReviewEvent]
    public var outcome: String {
        guard let grade = attempts.first?.rating else {
            return bucket == .unstudied ? "Unstudied" : "Not reviewed in this period"
        }
        switch grade { case .again: return "Forgot"; case .hard: return "Recalled with difficulty"; case .good, .easy: return "Recalled" }
    }
    public func matches(_ filter: ActivityCardFilter) -> Bool {
        switch filter { case .all: return true; case .due: return isDue; case .reviewed: return !attempts.isEmpty; case .unstudied: return bucket == .unstudied }
    }
}
public struct ActivityDeck: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let folder: String
    public let questions: [ActivityQuestion]
    public let suspendedCount: Int
    public let counts: [MemoryBucket: Int]
    public var dueCount: Int { questions.filter(\.isDue).count }
}
public struct ActivitySummary: Sendable {
    public let decks: [ActivityDeck]
    public let reviewedCount: Int
    public let attemptCount: Int
    public var dueCount: Int { decks.reduce(0) { $0 + $1.dueCount } }

    public static func make(in library: LibrarySnapshot, period: ActivityPeriod, now: Date,
                            estimator: (any MemoryEstimating)?, interval: DateInterval? = nil) -> Self {
        let notes = Dictionary(uniqueKeysWithValues: library.liveNotes.map { ($0.id, $0) })
        let deckIDs = Set(library.liveDecks.map(\.id))
        let cards = library.liveCards.filter { notes[$0.noteID] != nil && deckIDs.contains($0.deckID) }
        let activeIDs = Set(cards.filter { !$0.suspended }.map(\.id))
        let start = interval?.start ?? period.start(now: now, settings: library.settings)
        let reviews = library.activeReviews.filter { activeIDs.contains($0.cardID) && $0.reviewedAt >= start && $0.reviewedAt <= now && (interval == nil || $0.reviewedAt < interval!.end) }
        let history = Dictionary(grouping: reviews, by: \.cardID)
        let groupedCards = Dictionary(grouping: cards, by: \.deckID)
        let decks = library.liveDecks.map { deck -> ActivityDeck in
            var deckSettings = library.settings
            deckSettings.desiredRetention = deck.desiredRetention ?? library.settings.desiredRetention
            let ownCards = groupedCards[deck.id] ?? []
            let questions = ownCards.filter { !$0.suspended }.map { card -> ActivityQuestion in
                let bucket: MemoryBucket
                switch card.schedule.phase {
                case .new: bucket = .unstudied
                case .learning, .relearning: bucket = .learning
                case .review:
                    if let value = estimator?.recallProbability(state: card.schedule, now: now, settings: deckSettings), value.isFinite, (0...1).contains(value) {
                        bucket = value >= deckSettings.desiredRetention ? .atTarget : .belowTarget
                    } else { bucket = .unavailable }
                }
                let rendered = notes[card.noteID].flatMap { try? CardRenderer.render(note: $0, card: card, revealed: true) }
                func plain(_ text: String) -> String {
                    let content = SafeCardMarkup.inspect(text)
                    return content.plainText.isEmpty && !content.mediaNames.isEmpty ? "Media card" : content.plainText
                }
                return ActivityQuestion(id: card.id, prompt: rendered.map { plain($0.prompt) } ?? "Unsupported card",
                    answer: rendered?.answer ?? "This card’s content cannot be displayed here.",
                    due: card.schedule.due, isDue: card.schedule.phase != .new && card.schedule.due <= now,
                    bucket: bucket, attempts: (history[card.id] ?? []).sorted {
                        $0.reviewedAt == $1.reviewedAt ? $0.id < $1.id : $0.reviewedAt > $1.reviewedAt
                    })
            }.sorted {
                if $0.isDue != $1.isDue { return $0.isDue }
                if $0.isDue && $0.due != $1.due { return $0.due < $1.due }
                return $0.prompt == $1.prompt ? $0.id < $1.id : $0.prompt.localizedStandardCompare($1.prompt) == .orderedAscending
            }
            let parts = deck.name.components(separatedBy: "::")
            return ActivityDeck(id: deck.id, title: parts.last ?? deck.name, folder: parts.dropLast().joined(separator: " / "),
                questions: questions, suspendedCount: ownCards.filter(\.suspended).count,
                counts: Dictionary(grouping: questions, by: \.bucket).mapValues(\.count))
        }.sorted {
            if $0.dueCount != $1.dueCount { return $0.dueCount > $1.dueCount }
            let lhs = $0.folder + $0.title, rhs = $1.folder + $1.title
            return lhs == rhs ? $0.id < $1.id : lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
        return Self(decks: decks, reviewedCount: Set(reviews.map(\.cardID)).count, attemptCount: reviews.count)
    }
}
