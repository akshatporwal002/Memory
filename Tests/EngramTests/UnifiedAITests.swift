import XCTest
import LearningCore
import StudyApplication
import PersistenceAdapters
import SchedulingAdapters

final class UnifiedAITests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_788_393_600)
    func testProvisionalAttemptSurvivesReopenAndNextCommitsOnce() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let url = directory.appendingPathComponent("library.sqlite")
        let repo = try SQLiteLibraryRepository(url:url)
        let app = StudyService(repository:repo,scheduler:FSRSScheduler())
        let deck = try await app.createDeck(name:"Study")
        let note = try await app.saveNote(NoteDraft(deckID:deck.id,front:"Energy?",back:"ATP"),now:now)
        let session = try await app.startSession(deckID:deck.id,now:now)
        let item = try XCTUnwrap(session.current)
        var attempt = AnswerAttempt(sessionID:session.id,item:item,noteID:note.id,answer:"ATP",prompt:"Energy?",expected:"ATP",modelID:"fixture",evidence:[],now:now)
        attempt.assessment = AnswerAssessment(outcome:.correct,reason:"Matches",method:"local-exact")
        try await app.saveAnswerAttempt(attempt)
        let reopened = try SQLiteLibraryRepository(url:url)
        let saved = try await reopened.read()
        XCTAssertEqual(saved.answerAttempts?.first?.originalAnswer,"ATP")
        XCTAssertTrue(saved.reviews.isEmpty)
        try await app.commitAnswerAttempt(id:attempt.id,now:now)
        try await app.commitAnswerAttempt(id:attempt.id,now:now)
        let committed = try await repo.read()
        XCTAssertEqual(committed.reviews.count,1)
        XCTAssertNotNil(committed.answerAttempts?.first?.committedAt)
    }
    func testAssistedAttemptCannotAutomaticallyGrade() async throws {
        let app = StudyService(repository:MemoryRepository(),scheduler:FSRSScheduler())
        let deck = try await app.createDeck(name:"Study")
        _ = try await app.saveNote(NoteDraft(deckID:deck.id,front:"Energy?",back:"ATP"),now:now)
        let session = try await app.startSession(deckID:deck.id,now:now)
        let item = try XCTUnwrap(session.current)
        try await app.markAttemptAssisted(presentationID:item.presentationID)
        do { try await app.commitAnswerAttempt(id:"attempt-" + item.presentationID); XCTFail("Assisted grade accepted") } catch {}
        let ungraded = try await app.snapshot(); XCTAssertTrue(ungraded.reviews.isEmpty)
    }
    func testUnicodeAnnotationsRejectBrokenAndOverlappingRanges() {
        let item = ReviewPresentation(card:StudyCard(noteID:"n",deckID:"d",schedule:try! FSRSScheduler().initialState(now:now,settings:StudySettings())))
        let attempt = AnswerAttempt(sessionID:"s",item:item,noteID:"n",answer:"👩🏽‍💻 ATP",prompt:"q",expected:"a",modelID:"fixture",evidence:[])
        let good = AnswerAnnotation(startUTF16:8,lengthUTF16:3,text:"ATP",kind:"correct")
        let broken = AnswerAnnotation(startUTF16:1,lengthUTF16:1,text:"?",kind:"correct")
        XCTAssertEqual(attempt.validatedAnnotations([broken,good,good]),[good])
    }
    func testRunUndoIsAtomicAndRetriesDoNotRepeatEdits() async throws {
        let app = StudyService(repository:MemoryRepository(),scheduler:FSRSScheduler())
        let deck = try await app.createDeck(name:"Original",now:now)
        for (id,name) in [("one","First"),("two","Second")] {
            let revision = try await app.snapshot().revision
            _ = try await app.executeAIContent(.renameDeck(deck.id,name),runID:"run",conversationID:"chat",callID:id,name:"rename",arguments:name,expectedRevision:revision,now:now)
            _ = try await app.executeAIContent(.renameDeck(deck.id,name),runID:"run",conversationID:"chat",callID:id,name:"rename",arguments:name,expectedRevision:revision,now:now)
        }
        try await app.undoAIRun(id:"run",now:now)
        let result = try await app.snapshot()
        XCTAssertEqual(result.liveDecks.first?.name,"Original")
        XCTAssertEqual(result.assistantState?.runs.first?.actions.count,2)
        XCTAssertTrue(result.assistantState!.runs[0].actions.flatMap(\.changes).allSatisfy { $0.undoneAt != nil })
    }
    func testSQLiteAccountIsolationAndDurableOutbox() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let repo = try SQLiteLibraryRepository(url:directory.appendingPathComponent("library.sqlite"))
        var local = try await repo.read(); local.decks = [Deck(name:"Private local")]
        try await repo.commit(local,expectedRevision:local.revision)
        try await repo.selectAccount("a")
        var a = try await repo.read(); XCTAssertTrue(a.decks.isEmpty)
        a.decks = [Deck(name:"Account A")]; try await repo.commit(a,expectedRevision:a.revision)
        let pendingA = try await repo.pendingOperations(); XCTAssertEqual(pendingA.count,1)
        try await repo.selectAccount("b")
        let b = try await repo.read(); XCTAssertTrue(b.decks.isEmpty)
        let pendingB = try await repo.pendingOperations(); XCTAssertTrue(pendingB.isEmpty)
        try await repo.selectAccount(nil)
        let original = try await repo.read(); XCTAssertEqual(original.decks.first?.name,"Private local")
    }
}
