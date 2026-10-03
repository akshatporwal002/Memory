import Foundation
import LearningCore

/// All study, AI and retrieval use cases see the same selected-library projection.
/// Cloud synchronization continues to use the underlying account repository.
actor LibrarySpaceRepository: LibraryRepository {
    let base: any LibraryRepository
    private(set) var selectedID = LibrarySpace.defaultID
    private var generation = UUID().uuidString
    init(base: any LibraryRepository) { self.base = base }
    func spaces() async throws -> [LibrarySpace] { (try await base.read()).librarySpaces?.spaces ?? LibrarySpaceCatalog().spaces }
    func select(_ id: String) async throws {
        guard try await spaces().contains(where: { $0.id == id }) else { throw EngramError.missing("library") }
        selectedID = id; generation = UUID().uuidString
    }
    func read() async throws -> LibrarySnapshot {
        let id = selectedID, lease = generation
        let root = try await base.read()
        guard lease == generation else { throw EngramError.conflict }
        var result = root.librarySpaces == nil ? root : LibrarySpaceScope.project(root, spaceIDs: [id])
        // A scoped export or assistant snapshot contains only this library,
        // without other libraries' names, memberships or empty folder paths.
        result.librarySpaces = nil
        result.repositoryContext = (root.repositoryContext ?? "memory") + "|library:" + lease
        return result
    }
    func commit(_ snapshot: LibrarySnapshot, expectedRevision: Int) async throws {
        let id = selectedID, lease = generation
        var root = try await base.read()
        guard generation == lease, root.revision == expectedRevision,
              snapshot.repositoryContext == (root.repositoryContext ?? "memory") + "|library:" + lease else { throw EngramError.conflict }
        try LibraryValidation.validate(snapshot)
        if root.librarySpaces == nil {
            var complete = snapshot; complete.repositoryContext = root.repositoryContext
            try await base.commit(complete, expectedRevision: expectedRevision)
            return
        }
        let before = root.librarySpaces == nil ? root : LibrarySpaceScope.project(root, spaceIDs: [id])
        func merge<T: Identifiable>(_ old: [T], _ visible: [T], _ next: [T]) throws -> [T] where T.ID == String {
            let visibleIDs = Set(visible.map(\.id))
            let other = old.filter { !visibleIDs.contains($0.id) }
            let otherIDs = Set(other.map(\.id))
            guard next.allSatisfy({ !otherIDs.contains($0.id) }) else { throw EngramError.invalid("This item already belongs to another library.") }
            return other + next
        }
        root.decks = try merge(root.decks, before.decks, snapshot.decks)
        root.notes = try merge(root.notes, before.notes, snapshot.notes)
        root.cards = try merge(root.cards, before.cards, snapshot.cards)
        root.reviews = try merge(root.reviews, before.reviews, snapshot.reviews)
        root.corrections = try merge(root.corrections, before.corrections, snapshot.corrections)
        root.importedReviews = try merge(root.importedReviews, before.importedReviews, snapshot.importedReviews)
        root.answerAttempts = try merge(root.answerAttempts ?? [], before.answerAttempts ?? [], snapshot.answerAttempts ?? [])
        root.folderDocuments = try merge(root.folderDocuments ?? [], before.folderDocuments ?? [], snapshot.folderDocuments ?? [])
        // Media is immutable, content-addressed and shared locally between libraries.
        let addedMedia = snapshot.media.filter { item in !root.media.contains { $0.name == item.name } }
        root.media += addedMedia
        if root.assistantState != nil || snapshot.assistantState != nil {
            var state = snapshot.assistantState ?? LearningAssistantState()
            let existing = root.assistantState ?? LearningAssistantState()
            let prior = before.assistantState ?? LearningAssistantState()
            state.conversations = try merge(existing.conversations, prior.conversations, state.conversations)
            state.runs = try merge(existing.runs, prior.runs, state.runs)
            state.memory = try merge(existing.memory, prior.memory, state.memory)
            root.assistantState = state
        }
        root.settings = snapshot.settings
        if before.session != nil || snapshot.session != nil { root.session = snapshot.session }
        if var catalog = root.librarySpaces {
            for deck in snapshot.decks { catalog.membership["deck:" + deck.id] = id }
            for file in snapshot.folderDocuments ?? [] { catalog.membership["file:" + file.id] = id }
            for chat in snapshot.assistantState?.conversations ?? [] { catalog.membership["chat:" + chat.id] = id }
            for run in snapshot.assistantState?.runs ?? [] { catalog.membership["chat:" + run.conversationID] = id }
            if let session = snapshot.session { catalog.membership["session:" + session.id] = id }
            if let index = catalog.spaces.firstIndex(where: { $0.id == id }) { catalog.spaces[index].folders = snapshot.folders ?? [] }
            root.librarySpaces = catalog
            root.folders = Array(Set(catalog.spaces.flatMap(\.folders))).sorted()
        } else { root.folders = snapshot.folders }
        guard generation == lease else { throw EngramError.conflict }
        try await base.commit(root, expectedRevision: expectedRevision)
    }
    func create(name: String, deviceOnly: Bool) async throws -> LibrarySpace {
        var root = try await base.read()
        var catalog = root.librarySpaces ?? LibrarySpaceCatalog()
        if root.librarySpaces == nil { catalog.spaces[0].folders = root.folders ?? [] }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !catalog.spaces.contains(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) else { throw EngramError.invalid("A library with this name already exists.") }
        let space = LibrarySpace(name: clean, deviceOnly: deviceOnly)
        catalog.spaces.append(space); try catalog.validate(); root.librarySpaces = catalog
        try await base.commit(root, expectedRevision: root.revision)
        return space
    }
    func moveDeck(_ deckID: String, to spaceID: String) async throws {
        var root = try await base.read()
        guard var catalog = root.librarySpaces, catalog.spaces.contains(where: { $0.id == spaceID }),
              let deck = root.liveDecks.first(where: { $0.id == deckID }),
              catalog.space(for: "deck:" + deckID) == selectedID else { throw EngramError.missing("library or deck") }
        if catalog.spaces.first(where: { $0.id == spaceID })?.deviceOnly == true,
           catalog.spaces.first(where: { $0.id == selectedID })?.deviceOnly != true {
            throw EngramError.invalid("Create or import content directly into a device-only library. Moving an existing cloud notebook cannot recall copies already uploaded.")
        }
        // Moving a parent keeps its child notebooks together.
        for item in root.decks where item.id == deckID || item.name.hasPrefix(deck.name + "::") {
            guard catalog.space(for: "deck:" + item.id) == selectedID else { continue }
            catalog.membership["deck:" + item.id] = spaceID
        }
        // Content moves retain schedules, IDs and linked tutoring history.
        for chat in root.assistantState?.conversations ?? [] where chat.id.contains(deckID) { catalog.membership["chat:" + chat.id] = spaceID }
        root.librarySpaces = catalog; root.session = nil
        try await base.commit(root, expectedRevision: root.revision)
    }
}
