import Foundation

/// Personal organization; never derived from the connected AI account.
public struct LibrarySpace: Codable, Equatable, Identifiable, Sendable {
    public static let defaultID = "default"
    public var id: String
    public var name: String
    public var deviceOnly: Bool
    public var folders: [String]
    public init(id: String = UUID().uuidString, name: String, deviceOnly: Bool = false, folders: [String] = []) {
        self.id = id; self.name = name; self.deviceOnly = deviceOnly; self.folders = folders
    }
}

public struct LibrarySpaceCatalog: Codable, Equatable, Sendable {
    public var spaces: [LibrarySpace] = [LibrarySpace(id: LibrarySpace.defaultID, name: "My library")]
    /// Unassigned legacy and newly shared content belongs to the default library.
    public var membership: [String: String] = [:]
    public init() {}
    public func space(for key: String) -> String { membership[key] ?? LibrarySpace.defaultID }
    public func validate() throws {
        guard spaces.count <= 50, Set(spaces.map(\.id)).count == spaces.count,
              spaces.contains(where: { $0.id == LibrarySpace.defaultID && !$0.deviceOnly }),
              spaces.allSatisfy({ ($0.id == LibrarySpace.defaultID || UUID(uuidString: $0.id) != nil) && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 80 }),
              membership.values.allSatisfy({ id in spaces.contains { $0.id == id } }) else {
            throw EngramError.invalid("Invalid library organization.")
        }
        for space in spaces {
            guard space.folders.count <= 5_000, Set(space.folders.map { $0.lowercased() }).count == space.folders.count else { throw EngramError.invalid("Duplicate library folders.") }
            for path in space.folders { try LibraryValidation.validateFolderPath(path) }
        }
    }
}

public enum LibrarySpaceScope {
    public static func project(_ source: LibrarySnapshot, spaceIDs: Set<String>) -> LibrarySnapshot {
        let catalog = source.librarySpaces ?? LibrarySpaceCatalog()
        func includes(_ key: String) -> Bool { spaceIDs.contains(catalog.space(for: key)) }
        var result = source
        result.decks = source.decks.filter { includes("deck:" + $0.id) }
        let decks = Set(result.decks.map(\.id))
        result.notes = source.notes.filter { decks.contains($0.deckID) }
        let notes = Set(result.notes.map(\.id))
        result.cards = source.cards.filter { decks.contains($0.deckID) }
        let cards = Set(result.cards.map(\.id))
        result.reviews = source.reviews.filter { decks.contains($0.deckID) }
        let reviews = Set(result.reviews.map(\.id))
        result.corrections = source.corrections.filter { reviews.contains($0.reviewID) }
        result.importedReviews = source.importedReviews.filter { cards.contains($0.cardID) }
        result.answerAttempts = source.answerAttempts?.filter { notes.contains($0.noteID) }
        result.folderDocuments = source.folderDocuments?.filter { includes("file:" + $0.id) }
        if let session = source.session, !includes("session:" + session.id) { result.session = nil }
        if source.librarySpaces != nil {
            result.folders = Array(Set(catalog.spaces.filter { spaceIDs.contains($0.id) }.flatMap(\.folders))).sorted()
        }
        if let current = source.session?.current, !decks.contains(current.card.deckID) { result.session = nil }
        if let deck = source.session?.deckID, !decks.contains(deck) { result.session = nil }
        if var state = source.assistantState {
            state.conversations = state.conversations.filter { includes("chat:" + $0.id) }
            let conversations = Set(state.conversations.map(\.id))
            state.runs = state.runs.filter { includes("chat:" + $0.conversationID) || conversations.contains($0.conversationID) }
            state.memory = state.memory.filter { notes.contains($0.noteID) }
            result.assistantState = state
        }
        if source.librarySpaces != nil {
            let references = Set(result.notes.flatMap { SafeCardMarkup.inspect($0.front).mediaNames + SafeCardMarkup.inspect($0.back).mediaNames })
                .union(result.decks.compactMap(\.coverMediaName))
            let notebookText = result.decks.compactMap(\.sourceDocument).joined(separator: "\n")
            result.media = source.media.filter { references.contains($0.name) || notebookText.contains($0.name) }
        }
        return result
    }

    public static func syncable(_ source: LibrarySnapshot) -> LibrarySnapshot {
        guard let catalog = source.librarySpaces else { return source }
        let allowed = Set(catalog.spaces.filter { !$0.deviceOnly }.map(\.id))
        var result = project(source, spaceIDs: allowed)
        var cloudCatalog = catalog
        cloudCatalog.spaces.removeAll { $0.deviceOnly }
        cloudCatalog.membership = catalog.membership.filter { allowed.contains($0.value) }
        result.librarySpaces = cloudCatalog
        return result
    }
}
