import XCTest
import LearningCore
import StudyApplication
import SchedulingAdapters
import PersistenceAdapters

final class TestingLibraryTests: XCTestCase {
    func testSamplesAreStudyableAndRepeatedImportPreservesEditsAndProgress() async throws {
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let now = Date()
        let first = try await service.importTestingLibrary(now: now)
        XCTAssertEqual(first.addedDecks, 3); XCTAssertEqual(first.addedQuestions, 13)
        let snapshot = try await service.snapshot()
        XCTAssertEqual(snapshot.folders, ["Testing"])
        let mcq = try XCTUnwrap(snapshot.liveNotes.first { $0.mcq != nil })
        let choices = try XCTUnwrap(mcq.mcq)
        for seed in ["one", "two", "three"] {
            let presented = choices.ordered(for: seed)
            XCTAssertEqual(presented.resolvePresented(presented.displayLetter(for: presented.correctID)), choices.correctID)
        }
        let recall = try XCTUnwrap(snapshot.liveNotes.first { $0.mcq == nil && $0.front.contains("CloudTrail") })
        var draft = NoteDraft(note: recall); draft.back = "My revised explanation"
        _ = try await service.saveNote(draft, now: now)
        _ = try await service.startSession(deckID: recall.deckID, now: now)
        let session = try await service.snapshot()
        let item = try XCTUnwrap(session.session?.current), sessionID = try XCTUnwrap(session.session?.id)
        try await service.reveal(sessionID: sessionID, presentationID: item.presentationID, now: now)
        try await service.grade(sessionID: sessionID, presentationID: item.presentationID, rating: .good, mutationID: "sample-review", now: now)
        let before = try await service.snapshot()
        let again = try await service.importTestingLibrary(now: now.addingTimeInterval(30))
        let after = try await service.snapshot()
        XCTAssertEqual(again.addedQuestions, 0); XCTAssertEqual(again.preservedQuestions, 13)
        XCTAssertEqual(before, after)
    }
    func testDeletedSamplesStayDeletedAndIdentitiesAreLibraryScoped() async throws {
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        _ = try await service.importTestingLibrary()
        let first = try await service.snapshot()
        let deck = try XCTUnwrap(first.liveDecks.first)
        let deletedNote = try XCTUnwrap(first.liveNotes.first { $0.deckID != deck.id })
        try await service.deleteNote(id: deletedNote.id)
        try await service.deleteDeck(id: deck.id)
        _ = try await service.importTestingLibrary()
        let deleted = try await service.snapshot()
        XCTAssertFalse(deleted.liveDecks.contains { $0.id == deck.id })
        XCTAssertFalse(deleted.liveNotes.contains { $0.id == deletedNote.id })
        let space = try await service.createLibrary(name: "Other device", deviceOnly: true)
        try await service.selectLibrary(space.id)
        _ = try await service.importTestingLibrary()
        let second = try await service.snapshot()
        XCTAssertTrue(Set(first.decks.map(\.id)).isDisjoint(with: Set(second.decks.map(\.id))))
    }
    func testNameCollisionLeavesEntireLibraryUnchanged() async throws {
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        _ = try await service.createDeck(name: "Testing::AWS · Short answer")
        let before = try await service.snapshot()
        do { _ = try await service.importTestingLibrary(); XCTFail("Expected collision") } catch {}
        let after = try await service.snapshot()
        XCTAssertEqual(before, after)
    }
}
