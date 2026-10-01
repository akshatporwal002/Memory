import XCTest
import LearningCore
import StudyApplication
import PersistenceAdapters
import SchedulingAdapters

extension AnswerAssessmentTests {
    func testSimultaneousSubmissionCommitsOnce() async throws {
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let deck = try await service.createDeck(from: DeckCreationDraft(title: "Race", document: front + " -> " + back))
        let session = try await service.startSession(deckID: deck.id, now: Date())
        let presentation = session.current!.presentationID
        await withTaskGroup(of: Void.self) { group in
            for choice in ["A", "B"] { group.addTask { try? await service.submitAnswer(sessionID: session.id, presentationID: presentation, choiceID: choice) } }
        }
        let snapshot = try await service.snapshot()
        XCTAssertEqual(snapshot.reviews.count, 1)
        XCTAssertEqual(snapshot.session?.completed, 1)
    }
    func testRevealCannotBeRegradedAsUnassistedAnswer() async throws {
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let deck = try await service.createDeck(from: DeckCreationDraft(title: "Hints", document: front + " -> " + back))
        let session = try await service.startSession(deckID: deck.id, now: Date())
        let presentation = session.current!.presentationID
        _ = try await service.reveal(sessionID: session.id, presentationID: presentation, now: Date())
        do { try await service.submitAnswer(sessionID: session.id, presentationID: presentation, choiceID: "B"); XCTFail("Revealed answer must not count as unassisted") } catch { }
        let snapshot = try await service.snapshot(); XCTAssertTrue(snapshot.reviews.isEmpty)
    }
    func testLocalRetrievalIncludesNotebookEvidence() {
        var library = LibrarySnapshot()
        let note = Note(deckID: "d", kind: .basic, front: "Explain availability zones", back: "Separate failure boundaries")
        var deck = Deck(id: "d", name: "Cloud")
        deck.notebookBlocks = [NotebookBlock(id: "p", text: "Availability zones provide separate infrastructure failure boundaries.")]
        library.decks = [deck]; library.notes = [note]
        XCTAssertTrue(LocalAnswerEvidence.retrieve(note: note, prompt: note.front, library: library).contains { $0.id == "passage-p" })
    }
}
