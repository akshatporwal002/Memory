import XCTest
import LearningCore
import StudyApplication
import PersistenceAdapters
import SchedulingAdapters

final class UnifiedAITests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_788_393_600)
    func testAssistantCoverRemovalIsJournaledAndUndoable() async throws {
        let app = StudyService(repository:MemoryRepository(),scheduler:FSRSScheduler())
        let deck = try await app.createDeck(name:"Covered",now:now)
        try await app.setDeckCover(id:deck.id,jpeg:Data([0xFF,0xD8,0xFF,0xD9]),now:now)
        let before = try await app.snapshot(),cover = try XCTUnwrap(before.decks.first?.coverMediaName)
        let action = try await app.executeAIContent(.removeCover(deck.id),runID:"cover-run",conversationID:"library",callID:"remove-cover",name:"remove_cover",arguments:"{}",expectedRevision:before.revision,now:now)
        XCTAssertEqual(action.changes.count,1)
        let removed = try await app.snapshot()
        XCTAssertNil(removed.decks.first?.coverMediaName)
        try await app.undoAIRun(id:"cover-run",now:now)
        let restored = try await app.snapshot()
        XCTAssertEqual(restored.decks.first?.coverMediaName,cover)
    }
    func testLibraryRetrievalRanksRelevantDeckAndPreservesEvidenceVersions() async throws {
        let app = StudyService(repository:MemoryRepository(),scheduler:FSRSScheduler())
        let biology = try await app.createDeck(name:"Biology",now:now),aws = try await app.createDeck(name:"AWS",now:now)
        _ = try await app.saveNote(NoteDraft(deckID:biology.id,front:"Energy?",back:"ATP"),now:now)
        _ = try await app.saveNote(NoteDraft(deckID:aws.id,front:"CloudFront delivery?",back:"CloudFront caches content at edge locations"),now:now)
        let evidence = EvidenceRetrieval.retrieveLibrary(query:"CloudFront edge delivery",library:try await app.snapshot(),limit:1)
        XCTAssertEqual(evidence.count,1); XCTAssertEqual(evidence.first?.deckID,aws.id); XCTAssertTrue(evidence.first?.text.localizedCaseInsensitiveContains("CloudFront") == true,"Returned: \(evidence)"); XCTAssertEqual(evidence.first?.version,String(now.timeIntervalSince1970))
    }
    func testUndoConflictRequiresChoiceAndPreservesLaterEditsUntilResolved() async throws {
        let app = StudyService(repository:MemoryRepository(),scheduler:FSRSScheduler())
        let deck = try await app.createDeck(name:"Original",now:now)
        let action = try await app.executeAIContent(.renameDeck(deck.id,"Assistant"),runID:"run",conversationID:"chat",callID:"call",name:"rename",arguments:"Assistant",expectedRevision:try await app.snapshot().revision,now:now)
        try await app.renameDeck(id:deck.id,name:"Human")
        let change = try XCTUnwrap(action.changes.first)
        do { try await app.undoAIChange(runID:"run",actionID:"call",changeID:change.id); XCTFail("Overlapping undo accepted") } catch {}
        let before = try await app.snapshot(); XCTAssertEqual(before.liveDecks.first?.name,"Human")
        try await app.resolveAIUndo(runID:"run",actionID:"call",changeID:change.id,choice:"theirs",expectedRevision:before.revision,now:now)
        let after = try await app.snapshot(); XCTAssertEqual(after.liveDecks.first?.name,"Original"); XCTAssertGreaterThan(after.revision,before.revision)
    }
    func testAppearanceAndMemoryActionsHaveVersionedUndo() async throws {
        let app = StudyService(repository:MemoryRepository(),scheduler:FSRSScheduler())
        let deck = try await app.createDeck(name:"Study",now:now)
        let note = try await app.saveNote(NoteDraft(deckID:deck.id,front:"Energy?",back:"ATP"),now:now)
        let values = ["theme":"neutral","appearance":"dark"],baseline = ["theme":"warm","appearance":"system"]
        _ = try await app.executeAIContent(.preferences(values,baseline:baseline),runID:"prefs",conversationID:"chat",callID:"prefs",name:"appearance",arguments:"dark",expectedRevision:try await app.snapshot().revision)
        try await app.undoAIRun(id:"prefs")
        let restored = try await app.snapshot(); XCTAssertEqual(restored.assistantState?.preferences,baseline)
        _ = try await app.executeAIContent(.memory(LearningMemory(id:"m",noteID:note.id,text:"Accepted correction")),runID:"memory",conversationID:"chat",callID:"memory",name:"memory",arguments:"accepted",expectedRevision:restored.revision)
        try await app.undoAIRun(id:"memory")
        let result = try await app.snapshot(); XCTAssertTrue(result.assistantState?.memory.isEmpty ?? false)
    }
    func testLegacyMigrationPreservesIDsAndVerifiesBackup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let app = StudyService(repository:MemoryRepository(),scheduler:FSRSScheduler())
        let deck = try await app.createDeck(name:"Imported")
        _ = try await app.saveNote(NoteDraft(deckID:deck.id,front:"Question",back:"Answer"),now:now)
        let original = try await app.snapshot(),bytes = try JSONEncoder().encode(original),legacy = directory.appendingPathComponent("library.json")
        try bytes.write(to:legacy)
        let repository = try SQLiteLibraryRepository(url:directory.appendingPathComponent("library.sqlite"),migrating:legacy)
        let migrated = try await repository.read(); XCTAssertEqual(migrated,original)
        let backup = try XCTUnwrap(FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil).first { $0.lastPathComponent.hasSuffix(".backup") })
        XCTAssertEqual(try Data(contentsOf:backup),bytes); XCTAssertEqual(try Data(contentsOf:legacy),bytes)
    }
    func testAccountSwitchInvalidatesCapturedMutationEvenWithSameRevision() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let repo = try SQLiteLibraryRepository(url:directory.appendingPathComponent("library.sqlite"))
        try await repo.selectAccount("a")
        var captured = try await repo.read(); captured.decks = [Deck(name:"Account A secret")]
        try await repo.selectAccount("b")
        do { try await repo.commit(captured,expectedRevision:captured.revision); XCTFail("Cross-account write accepted") } catch {}
        let isolated = try await repo.read(); XCTAssertTrue(isolated.decks.isEmpty)
        let serialized = String(decoding:try JSONEncoder().encode(captured),as:UTF8.self); XCTAssertFalse(serialized.contains("repositoryContext"))
    }
    func testStaleEvidenceCannotCommitAnAutomaticGrade() async throws {
        let app = StudyService(repository:MemoryRepository(),scheduler:FSRSScheduler())
        let deck = try await app.createDeck(name:"Study",now:now)
        let note = try await app.saveNote(NoteDraft(deckID:deck.id,front:"Energy?",back:"ATP"),now:now)
        let initial = try await app.snapshot()
        var blocks = NotebookDocument.blocks(for:try XCTUnwrap(initial.liveDecks.first),in:initial)
        blocks.append(NotebookBlock(id:"source",text:"ATP stores energy"))
        try await app.saveNotebook(deckID:deck.id,blocks:blocks,expectedRevision:initial.revision,now:now)
        let session = try await app.startSession(deckID:deck.id,now:now)
        let item = try XCTUnwrap(session.current)
        var attempt = AnswerAttempt(sessionID:session.id,item:item,noteID:note.id,answer:"ATP",prompt:"Energy?",expected:"ATP",modelID:"fixture",evidence:[AttemptEvidence(id:"passage-source",text:"ATP stores energy",version:String(now.timeIntervalSince1970))],now:now)
        attempt.assessment = AnswerAssessment(outcome:.correct,reason:"Source supported",method:"ai")
        try await app.saveAnswerAttempt(attempt)
        blocks[blocks.count-1].text = "Different evidence"
        try await app.saveNotebook(deckID:deck.id,blocks:blocks,expectedRevision:try await app.snapshot().revision,now:now.addingTimeInterval(0.1))
        do { try await app.commitAnswerAttempt(id:attempt.id,now:now); XCTFail("Stale source was graded") } catch {}
        let result = try await app.snapshot(); XCTAssertTrue(result.reviews.isEmpty)
    }
    func testAcceptedImprovementIsDeferredUntilNextAndPreservesOriginalRecall() async throws {
        let app = StudyService(repository:MemoryRepository(),scheduler:FSRSScheduler())
        let deck = try await app.createDeck(name:"Study",now:now)
        let note = try await app.saveNote(NoteDraft(deckID:deck.id,front:"Energy?",back:"ATP"),now:now)
        let session = try await app.startSession(deckID:deck.id,now:now)
        var attempt = AnswerAttempt(sessionID:session.id,item:try XCTUnwrap(session.current),noteID:note.id,answer:"Sugar",prompt:"Energy?",expected:"ATP",modelID:"fixture",evidence:[],now:now)
        attempt.assessment = AnswerAssessment(outcome:.incorrect,reason:"Incorrect original attempt",method:"fixture")
        attempt.acceptedImprovement = "ATP — adenosine triphosphate"
        try await app.saveAnswerAttempt(attempt)
        let provisional = try await app.snapshot(); XCTAssertEqual(provisional.liveNotes.first?.back,"ATP"); XCTAssertTrue(provisional.reviews.isEmpty)
        try await app.commitAnswerAttempt(id:attempt.id,now:now)
        let result = try await app.snapshot()
        XCTAssertEqual(result.liveNotes.first?.back,attempt.acceptedImprovement)
        XCTAssertEqual(result.reviews.first?.rating,.again)
        XCTAssertEqual(result.answerAttempts?.first?.originalAnswer,"Sugar")
        XCTAssertNotNil(result.assistantState?.runs.first?.actions.first?.changes.first?.beforeNote)
    }
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
