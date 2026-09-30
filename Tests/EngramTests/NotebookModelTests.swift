import XCTest
@testable import Features
import LearningCore
import StudyApplication
import PersistenceAdapters
import SchedulingAdapters

@MainActor final class NotebookModelTests: XCTestCase {
    func testEditingDocumentCardOpensNotebookAtLinkedQuestion() async throws {
        let defaults = UserDefaults(suiteName: "engram.tests.\(UUID().uuidString)")!
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let deck = try await service.createDeck(from: DeckCreationDraft(title: "Notebook", document: "Q → A"))
        let model = EngramModel(service: service, defaults: defaults)
        await model.refresh()
        model.edit(try XCTUnwrap(model.library.liveNotes.first))
        XCTAssertEqual(model.notebookDeckID, deck.id)
        XCTAssertEqual(model.notebookFocusNoteID, model.library.liveNotes.first?.id)
        XCTAssertFalse(model.editorPresented)
    }

    func testUnfinishedNotebookDraftSurvivesModelRecreation() async throws {
        let suite = "engram.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let model = EngramModel(service: service, defaults: defaults)
        let block = NotebookBlock(kind: .question, text: "Unfinished", answer: "")
        let draft = NotebookEditingDraft(blocks: [block], original: [], revision: 7)
        model.keepNotebookDraft(draft, deckID: "deck")
        let reopened = EngramModel(service: service, defaults: defaults)
        XCTAssertEqual(reopened.notebookDraft("deck"), draft)
        reopened.keepNotebookDraft(nil, deckID: "deck")
        XCTAssertNil(reopened.notebookDraft("deck"))
    }

    func testOrdinaryCardsStillOpenTheCardEditor() async throws {
        let defaults = UserDefaults(suiteName: "engram.tests.\(UUID().uuidString)")!
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let deck = try await service.createDeck(name: "Cards")
        let note = try await service.saveNote(NoteDraft(deckID: deck.id, front: "Q", back: "A"), now: Date())
        let model = EngramModel(service: service, defaults: defaults)
        await model.refresh(); model.edit(note)
        XCTAssertTrue(model.editorPresented)
        XCTAssertEqual(model.draft?.id, note.id)
        XCTAssertNil(model.notebookDeckID)
    }
}
