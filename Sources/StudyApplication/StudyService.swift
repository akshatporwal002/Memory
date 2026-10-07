import Foundation
import LearningCore

/// Application use cases. Views share this actor; no database or vendor scheduler enters presentation code.
public actor StudyService {
    public enum DocumentDestination: Sendable { case notebook(String), folder(String) }
    var repository: any LibraryRepository
    private let libraries: LibrarySpaceRepository
    let scheduler: any Scheduler
    var learnerCoordinator: LearnerStudyCoordinator?
    public func configureLearnerModels(store: any LearnerModelStore, account: @escaping @Sendable () async -> UUID?) {
        guard learnerCoordinator == nil else { return }
        let coordinator = LearnerStudyCoordinator(store: store, spaces: libraries, accountProvider: account)
        learnerCoordinator = coordinator; repository = LearnerObservingRepository(base: libraries, coordinator: coordinator)
    }
    public init(repository: any LibraryRepository, scheduler: any Scheduler,
                learnerStore: (any LearnerModelStore)? = nil, learnerAccount: (@Sendable () async -> UUID?)? = nil) {
        let scoped = LibrarySpaceRepository(base: repository)
        self.libraries = scoped; self.scheduler = scheduler
        if let learnerStore, let learnerAccount {
            let coordinator = LearnerStudyCoordinator(store: learnerStore, spaces: scoped, accountProvider: learnerAccount)
            self.learnerCoordinator = coordinator; self.repository = LearnerObservingRepository(base: scoped, coordinator: coordinator)
        } else { self.learnerCoordinator = nil; self.repository = scoped }
    }
    public func librarySpaces() async throws -> [LibrarySpace] { try await libraries.spaces() }
    public func selectedLibraryID() async -> String { await libraries.selectedID }
    public func selectLibrary(_ id: String) async throws { try await libraries.select(id) }
    public func createLibrary(name: String, deviceOnly: Bool = false) async throws -> LibrarySpace { try await libraries.create(name: name, deviceOnly: deviceOnly) }
    public func moveDeckToLibrary(_ id: String, libraryID: String) async throws { try await libraries.moveDeck(id, to: libraryID) }
    public func activity(in library: LibrarySnapshot, period: ActivityPeriod, now: Date, interval: DateInterval? = nil) -> ActivitySummary {
        ActivitySummary.make(in: library, period: period, now: now, estimator: scheduler as? any MemoryEstimating, interval: interval)
    }
    public func memoryOutlook(for deck: Deck, in library: LibrarySnapshot, now: Date) -> DeckMemoryOutlook {
        DeckMemoryOutlook.make(deck: deck, library: library, now: now, estimator: scheduler as? any MemoryEstimating, scheduler: scheduler)
    }
    public func snapshot() async throws -> LibrarySnapshot { try await repository.read() }

    /// A reviewed PDF draft commits once, including its source evidence. No partial decks.
    @discardableResult public func createPDFDeck(id: String, title: String, record: PDFLearningRecord, now: Date = Date()) async throws -> Deck {
        guard UUID(uuidString: id) != nil, !record.items.isEmpty,
              record.items.allSatisfy({ $0.verified == true || $0.userEdited == true }) else {
            throw EngramError.invalid("Review the generated content before saving.")
        }
        try record.brief.validate(source: record.source)
        try PDFRetrieval.validate(record.items, against: record.source.chunks)
        var library = try await repository.read()
        let name = try deckName(title, in: library, excluding: id)
        if let existing = library.decks.first(where: { $0.id == id }) {
            guard !existing.deleted, existing.name == name, existing.pdfLearning == record else { throw EngramError.conflict }
            return existing
        }
        var deck = Deck(id: id, name: name, createdAt: now, modifiedAt: now)
        deck.pdfLearning = record; deck.documentFormatVersion = 2
        var blocks: [NotebookBlock] = []
        for item in record.items {
            let sourceText = item.citations.compactMap { citation -> String? in
                guard let passage = record.source.chunks.first(where: { $0.id == citation.passageID }) else { return nil }
                return "\(record.source.filename), p. \(passage.page): “\(citation.quote)”"
            }.joined(separator: "\n")
            if item.kind == "note" {
                blocks.append(NotebookBlock(id: id + "-" + item.id, text: "# \(item.prompt)\n\(item.answer)\n\nSource · \(sourceText)"))
            } else {
                let note = Note(id: id + "-" + item.id, deckID: id, kind: .basic,
                                front: DeckDocument.cardText(item.front), back: DeckDocument.cardText(item.back),
                                tags: ["pdf-generated"], source: sourceText, modifiedAt: now)
                _ = try CardRenderer.ordinals(for: NoteDraft(note: note))
                library.notes.append(note)
                library.cards.append(StudyCard(noteID: note.id, deckID: id, ordinal: 0,
                                              schedule: try scheduler.initialState(now: now, settings: library.settings)))
                blocks.append(NotebookBlock(id: note.id, kind: .question, text: item.front, answer: item.back, noteID: note.id))
            }
        }
        deck.notebookBlocks = blocks; deck.sourceDocument = NotebookDocument.source(blocks)
        library.decks.append(deck)
        try Task.checkCancellation()
        try await save(library)
        return deck
    }

    public func setDeckExamDate(id: String, date: Date?) async throws {
        guard date.map({ $0.timeIntervalSince1970.isFinite }) ?? true else { throw EngramError.invalid("Choose a valid exam date.") }
        var library = try await repository.read()
        guard let index = library.decks.firstIndex(where: { $0.id == id && !$0.deleted }) else { throw EngramError.missing("deck") }
        library.decks[index].examDate = date
        library.decks[index].modifiedAt = Date()
        try await save(library)
    }

    public func setDeckRetention(id: String, desiredRetention: Double?) async throws {
        guard desiredRetention.map({ $0.isFinite && (0.8...0.97).contains($0) }) ?? true else {
            throw EngramError.invalid("Choose a desired retention between 80% and 97%.")
        }
        var library = try await repository.read()
        guard let index = library.decks.firstIndex(where: { $0.id == id && !$0.deleted }) else { throw EngramError.missing("deck") }
        library.decks[index].desiredRetention = desiredRetention
        library.decks[index].modifiedAt = Date()
        if let current = library.session?.current, current.card.deckID == id, current.assessment == nil {
            library.session?.current = ReviewPresentation(card: current.card)
        }
        try await save(library)
    }

    /// Validate everything, then commit the deck and all of its questions together.
    @discardableResult public func createDeck(from draft: DeckCreationDraft, now: Date = Date()) async throws -> Deck {
        guard UUID(uuidString: draft.id) != nil,
              !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EngramError.invalid("Give your deck a title before creating it.")
        }
        let document = DeckDocument.parse(draft.document)
        if let issue = document.issues.first {
            throw EngramError.invalid(issue.line > 0 ? "Line \(issue.line): \(issue.message)" : issue.message)
        }
        var library = try await repository.read()
        let clean = try deckName(draft.deckName, in: library, excluding: draft.id)
        if let existing = library.decks.first(where: { $0.id == draft.id }) {
            guard !existing.deleted, existing.name == clean, existing.sourceDocument == draft.document else { throw EngramError.conflict }
            return existing
        }
        var deck = Deck(id: draft.id, name: clean, createdAt: now, modifiedAt: now, sourceDocument: draft.document)
        deck.documentFormatVersion = 2
        library.decks.append(deck)
        for (index, question) in document.questions.enumerated() {
            let noteDraft = NoteDraft(deckID: deck.id, front: DeckDocument.cardText(question.front), back: DeckDocument.cardText(question.back))
            _ = try CardRenderer.ordinals(for: noteDraft)
            let note = Note(id: "\(deck.id)-note-\(index)", deckID: deck.id, kind: .basic,
                front: noteDraft.front, back: noteDraft.back, modifiedAt: now)
            library.notes.append(note)
            library.cards.append(StudyCard(noteID: note.id, deckID: deck.id, ordinal: 0,
                schedule: try scheduler.initialState(now: now, settings: library.settings)))
        }
        try await save(library)
        return deck
    }

    /// Commit notebook blocks and their linked cards atomically. A stale editor cannot overwrite newer work.
    public func saveNotebook(deckID: String, blocks: [NotebookBlock], expectedRevision: Int, originalBlocks: [NotebookBlock]? = nil, now: Date = Date()) async throws {
        var library = try await repository.read()
        guard let deckIndex = library.decks.firstIndex(where: { $0.id == deckID && !$0.deleted }) else { throw EngramError.missing("deck") }
        let previous = NotebookDocument.blocks(for: library.decks[deckIndex], in: library)
        guard library.revision == expectedRevision || originalBlocks == previous else {
            throw EngramError.invalid("This notebook has newer saved changes. Your draft is kept on this device. Use Notebook options to reload the saved version after keeping any writing you need.")
        }
        guard Set(blocks.map(\.id)).count == blocks.count, blocks.allSatisfy({ !$0.id.isEmpty }),
              blocks.filter({ $0.kind == .question }).count <= 1_000,
              NotebookDocument.source(blocks).utf8.count <= DeckDocument.byteLimit else {
            throw EngramError.invalid("Keep your notebook under 1 MB and 1,000 questions, with unique blocks.")
        }
        let priorIDs = Set(previous.compactMap(\.noteID))
        let requestedIDs = blocks.compactMap(\.noteID)
        guard Set(requestedIDs).count == requestedIDs.count, Set(requestedIDs).isSubset(of: priorIDs),
              blocks.allSatisfy({ $0.kind == .question || $0.noteID == nil }) else { throw EngramError.conflict }
        var saved = blocks
        for index in saved.indices where saved[index].kind == .question {
            let front = DeckDocument.cardText(saved[index].text)
            let back = DeckDocument.cardText(saved[index].answer)
            _ = try CardRenderer.ordinals(for: NoteDraft(deckID: deckID, front: front, back: back))
            if let id = saved[index].noteID {
                guard let ni = library.notes.firstIndex(where: { $0.id == id && !$0.deleted && $0.deckID == deckID }) else { throw EngramError.conflict }
                if library.notes[ni].front != front || library.notes[ni].back != back {
                    library.notes[ni].front = front; library.notes[ni].back = back; library.notes[ni].modifiedAt = now
                    library.notes[ni].multipleChoice = MultipleChoiceQuestion.parse(front: front, back: back)
                    for ci in library.cards.indices where library.cards[ci].noteID == id { library.cards[ci].version += 1 }
                }
            } else {
                let note = Note(deckID: deckID, kind: .basic, front: front, back: back, modifiedAt: now)
                library.notes.append(note)
                library.cards.append(StudyCard(noteID: note.id, deckID: deckID, ordinal: 0,
                    schedule: try scheduler.initialState(now: now, settings: library.settings)))
                saved[index].noteID = note.id
            }
        }
        let removed = priorIDs.subtracting(requestedIDs)
        for ni in library.notes.indices where removed.contains(library.notes[ni].id) { library.notes[ni].deleted = true }
        for ci in library.cards.indices where removed.contains(library.cards[ci].noteID) {
            library.cards[ci].retired = true; library.cards[ci].version += 1
        }
        library.decks[deckIndex].notebookBlocks = saved
        library.decks[deckIndex].sourceDocument = NotebookDocument.source(saved)
        library.decks[deckIndex].modifiedAt = now
        invalidateSessionIfNeeded(&library)
        try await save(library)
    }

    /// Keep materialized notebook text current after card edits, moves and deletions.
    func syncNotebooks(_ library: inout LibrarySnapshot, deckIDs: Set<String>) {
        for index in library.decks.indices where deckIDs.contains(library.decks[index].id) {
            let deck = library.decks[index]
            guard deck.sourceDocument != nil || deck.notebookBlocks != nil else { continue }
            let blocks = NotebookDocument.blocks(for: deck, in: library)
            library.decks[index].notebookBlocks = blocks
            library.decks[index].sourceDocument = NotebookDocument.source(blocks)
        }
    }

    @discardableResult public func createDeck(name: String, now: Date = Date()) async throws -> Deck {
        var library = try await repository.read()
        let clean = try deckName(name, in: library)
        let deck = Deck(name: clean, createdAt: now, modifiedAt: now); library.decks.append(deck)
        try await save(library); return deck
    }
    public func createFolder(name: String, in parent: String = "") async throws -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.contains("::") else { throw EngramError.invalid("Enter one folder name at a time.") }
        let path = parent.isEmpty ? clean : parent + "::" + clean
        try LibraryValidation.validateFolderPath(path)
        var library = try await repository.read()
        let existing = library.folders ?? []
        guard parent.isEmpty || existing.contains(parent) ||
              existing.contains(where: { $0.hasPrefix(parent + "::") }) ||
              library.liveDecks.contains(where: { $0.name == parent || $0.name.hasPrefix(parent + "::") }) else {
            throw EngramError.missing("parent folder")
        }
        guard !library.liveDecks.contains(where: { $0.name.caseInsensitiveCompare(path) == .orderedSame }) else {
            throw EngramError.invalid("A notebook already uses that name. Choose another folder name.")
        }
        guard !existing.contains(where: { $0.caseInsensitiveCompare(path) == .orderedSame }) else {
            throw EngramError.invalid("That folder already exists.")
        }
        library.folders = existing + [path]
        try await save(library)
        return path
    }
    public func removeEmptyFolder(path: String) async throws {
        var library = try await repository.read()
        guard library.folders?.contains(path) == true else { throw EngramError.missing("folder") }
        guard !library.liveDecks.contains(where: { $0.name == path || $0.name.hasPrefix(path + "::") }),
              !(library.folderDocuments ?? []).contains(where: { $0.folderPath == path }),
              !(library.folders ?? []).contains(where: { $0.hasPrefix(path + "::") }) else {
            throw EngramError.invalid("Move or remove the contents before deleting this folder.")
        }
        library.folders?.removeAll { $0 == path }
        try await save(library)
    }
    public func renameDeck(id: String, name: String) async throws {
        var library = try await repository.read()
        guard let index = library.decks.firstIndex(where: { $0.id == id && !$0.deleted }) else { throw EngramError.missing("deck") }
        let clean = try deckName(name, in: library, excluding: id)
        let oldName = library.decks[index].name
        let affected = library.decks.indices.filter { !library.decks[$0].deleted && (library.decks[$0].id == id || library.decks[$0].name.hasPrefix(oldName + "::")) }
        let affectedIDs = Set(affected.map { library.decks[$0].id })
        let mappings = affected.map { index in (index, clean + library.decks[index].name.dropFirst(oldName.count)) }
        for (_, replacement) in mappings {
            guard !library.decks.contains(where: { !$0.deleted && !affectedIDs.contains($0.id) && $0.name.caseInsensitiveCompare(replacement) == .orderedSame }) else { throw EngramError.invalid("Renaming would collide with an existing subdeck.") }
        }
        for (index, replacement) in mappings { library.decks[index].name = replacement; library.decks[index].modifiedAt = Date() }
        try await save(library)
    }
    public func moveDeck(id: String, toFolder path: String) async throws {
        var library = try await repository.read()
        guard let deck = library.liveDecks.first(where: { $0.id == id }) else { throw EngramError.missing("notebook") }
        try ensureDestination(path, in:&library)
        guard path != deck.name && !path.hasPrefix(deck.name + "::") else { throw EngramError.invalid("A notebook cannot contain itself.") }
        let leaf = deck.name.components(separatedBy:"::").last ?? deck.name
        let target = path.isEmpty ? leaf : path + "::" + leaf
        if target == deck.name { return }
        let clean = try deckName(target,in:library,excluding:id)
        let affected = library.decks.indices.filter { !library.decks[$0].deleted && (library.decks[$0].id == id || library.decks[$0].name.hasPrefix(deck.name + "::")) }
        let affectedIDs = Set(affected.map { library.decks[$0].id })
        for index in affected {
            let replacement = clean + library.decks[index].name.dropFirst(deck.name.count)
            guard !library.liveDecks.contains(where: { !affectedIDs.contains($0.id) && $0.name.caseInsensitiveCompare(replacement) == .orderedSame }) else { throw EngramError.conflict }
            library.decks[index].name = replacement
            library.decks[index].modifiedAt = Date()
        }
        try await save(library)
    }
    public func moveFolder(path: String, toFolder destination: String) async throws {
        var library = try await repository.read()
        guard (library.folders ?? []).contains(path) else { throw EngramError.missing("folder") }
        try ensureDestination(destination, in:&library)
        guard destination != path && !destination.hasPrefix(path + "::") else { throw EngramError.invalid("A folder cannot contain itself.") }
        let leaf = path.components(separatedBy:"::").last ?? path
        let target = destination.isEmpty ? leaf : destination + "::" + leaf
        if target == path { return }
        let affected = (library.folders ?? []).filter { $0 == path || $0.hasPrefix(path + "::") }
        let replacements = affected.map { target + $0.dropFirst(path.count) }
        let unaffected = (library.folders ?? []).filter { !affected.contains($0) }
        guard replacements.allSatisfy({ candidate in !unaffected.contains(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) }),
              !library.liveDecks.contains(where: { $0.name.caseInsensitiveCompare(target) == .orderedSame }) else {
            throw EngramError.invalid("That destination already has an item with this name.")
        }
        library.folders = unaffected + replacements
        for index in library.decks.indices where !library.decks[index].deleted && library.decks[index].name.hasPrefix(path + "::") {
            let newName = target + library.decks[index].name.dropFirst(path.count)
            guard !library.liveDecks.contains(where: { $0.id != library.decks[index].id && $0.name.caseInsensitiveCompare(newName) == .orderedSame }) else { throw EngramError.conflict }
            library.decks[index].name = newName
            library.decks[index].modifiedAt = Date()
        }
        for index in (library.folderDocuments ?? []).indices where library.folderDocuments![index].folderPath == path || library.folderDocuments![index].folderPath.hasPrefix(path + "::") {
            library.folderDocuments![index].folderPath = target + library.folderDocuments![index].folderPath.dropFirst(path.count)
        }
        try await save(library)
    }
    /// Cover assets participate in the existing media limits and native backup.
    /// Retain replaced media: imported notes or source evidence may still reference it.
    public func setDeckCover(id: String, jpeg: Data?, now: Date = Date()) async throws {
        var library = try await repository.read()
        guard let index = library.decks.firstIndex(where: { $0.id == id && !$0.deleted }) else { throw EngramError.missing("deck") }
        if let jpeg {
            guard jpeg.count <= 1_024 * 1_024, jpeg.starts(with: [0xFF, 0xD8, 0xFF]) else {
                throw EngramError.invalid("Choose a JPEG cover smaller than 1 MB.")
            }
            let name = "engram-cover-\(UUID().uuidString).jpg"
            library.media.append(MediaFile(name: name, data: jpeg))
            library.decks[index].coverMediaName = name
        } else { library.decks[index].coverMediaName = nil }
        library.decks[index].modifiedAt = now
        try await save(library)
    }
    public func addDocument(_ document: LibraryDocument, to deckID: String, now: Date = Date()) async throws {
        try document.validate()
        var library = try await repository.read()
        guard !allDocumentIDs(in:library).contains(document.id) else { throw EngramError.conflict }
        guard let index = library.decks.firstIndex(where: { $0.id == deckID && !$0.deleted }) else { throw EngramError.missing("notebook") }
        var documents = library.decks[index].documents ?? []
        guard documents.count < 20,
              documents.reduce(0, { $0 + $1.originalData.count }) + document.originalData.count <= 25_000_000,
              documents.reduce(0, { $0 + $1.pages.reduce(0, { $0 + $1.text.utf8.count }) }) + document.pages.reduce(0, { $0 + $1.text.utf8.count }) <= 4_000_000 else {
            throw EngramError.invalid("This notebook can hold up to 20 source files, 25 MB of originals and 4 MB of extracted text.")
        }
        documents.append(document)
        library.decks[index].documents = documents
        library.decks[index].modifiedAt = now
        try await save(library)
    }
    public func addDocument(_ document: LibraryDocument, toFolder path: String) async throws {
        try document.validate()
        var library = try await repository.read()
        try ensureDestination(path,in:&library)
        guard !allDocumentIDs(in:library).contains(document.id) else { throw EngramError.conflict }
        library.folderDocuments = (library.folderDocuments ?? []) + [LibraryFolderDocument(folderPath:path,document:document)]
        try await save(library)
    }
    public func moveDocument(id: String, to destination: DocumentDestination, now: Date = Date()) async throws {
        var library = try await repository.read()
        let document: LibraryDocument
        if let index = library.decks.firstIndex(where: { !$0.deleted && ($0.documents ?? []).contains(where: { $0.id == id }) }) {
            guard let source = library.decks[index].documents?.first(where: { $0.id == id }) else { throw EngramError.missing("source file") }
            document = source
            library.decks[index].documents?.removeAll { $0.id == id }
            library.decks[index].modifiedAt = now
        } else if let item = library.folderDocuments?.first(where: { $0.id == id }) {
            document = item.document
            library.folderDocuments?.removeAll { $0.id == id }
        } else { throw EngramError.missing("source file") }
        switch destination {
        case .folder(let path):
            try ensureDestination(path,in:&library)
            library.folderDocuments = (library.folderDocuments ?? []) + [LibraryFolderDocument(folderPath:path,document:document)]
        case .notebook(let deckID):
            guard let index = library.decks.firstIndex(where: { $0.id == deckID && !$0.deleted }) else { throw EngramError.missing("notebook") }
            library.decks[index].documents = (library.decks[index].documents ?? []) + [document]
            library.decks[index].modifiedAt = now
        }
        try await save(library)
    }
    public func removeFolderDocument(id: String) async throws {
        var library = try await repository.read()
        guard (library.folderDocuments ?? []).contains(where: { $0.id == id }) else { throw EngramError.missing("source file") }
        library.folderDocuments?.removeAll { $0.id == id }
        try await save(library)
    }
    private func ensureDestination(_ path: String,in library: inout LibrarySnapshot) throws {
        guard !path.isEmpty else { return }
        try LibraryValidation.validateFolderPath(path)
        if (library.folders ?? []).contains(path) { return }
        guard library.liveDecks.contains(where: { $0.name == path || $0.name.hasPrefix(path + "::") }) else { throw EngramError.missing("destination folder") }
        library.folders = (library.folders ?? []) + [path]
    }
    private func allDocumentIDs(in library: LibrarySnapshot) -> Set<String> {
        Set(library.decks.flatMap { ($0.documents ?? []).map(\.id) } + (library.folderDocuments ?? []).map(\.id))
    }
    public func removeDocument(id: String, from deckID: String, now: Date = Date()) async throws {
        var library = try await repository.read()
        guard let index = library.decks.firstIndex(where: { $0.id == deckID && !$0.deleted }),
              library.decks[index].documents?.contains(where: { $0.id == id }) == true else { throw EngramError.missing("source file") }
        library.decks[index].documents?.removeAll { $0.id == id }
        library.decks[index].modifiedAt = now
        try await save(library)
    }
    /// Caller presents a destructive confirmation. Tombstones retain historical evidence for backup.
    public func deleteDeck(id: String) async throws {
        var library = try await repository.read()
        guard let deck = library.decks.first(where: { $0.id == id && !$0.deleted }) else { throw EngramError.missing("deck") }
        let affected = Set(library.decks.filter { $0.id == id || $0.name.hasPrefix(deck.name + "::") }.map(\.id))
        for i in library.decks.indices where affected.contains(library.decks[i].id) { library.decks[i].deleted = true }
        for i in library.notes.indices where affected.contains(library.notes[i].deckID) { library.notes[i].deleted = true }
        for i in library.cards.indices where affected.contains(library.cards[i].deckID) { library.cards[i].retired = true; library.cards[i].version += 1 }
        invalidateSessionIfNeeded(&library)
        try await save(library)
    }
    @discardableResult public func saveNote(_ draft: NoteDraft, now: Date) async throws -> Note {
        let ordinals = try CardRenderer.ordinals(for: draft)
        var library = try await repository.read()
        guard library.decks.contains(where: { $0.id == draft.deckID && !$0.deleted }) else { throw EngramError.missing("destination deck") }
        let prior = library.notes.first(where: { $0.id == draft.id && !$0.deleted })
        if draft.id != nil && prior == nil { throw EngramError.missing("note") }
        if let prior, prior.kind != draft.kind { throw EngramError.invalid("Changing a saved note's type needs a migration. Create a new note instead.") }
        let tags = Array(Set(draft.tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        guard tags.count <= 100, tags.allSatisfy({ $0.count <= 100 && !$0.contains(where: \.isWhitespace) }) else { throw EngramError.invalid("Use at most 100 tags, without spaces, and 100 characters per tag.") }
        guard draft.questionType.map({ !$0.isEmpty && $0.count <= 80 && !$0.contains(where: \.isWhitespace) }) ?? true else {
            throw EngramError.invalid("Use a question type identifier of at most 80 characters without spaces.")
        }
        var note = Note(id: prior?.id ?? UUID().uuidString, deckID: draft.deckID, kind: draft.kind, front: draft.front,
            back: draft.back, tags: tags, source: draft.source, origin: prior?.origin, modifiedAt: now)
        note.questionType = draft.questionType ?? prior?.questionType
        if let prior, prior.front == note.front, prior.back == note.back, prior.source == note.source { note.questionFamily = prior.questionFamily }
        if let index = library.notes.firstIndex(where: { $0.id == note.id }) { library.notes[index] = note } else { library.notes.append(note) }
        for i in library.cards.indices where library.cards[i].noteID == note.id {
            library.cards[i].deckID = draft.deckID
            library.cards[i].retired = !ordinals.contains(library.cards[i].ordinal)
            library.cards[i].version += 1
        }
        for ordinal in ordinals where !library.cards.contains(where: { $0.noteID == note.id && $0.ordinal == ordinal }) {
            library.cards.append(StudyCard(noteID: note.id, deckID: note.deckID, ordinal: ordinal,
                schedule: try scheduler.initialState(now: now, settings: library.settings)))
        }
        syncNotebooks(&library, deckIDs: Set([prior?.deckID, note.deckID].compactMap { $0 }))
        invalidateSessionIfNeeded(&library)
        try await save(library); return note
    }
    public func deleteNote(id: String) async throws {
        var library = try await repository.read()
        guard let index = library.notes.firstIndex(where: { $0.id == id && !$0.deleted }) else { throw EngramError.missing("note") }
        library.notes[index].deleted = true
        syncNotebooks(&library, deckIDs: [library.notes[index].deckID])
        for i in library.cards.indices where library.cards[i].noteID == id { library.cards[i].retired = true; library.cards[i].version += 1 }
        invalidateSessionIfNeeded(&library); try await save(library)
    }
    public func setDeckSuspended(id: String, suspended: Bool) async throws {
        var library = try await repository.read()
        guard let index = library.decks.firstIndex(where: { $0.id == id && !$0.deleted }) else { throw EngramError.missing("deck") }
        library.decks[index].studySuspended = suspended ? true : nil
        library.decks[index].modifiedAt = Date()
        invalidateSessionIfNeeded(&library)
        try await save(library)
    }
    public func setSuspended(cardID: String, suspended: Bool) async throws {
        var library = try await repository.read()
        guard let index = library.cards.firstIndex(where: { $0.id == cardID && !$0.retired }) else { throw EngramError.missing("card") }
        library.cards[index].suspended = suspended; library.cards[index].version += 1
        invalidateSessionIfNeeded(&library); try await save(library)
    }
    public func updateSettings(_ settings: StudySettings) async throws {
        var library = try await repository.read()
        var updated = settings; updated.version = library.settings.version + 1
        library.settings = updated
        if let current = library.session?.current { library.session?.current = ReviewPresentation(card: current.card) }
        try await save(library)
    }
    public func search(_ query: String, deckID: String? = nil) async throws -> [Note] {
        let library = try await repository.read()
        return Self.search(query, deckID: deckID, in: library)
    }
    public static func search(_ query: String, deckID: String?, in library: LibrarySnapshot) -> [Note] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return library.liveNotes.filter { note in
            guard deckID == nil || note.deckID == deckID else { return false }
            let haystack = [note.front, note.back, note.source, note.tags.joined(separator: " ")].joined(separator: " ").lowercased()
            return terms.allSatisfy { term in
                if term.hasPrefix("tag:") { return note.tags.contains { $0.lowercased() == String(term.dropFirst(4)) } }
                if term == "is:suspended" { return library.liveCards.contains { $0.noteID == note.id && $0.suspended } }
                return haystack.contains(term)
            }
        }.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    public func startSession(deckID: String?, now: Date) async throws -> StudySession {
        var library = try await repository.read()
        if let existing = library.session, existing.deckID == deckID, let current = existing.current,
           (current.assessment != nil || library.cards.contains(where: { $0.id == current.card.id && $0.version == current.card.version && !$0.retired && !$0.suspended && !library.isDeckSuspended($0.deckID) })) {
            return existing
        }
        let queue = QueuePolicy.dueCards(in: library, deckID: deckID, now: now)
        var session = StudySession(deckID: deckID, startedAt: now, queue: queue.map(\.id), current: queue.first.map(ReviewPresentation.init))
        session.nextLearningDue = nextLearningDue(in: library, deckID: deckID, now: now)
        library.session = session; try await save(library); return session
    }
    public func startDeadlineSession(deckID: String, now: Date) async throws -> StudySession {
        guard let coordinator = learnerCoordinator else { throw LearnerError.unavailable }
        let context = try await coordinator.context()
        let plan = try await deadlinePlan(deckID: deckID, now: now, saveForecast: true)
        guard plan.staleItems == 0 else { throw EngramError.invalid("Target cards changed. Save a new deadline goal before studying.") }
        var library = try await repository.read()
        try await coordinator.check(context)
        guard library.repositoryContext == context.snapshot.repositoryContext, library.revision == context.snapshot.revision else { throw LearnerError.conflict }
        guard library.session?.current == nil else { throw EngramError.invalid("Finish or close your current review before starting the deadline plan.") }
        let ids = plan.actions.filter { $0.date <= now }.map(\.cardID)
        let eligible = QueuePolicy.eligibleCards(in: library, deckID: deckID)
        let cards = ids.compactMap { id in eligible.first { $0.id == id } }
        guard !cards.isEmpty else { throw EngramError.invalid("No deadline practice is planned right now.") }
        var session = StudySession(deckID: deckID, startedAt: now, queue: cards.map(\.id), current: cards.first.map(ReviewPresentation.init))
        session.deadlineCardIDs = cards.map(\.id)
        library.session = session; try await save(library); return session
    }
    /// Rechecks cards that became due, including short learning steps. Does not disturb a visible prompt.
    public func refreshSession(now: Date) async throws -> StudySession? {
        var library = try await repository.read()
        guard var session = library.session else { return nil }
        if let item = session.current,
           (item.assessment != nil || library.cards.contains(where: { $0.id == item.card.id && $0.version == item.card.version && !$0.retired && !$0.suspended && !library.isDeckSuspended($0.deckID) })) { return session }
        refresh(&session, in: library, now: now); library.session = session
        try await save(library); return session
    }
    public func reveal(sessionID: String, presentationID: String, now: Date) async throws -> ReviewPresentation {
        var library = try await repository.read()
        guard var session = library.session, session.id == sessionID,
              var item = session.current, item.presentationID == presentationID else { throw EngramError.conflict }
        guard library.cards.contains(where: { $0.id == item.card.id && $0.version == item.card.version && !$0.retired && !$0.suspended && !library.isDeckSuspended($0.deckID) }) else { throw EngramError.conflict }
        if item.revealedAt != nil { return item }
        let history = library.activeReviews.filter { $0.cardID == item.card.id }
        var schedulingSettings = library.settings
        if let target = library.liveDecks.first(where: { $0.id == item.card.deckID })?.desiredRetention {
            schedulingSettings.desiredRetention = target
        }
        item.outcomes = try scheduler.outcomes(state: item.card.schedule, history: history, now: now, settings: schedulingSettings)
        guard item.outcomes.count == 4 else { throw EngramError.invalid("Scheduler did not supply all four grades.") }
        item.revealedAt = now; session.current = item; library.session = session
        try await save(library); return item
    }
    public func grade(sessionID: String, presentationID: String, rating: Grade, mutationID: String, now: Date) async throws {
        var library = try await repository.read()
        if let previous = library.reviews.first(where: { $0.id == mutationID }) {
            guard previous.sessionID == sessionID, previous.rating == rating else { throw EngramError.conflict }
            return
        }
        guard !mutationID.isEmpty, var session = library.session, session.id == sessionID,
              let item = session.current, item.presentationID == presentationID,
              let revealedAt = item.revealedAt, now >= revealedAt,
              let outcome = item.outcomes[rating],
              let index = library.cards.firstIndex(where: { $0.id == item.card.id && !$0.retired && !$0.suspended && !library.isDeckSuspended($0.deckID) }),
              library.cards[index].version == item.card.version,
              outcome.settingsVersion == library.settings.version else { throw EngramError.conflict }
        library.cards[index].schedule = outcome; library.cards[index].version += 1
        library.reviews.append(ReviewEvent(id: mutationID, cardID: item.card.id, deckID: item.card.deckID, sessionID: session.id,
            rating: rating, reviewedAt: revealedAt, committedAt: now, before: item.card.schedule, after: outcome))
        library.reviews[library.reviews.count - 1].settingsSnapshot = library.settings
        library.reviews[library.reviews.count - 1].presentationID = presentationID
        library.reviews[library.reviews.count - 1].gradingMethod = "manual"
        library.reviews[library.reviews.count - 1].questionType = library.liveNotes.first { $0.id == item.card.noteID }?.canonicalQuestionType
        library.reviews[library.reviews.count - 1].subject = library.liveNotes.first { $0.id == item.card.noteID }?.declaredSubject
        library.reviews[library.reviews.count - 1].questionSubtype = library.liveNotes.first { $0.id == item.card.noteID }?.declaredQuestionSubtype
        library.reviews[library.reviews.count - 1].questionSchemaVersion = 1
        library.reviews[library.reviews.count - 1].inputModality = "manual"
        session.completed += 1
        refresh(&session, in: library, now: now); library.session = session
        try await save(library)
    }
    public func undo(sessionID: String, now: Date) async throws {
        var library = try await repository.read()
        guard var session = library.session, session.id == sessionID,
              let event = library.activeReviews.last(where: { $0.sessionID == sessionID }),
              let index = library.cards.firstIndex(where: { $0.id == event.cardID && !$0.retired && !$0.suspended && !library.isDeckSuspended($0.deckID) }),
              library.cards[index].schedule == event.after else { throw EngramError.invalid("There is no unchanged review in this session to undo.") }
        library.cards[index].schedule = event.before; library.cards[index].version += 1
        library.corrections.append(ReviewCorrection(reviewID: event.id, createdAt: now))
        session.completed = max(0, session.completed - 1)
        refresh(&session, in: library, now: now)
        let restored = library.cards[index]
        session.current = ReviewPresentation(card: restored)
        session.queue.removeAll { $0 == restored.id }; session.queue.insert(restored.id, at: 0)
        library.session = session; try await save(library)
    }
    /// Exiting the review UI needs no mutation; persisted session and committed grades remain resumable.
    public func endSession() async throws {
        var library = try await repository.read(); library.session = nil; try await save(library)
    }
    /// Only a fully inspected/confirmed restore invokes this operation. Export pre-restore backup first.
    public func restore(_ candidate: LibrarySnapshot, expectedRevision: Int,expectedContext: String? = nil) async throws {
        try LibraryValidation.validate(candidate)
        var restored = candidate; restored.revision = expectedRevision; restored.session = nil
        let current = try await repository.read()
        guard current.revision == expectedRevision else { throw EngramError.conflict }
        if let expectedContext { guard current.repositoryContext == expectedContext else { throw EngramError.conflict } }
        restored.repositoryContext = current.repositoryContext
        try await repository.commit(restored, expectedRevision: expectedRevision)
    }

    private func save(_ library: LibrarySnapshot) async throws { try await repository.commit(library, expectedRevision: library.revision) }
    private func deckName(_ value: String, in library: LibrarySnapshot, excluding: String? = nil) throws -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 200, clean.components(separatedBy: "::").allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { throw EngramError.invalid("Enter a deck name up to 200 characters. Separate nested decks with ::.") }
        guard !library.liveDecks.contains(where: { $0.id != excluding && $0.name.caseInsensitiveCompare(clean) == .orderedSame }) else { throw EngramError.invalid("A deck with this name already exists.") }
        return clean
    }
    private func refresh(_ session: inout StudySession, in library: LibrarySnapshot, now: Date) {
        if session.deadlineCardIDs != nil {
            let cards = plannedSessionCards(session, in: library, now: now)
            session.queue = cards.map(\.id); session.current = cards.first.map(ReviewPresentation.init); session.nextLearningDue = nil
            return
        }
        let queue = QueuePolicy.dueCards(in: library, deckID: session.deckID, now: now).filter { !(session.skippedCardIDs ?? []).contains($0.id) }
        session.queue = queue.map(\.id); session.current = queue.first.map(ReviewPresentation.init)
        session.nextLearningDue = nextLearningDue(in: library, deckID: session.deckID, now: now)
    }
    private func nextLearningDue(in library: LibrarySnapshot, deckID: String?, now: Date) -> Date? {
        QueuePolicy.eligibleCards(in: library, deckID: deckID).filter { ($0.schedule.phase == .learning || $0.schedule.phase == .relearning) && $0.schedule.due > now }.map(\.schedule.due).min()
    }
    private func invalidateSessionIfNeeded(_ library: inout LibrarySnapshot) {
        guard let current = library.session?.current else { return }
        if !library.cards.contains(where: { $0.id == current.card.id && $0.version == current.card.version && !$0.retired && !$0.suspended && !library.isDeckSuspended($0.deckID) }) {
            library.session?.current = nil
        }
    }
}
