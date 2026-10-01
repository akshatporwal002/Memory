import Foundation
import LearningCore

/// Calendar arithmetic respects the saved study boundary and 23/25-hour days.
public struct ActivityWindow: Equatable, Sendable {
    public let interval: DateInterval
    public let buckets: [DateInterval]
    public init(period: ActivityPeriod, offset: Int, now: Date, settings: StudySettings, earliestReview: Date? = nil) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: settings.timeZoneID) ?? .gmt
        let days = period == .month ? 30 : period == .week ? 7 : 1
        let today = QueuePolicy.dayStart(now: now, settings: settings)
        let end = calendar.date(byAdding: .day, value: 1 + min(0, offset) * days, to: today)!
        let start = period == .all
            ? QueuePolicy.dayStart(now: min(earliestReview ?? now, now), settings: settings)
            : calendar.date(byAdding: .day, value: -days, to: end)!
        interval = DateInterval(start: start, end: end)
        var points: [DateInterval] = []; var cursor = start
        let component: Calendar.Component = period == .today ? .hour : .day
        // All-time charts use monthly bins once daily bins would become unreadable.
        let step: Calendar.Component = period == .all && calendar.dateComponents([.day], from: start, to: end).day! > 90 ? .month : component
        while cursor < end {
            let next = min(calendar.date(byAdding: step, value: 1, to: cursor)!, end)
            points.append(DateInterval(start: cursor, end: next)); cursor = next
        }
        buckets = points
    }
}
public struct ActivityChartPoint: Identifiable, Sendable {
    public var id: Date { interval.start }
    public let interval: DateInterval
    public let attempts: Int
    public let cards: Int
}
public struct ActivityReviewReport: Sendable {
    public let points: [ActivityChartPoint]
    public let attempts: Int
    public let cards: Int
    public let automatic: Int
    public let manual: Int
    public let recalled: Int
    public static func make(in library: LibrarySnapshot, window: ActivityWindow, now: Date) -> Self {
        let notes = Set(library.liveNotes.map(\.id)), decks = Set(library.liveDecks.map(\.id))
        let cards = Set(library.liveCards.filter { !$0.suspended && notes.contains($0.noteID) && decks.contains($0.deckID) }.map(\.id))
        let reviews = library.activeReviews.filter { cards.contains($0.cardID) && $0.reviewedAt <= now && $0.reviewedAt >= window.interval.start && $0.reviewedAt < window.interval.end }
        let points = window.buckets.map { bucket in
            let own = reviews.filter { $0.reviewedAt >= bucket.start && $0.reviewedAt < bucket.end }
            return ActivityChartPoint(interval: bucket, attempts: own.count, cards: Set(own.map(\.cardID)).count)
        }
        return Self(points: points, attempts: reviews.count, cards: Set(reviews.map(\.cardID)).count,
                    automatic: reviews.filter { $0.assessment != nil }.count,
                    manual: reviews.filter { $0.assessment == nil }.count,
                    recalled: reviews.filter { $0.rating == .good || $0.rating == .easy }.count)
    }
}
