import Foundation
import LearningCore

public enum QueuePolicy {
    /// A persisted IANA zone avoids changing the study day silently when travelling.
    public static func dayStart(now: Date, settings: StudySettings) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: settings.timeZoneID) ?? .gmt
        let midnight = calendar.startOfDay(for: now)
        let boundary = calendar.date(bySettingHour: settings.dayStartsAtHour, minute: 0, second: 0, of: midnight) ?? midnight
        if now >= boundary { return boundary }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: midnight) ?? midnight
        return calendar.date(bySettingHour: settings.dayStartsAtHour, minute: 0, second: 0, of: yesterday) ?? yesterday
    }
    public static func dueCards(in library: LibrarySnapshot, deckID: String?, now: Date) -> [StudyCard] {
        let start = dayStart(now: now, settings: library.settings)
        let today = library.activeReviews.filter { $0.reviewedAt >= start && $0.reviewedAt <= now }
        let newUsed = Set(today.filter { $0.before.phase == .new }.map(\.cardID)).count
        let reviewUsed = today.filter { $0.before.phase == .review }.count
        var newBudget = max(0, library.settings.newCardsPerDay - newUsed)
        var reviewBudget = max(0, library.settings.reviewsPerDay - reviewUsed)
        let supportedNotes = Set(library.liveNotes.filter { $0.kind != .unsupported }.map(\.id))
        let liveDecks = Set(library.liveDecks.map(\.id))
        let selectedName = library.decks.first { $0.id == deckID }?.name
        let selectedDecks = Set(library.liveDecks.filter { $0.id == deckID || (selectedName != nil && $0.name.hasPrefix(selectedName! + "::")) }.map(\.id))
        return library.cards.filter {
            !$0.retired && !$0.suspended && supportedNotes.contains($0.noteID) && liveDecks.contains($0.deckID) &&
            (deckID == nil || selectedDecks.contains($0.deckID)) && $0.schedule.due <= now
        }.sorted {
            func priority(_ phase: LearningPhase) -> Int { phase == .new ? 2 : (phase == .review ? 1 : 0) }
            let a = priority($0.schedule.phase), b = priority($1.schedule.phase)
            if a != b { return a < b }
            if $0.schedule.due != $1.schedule.due { return $0.schedule.due < $1.schedule.due }
            return $0.id < $1.id
        }.filter {
            switch $0.schedule.phase {
            case .new: guard newBudget > 0 else { return false }; newBudget -= 1
            case .review: guard reviewBudget > 0 else { return false }; reviewBudget -= 1
            case .learning, .relearning: break
            }
            return true
        }
    }
}
