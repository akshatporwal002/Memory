import Foundation
import LearningCore

public enum LibrarySort: String, CaseIterable, Identifiable, Sendable {
    case nextReview, alphabetical, reverseAlphabetical, recentlyEdited, recentlyCreated, mostCards
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .nextReview: return "Next review"
        case .alphabetical: return "Name A–Z"
        case .reverseAlphabetical: return "Name Z–A"
        case .recentlyEdited: return "Recently edited"
        case .recentlyCreated: return "Newest first"
        case .mostCards: return "Most cards"
        }
    }
}

public struct LibraryDeckSummary: Identifiable, Sendable {
    public var id: String { deck.id }
    public let deck: Deck
    public let cardCount: Int
    public let dueCount: Int
    public let newCount: Int
    public let availableCount: Int
    public let nextReview: Date?
    public let lastEdited: Date?
    public let searchText: String
    public var title: String { deck.name.components(separatedBy: "::").last ?? deck.name }
    public var folder: String { deck.name.components(separatedBy: "::").dropLast().joined(separator: "::") }
    public var priority: Int { dueCount > 0 ? 0 : newCount > 0 ? 1 : nextReview != nil ? 2 : 3 }
    public var limitReached: Bool { dueCount + newCount > 0 && availableCount == 0 }

    public static func make(in library: LibrarySnapshot, now: Date) -> [Self] {
        let liveNotes = library.liveNotes
        let notes = Dictionary(grouping: liveNotes, by: \.deckID)
        let noteIDs = Set(liveNotes.map(\.id))
        let cards = Dictionary(grouping: library.liveCards.filter { noteIDs.contains($0.noteID) }, by: \.deckID)
        let eligible = Dictionary(grouping: QueuePolicy.eligibleCards(in: library, deckID: nil), by: \.deckID)
        let start = QueuePolicy.dayStart(now: now, settings: library.settings)
        let today = library.activeReviews.filter { $0.reviewedAt >= start && $0.reviewedAt <= now }
        let newBudget = max(0, library.settings.newCardsPerDay - Set(today.filter { $0.before.phase == .new }.map(\.cardID)).count)
        let reviewBudget = max(0, library.settings.reviewsPerDay - today.filter { $0.before.phase == .review }.count)
        return library.liveDecks.map { deck in
            let studyCards = eligible[deck.id] ?? []
            let ready = studyCards.filter { $0.schedule.due <= now }
            let newCount = ready.filter { $0.schedule.phase == .new }.count
            let reviews = ready.filter { $0.schedule.phase == .review }.count
            let learning = ready.filter { $0.schedule.phase == .learning || $0.schedule.phase == .relearning }.count
            let deckNotes = notes[deck.id] ?? []
            return Self(deck: deck, cardCount: cards[deck.id]?.count ?? 0,
                dueCount: reviews + learning, newCount: newCount,
                availableCount: min(newCount, newBudget) + min(reviews, reviewBudget) + learning,
                nextReview: studyCards.filter { $0.schedule.phase != .new }.map(\.schedule.due).min(),
                lastEdited: ([deck.modifiedAt] + deckNotes.map { Optional($0.modifiedAt) }).compactMap { $0 }.max(),
                searchText: ([deck.name, deck.sourceDocument ?? ""] + (deck.documents ?? []).map(\.name) + deckNotes.flatMap { [$0.front, $0.tags.joined(separator: " ")] }).joined(separator: " "))
        }
    }

    public static func sorted(_ entries: [Self], by sort: LibrarySort, query: String = "") -> [Self] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return entries.filter { entry in terms.allSatisfy { entry.searchText.localizedStandardContains($0) } }.sorted { a, b in
            switch sort {
            case .nextReview:
                if a.priority != b.priority { return a.priority < b.priority }
                if a.nextReview != b.nextReview { return (a.nextReview ?? .distantFuture) < (b.nextReview ?? .distantFuture) }
            case .recentlyEdited:
                if a.lastEdited != b.lastEdited { return (a.lastEdited ?? .distantPast) > (b.lastEdited ?? .distantPast) }
            case .recentlyCreated:
                if a.deck.createdAt != b.deck.createdAt { return (a.deck.createdAt ?? .distantPast) > (b.deck.createdAt ?? .distantPast) }
            case .mostCards:
                if a.cardCount != b.cardCount { return a.cardCount > b.cardCount }
            case .alphabetical, .reverseAlphabetical: break
            }
            let comparison = a.deck.name.localizedStandardCompare(b.deck.name)
            if comparison == .orderedSame { return a.id < b.id }
            return sort == .reverseAlphabetical ? comparison == .orderedDescending : comparison == .orderedAscending
        }
    }
}

/// Presentation hierarchy over existing :: paths; no duplicated or renamed decks.
public struct LibraryFolder: Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let title: String
    public let deck: LibraryDeckSummary?
    public let isExplicit: Bool
    public let children: [LibraryFolder]
    public var deckCount: Int { (deck == nil ? 0 : 1) + children.reduce(0) { $0 + $1.deckCount } }
    public var dueCount: Int { (deck?.dueCount ?? 0) + children.reduce(0) { $0 + $1.dueCount } }

    public static func tree(_ entries: [LibraryDeckSummary], explicitFolders: [String] = [], parent: String = "") -> [Self] {
        let prefix = parent.isEmpty ? "" : parent + "::"
        var seen = Set<String>()
        // Entries arrive sorted; each branch inherits its first descendant's priority.
        let paths = entries.map(\.deck.name) + explicitFolders
        return paths.compactMap { fullPath in
            guard fullPath.hasPrefix(prefix),fullPath.count > prefix.count else { return nil }
            let remainder = String(fullPath.dropFirst(prefix.count))
            let name = remainder.components(separatedBy: "::")[0]
            let path = prefix + name
            guard seen.insert(path).inserted else { return nil }
            return Self(path: path, title: name, deck: entries.first { $0.deck.name == path },
                isExplicit: explicitFolders.contains(path),
                children: tree(entries.filter { $0.deck.name.hasPrefix(path + "::") },
                               explicitFolders: explicitFolders.filter { $0.hasPrefix(path + "::") },parent:path))
        }
    }
}
