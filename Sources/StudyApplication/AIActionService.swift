import Foundation
import LearningCore

public enum AIContentOperation: Sendable {
    case createDeck(String), renameDeck(String,String), saveNote(NoteDraft), deleteNote(String), deleteDeck(String)
    case saveNotebook(String,[NotebookBlock]), retention(String,Double?), suspend(String,Bool), settings(StudySettings)
}
extension StudyService {
    public func saveConversation(_ conversation: LearningConversation) async throws {
        guard conversation.messages.count <= 2000, conversation.messages.allSatisfy({ $0.text.utf8.count <= 200_000 }),
              (conversation.toolHistoryJSON?.count ?? 0) <= 2_000_000 else { throw EngramError.invalid("Conversation is too large. Start a new chat.") }
        var library = try await repository.read(), state = LearningAssistantState()
        state = library.assistantState ?? state
        if let index = state.conversations.firstIndex(where: { $0.id == conversation.id }) { state.conversations[index] = conversation }
        else { state.conversations.append(conversation) }
        library.assistantState = state
        try await repository.commit(library,expectedRevision:library.revision)
    }
    public func recordAIAction(runID: String, conversationID: String, record: AIActionRecord) async throws {
        var library = try await repository.read()
        Self.appendAIRecord(record,runID:runID,conversationID:conversationID,to:&library)
        try await repository.commit(library,expectedRevision:library.revision)
    }
    public func setAIRunStatus(_ id: String,status: String) async throws {
        var library = try await repository.read()
        guard var state = library.assistantState, let index = state.runs.firstIndex(where: { $0.id == id }) else { return }
        state.runs[index].status = status; library.assistantState = state
        try await repository.commit(library,expectedRevision:library.revision)
    }
    public func executeAIContent(_ operation: AIContentOperation, runID: String, conversationID: String, callID: String,
                                 name: String, arguments: String, expectedRevision: Int, now: Date = Date()) async throws -> AIActionRecord {
        let library = try await repository.read()
        if let existing = library.assistantState?.runs.flatMap(\.actions).first(where: { $0.id == callID && $0.status == "completed" }) { guard existing.name == name, existing.arguments == arguments else { throw EngramError.conflict }; return existing }
        guard library.revision == expectedRevision else { throw EngramError.conflict }
        let journal = AIJournalRepository(base:repository,runID:runID,conversationID:conversationID,callID:callID,name:name,arguments:arguments)
        let service = StudyService(repository:journal,scheduler:scheduler)
        switch operation {
        case .createDeck(let name): _ = try await service.createDeck(name:name,now:now)
        case .renameDeck(let id,let name): try await service.renameDeck(id:id,name:name)
        case .saveNote(let draft): _ = try await service.saveNote(draft,now:now)
        case .deleteNote(let id): try await service.deleteNote(id:id)
        case .deleteDeck(let id): try await service.deleteDeck(id:id)
        case .saveNotebook(let id,let blocks): try await service.saveNotebook(deckID:id,blocks:blocks,expectedRevision:expectedRevision,now:now)
        case .retention(let id,let value): try await service.setDeckRetention(id:id,desiredRetention:value)
        case .suspend(let id,let value): try await service.setSuspended(cardID:id,suspended:value)
        case .settings(let settings): try await service.updateSettings(settings)
        }
        guard let record = try await repository.read().assistantState?.runs.flatMap(\.actions).first(where: { $0.id == callID }) else { throw EngramError.storage("Action journal missing") }
        return record
    }
    static func appendAIRecord(_ record: AIActionRecord,runID: String,conversationID: String,to library: inout LibrarySnapshot) {
        var state = library.assistantState ?? LearningAssistantState()
        let ri: Int
        if let index = state.runs.firstIndex(where: { $0.id == runID }) { ri = index }
        else { state.runs.append(AIActionRun(id:runID,conversationID:conversationID)); ri = state.runs.count - 1 }
        if let index = state.runs[ri].actions.firstIndex(where: { $0.id == record.id }) { state.runs[ri].actions[index] = record }
        else { state.runs[ri].actions.append(record) }
        library.assistantState = state
    }
    public func undoAIChange(runID: String,actionID: String,changeID: String,now: Date = Date()) async throws {
        try await undoAIChange(runID:runID,actionID:actionID,changeID:changeID,now:now,preserveMetadata:false)
    }
    public func undoAIRun(id: String,now: Date = Date()) async throws {
        let original = try await repository.read()
        guard let run = original.assistantState?.runs.first(where: { $0.id == id }) else { throw EngramError.missing("run") }
        let working = UndoWorkingRepository(original)
        let service = StudyService(repository:working,scheduler:scheduler)
        for action in run.actions.reversed() {
            for change in action.changes.reversed() where change.undoneAt == nil {
                try await service.undoAIChange(runID:id,actionID:action.id,changeID:change.id,now:now,preserveMetadata:true)
            }
        }
        var final = await working.read()
        final.revision = original.revision
        syncNotebooks(&final,deckIDs:Set(final.notes.filter { note in note != original.notes.first(where: { $0.id == note.id }) }.map(\.deckID)))
        for index in final.notes.indices where final.notes[index] != original.notes.first(where: { $0.id == final.notes[index].id }) { final.notes[index].modifiedAt = now }
        for index in final.decks.indices where final.decks[index] != original.decks.first(where: { $0.id == final.decks[index].id }) { final.decks[index].modifiedAt = now }
        try await repository.commit(final,expectedRevision:original.revision)
    }
    private func undoAIChange(runID: String,actionID: String,changeID: String,now: Date,preserveMetadata: Bool) async throws {
        var library = try await repository.read()
        guard var state = library.assistantState, let ri = state.runs.firstIndex(where: { $0.id == runID }),
              let ai = state.runs[ri].actions.firstIndex(where: { $0.id == actionID }),
              let ci = state.runs[ri].actions[ai].changes.firstIndex(where: { $0.id == changeID }) else { throw EngramError.missing("action") }
        let change = state.runs[ri].actions[ai].changes[ci]
        guard change.undoneAt == nil else { return }
        if let after = change.afterDeck {
            guard let index = library.decks.firstIndex(where: { $0.id == after.id }),library.decks[index] == after else { throw EngramError.conflict }
            if var before = change.beforeDeck { if !preserveMetadata { before.modifiedAt = now }; library.decks[index] = before }
            else { library.decks[index].deleted = true; library.decks[index].modifiedAt = now }
        }
        if let after = change.afterNote {
            guard let index = library.notes.firstIndex(where: { $0.id == after.id }),library.notes[index] == after else { throw EngramError.conflict }
            if var before = change.beforeNote { if !preserveMetadata { before.modifiedAt = now }; library.notes[index] = before }
            else { library.notes[index].deleted = true }
            for index in library.cards.indices where library.cards[index].noteID == after.id {
                library.cards[index].version += 1
                let restored = library.notes.first(where: { $0.id == after.id })
                let ordinals = try restored.map { try CardRenderer.ordinals(for: NoteDraft(note:$0)) } ?? []
                library.cards[index].retired = restored?.deleted != false || !ordinals.contains(library.cards[index].ordinal)
            }
        }
        if let after = change.afterSettings {
            guard library.settings == after,let before = change.beforeSettings else { throw EngramError.conflict }
            library.settings = before; library.settings.version = preserveMetadata ? before.version : after.version + 1
        }
        if let after = change.afterCard {
            guard let index = library.cards.firstIndex(where: { $0.id == after.id }), let before = change.beforeCard,
                  library.cards[index].suspended == after.suspended else { throw EngramError.conflict }
            library.cards[index].suspended = before.suspended; library.cards[index].version += 1
        }
        if !preserveMetadata, let id = change.deckID { syncNotebooks(&library,deckIDs:[id]) }
        state.runs[ri].actions[ai].changes[ci].undoneAt = now
        library.assistantState = state
        // Existing reviews/schedules stay intact; a stale presentation must not be graded.
        library.session = nil
        try LibraryValidation.validate(library)
        try await repository.commit(library,expectedRevision:library.revision)
    }
    public func saveLearningMemory(_ memory: LearningMemory?) async throws {
        guard let memory else { return }
        guard !memory.text.isEmpty,memory.text.utf8.count <= 10_000 else { throw EngramError.invalid("Keep learning memory under 10 KB.") }
        var library = try await repository.read(), state = LearningAssistantState()
        state = library.assistantState ?? state
        if let index = state.memory.firstIndex(where: { $0.id == memory.id }) { state.memory[index] = memory }
        else { state.memory.append(memory) }
        library.assistantState = state; try await repository.commit(library,expectedRevision:library.revision)
    }
    public func deleteLearningMemory(id: String) async throws {
        var library = try await repository.read()
        library.assistantState?.memory.removeAll { $0.id == id }
        try await repository.commit(library,expectedRevision:library.revision)
    }
}

private actor AIJournalRepository: LibraryRepository {
    let base: any LibraryRepository
    let runID: String,conversationID: String,callID: String,name: String,arguments: String
    init(base: any LibraryRepository,runID: String,conversationID: String,callID: String,name: String,arguments: String) {
        self.base = base; self.runID = runID; self.conversationID = conversationID; self.callID = callID; self.name = name; self.arguments = arguments
    }
    func read() async throws -> LibrarySnapshot { try await base.read() }
    func commit(_ snapshot: LibrarySnapshot,expectedRevision: Int) async throws {
        let prior = try await base.read()
        guard prior.revision == expectedRevision else { throw EngramError.conflict }
        var next = snapshot, changes: [AIContentChange] = []
        for after in next.decks where prior.decks.first(where: { $0.id == after.id }) != after {
            var change = AIContentChange(deckID:after.id)
            change.beforeDeck = prior.decks.first { $0.id == after.id }; change.afterDeck = after; changes.append(change)
        }
        for after in next.notes where prior.notes.first(where: { $0.id == after.id }) != after {
            var change = AIContentChange(deckID:after.deckID,noteID:after.id)
            change.beforeNote = prior.notes.first { $0.id == after.id }; change.afterNote = after; changes.append(change)
        }
        for after in next.cards {
            if let before = prior.cards.first(where: { $0.id == after.id }),before.suspended != after.suspended {
                var change = AIContentChange(deckID:after.deckID,noteID:after.noteID); change.beforeCard = before; change.afterCard = after; changes.append(change)
            }
        }
        if prior.settings != next.settings {
            var change = AIContentChange(); change.beforeSettings = prior.settings; change.afterSettings = next.settings; changes.append(change)
        }
        let record = AIActionRecord(id:callID,name:name,arguments:arguments,status:"completed",summary:"\(name): \(changes.count) saved changes",changes:changes)
        StudyService.appendAIRecord(record,runID:runID,conversationID:conversationID,to:&next)
        try await base.commit(next,expectedRevision:expectedRevision)
    }
}

private actor UndoWorkingRepository: LibraryRepository {
    private var value: LibrarySnapshot
    init(_ value: LibrarySnapshot) { self.value = value }
    func read() -> LibrarySnapshot { value }
    func commit(_ snapshot: LibrarySnapshot,expectedRevision: Int) throws {
        guard value.revision == expectedRevision else { throw EngramError.conflict }
        value = snapshot; value.revision += 1
    }
}
