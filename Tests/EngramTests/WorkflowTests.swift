import XCTest
import LearningCore
import StudyApplication
import PersistenceAdapters
import SchedulingAdapters

final class WorkflowTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_788_393_600)

    func testCreateStudyReopenAndUndo() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library.json")
        let store = try AtomicFileRepository(url: url)
        let app = StudyService(repository: store, scheduler: FSRSScheduler())
        let deck = try await app.createDeck(name: "Science::Biology")
        let note = try await app.saveNote(NoteDraft(deckID: deck.id, kind: .basic, front: "Cell energy?", back: "ATP"), now: now)
        let session = try await app.startSession(deckID: deck.id, now: now)
        let item = try XCTUnwrap(session.current)
        XCTAssertEqual(item.card.noteID, note.id)
        let revealed = try await app.reveal(sessionID: session.id, presentationID: item.presentationID, now: now)
        let good = try XCTUnwrap(revealed.outcomes[.good])
        let mutation = UUID().uuidString
        try await app.grade(sessionID: session.id, presentationID: item.presentationID, rating: .good, mutationID: mutation, now: now)
        let reopened = try AtomicFileRepository(url: url)
        let saved = try await reopened.read()
        XCTAssertEqual(saved.reviews.count, 1)
        XCTAssertEqual(saved.cards.first?.schedule, good)
        XCTAssertEqual(saved.notes.first?.back, "ATP")
        do {
            try await app.grade(sessionID: session.id, presentationID: item.presentationID, rating: .good, mutationID: mutation, now: now)
        } catch { /* stale presentation is safe; event count must stay one */ }
        XCTAssertEqual(try await app.snapshot().reviews.count, 1)
        try await app.undo(sessionID: session.id, now: now)
        let undone = try await app.snapshot()
        XCTAssertEqual(undone.cards.first?.schedule, item.card.schedule)
        XCTAssertEqual(undone.reviews.count, 1, "Undo must retain audit evidence")
        XCTAssertEqual(undone.corrections.count, 1)
        XCTAssertEqual(undone.activeReviews.count, 0)
    }

    func testClozeSiblingsKeepStateWhenEditing() async throws {
        let app = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let deck = try await app.createDeck(name: "Cloze")
        let text = "{{c1::Paris::city}} is in {{c2::France}}. {{c1::Paris}} again."
        let note = try await app.saveNote(NoteDraft(deckID: deck.id, kind: .cloze, front: text), now: now)
        var snapshot = try await app.snapshot()
        XCTAssertEqual(snapshot.cards.count, 2)
        let first = try XCTUnwrap(snapshot.cards.first { $0.ordinal == 0 })
        let rendered = try CardRenderer.render(note: note, card: first, revealed: false)
        XCTAssertFalse(rendered.prompt.contains("Paris"))
        XCTAssertTrue(rendered.prompt.contains("France"))
        XCTAssertTrue(rendered.prompt.contains("[city]"))
        try await app.setSuspended(cardID: first.id, suspended: true)
        _ = try await app.saveNote(NoteDraft(id: note.id, deckID: deck.id, kind: .cloze, front: text + " Updated."), now: now)
        snapshot = try await app.snapshot()
        XCTAssertEqual(snapshot.cards.first { $0.id == first.id }?.suspended, true)
        XCTAssertEqual(snapshot.cards.first { $0.id == first.id }?.schedule, first.schedule)
        XCTAssertEqual(try await app.startSession(deckID: nil, now: now).queue.count, 1)
    }

    func testInvalidClozeAndEmptyBasicLeaveStoreUntouched() async throws {
        let app = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let deck = try await app.createDeck(name: "Validation")
        for text in ["No deletion", "{{c0::bad}}", "{{c1::}}", "{{c1::unfinished", "{{c1::outer {{c2::nested}}}}"] {
            do { _ = try await app.saveNote(NoteDraft(deckID: deck.id, kind: .cloze, front: text), now: now); XCTFail(text) }
            catch {}
        }
        do { _ = try await app.saveNote(NoteDraft(deckID: deck.id, kind: .basic, front: "Question", back: "  "), now: now); XCTFail() }
        catch {}
        XCTAssertEqual(try await app.snapshot().notes.count, 0)
    }

    func testRepositoryContractsAndCompareAndSwap() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try AtomicFileRepository(url: directory.appendingPathComponent("library.json"))
        for repo: any LibraryRepository in [MemoryRepository(), file] {
            let original = try await repo.read()
            var changed = original
            changed.decks.append(Deck(name: "Saved"))
            try await repo.commit(changed, expectedRevision: original.revision)
            do { try await repo.commit(original, expectedRevision: original.revision); XCTFail("Lost-update protection") } catch {}
            XCTAssertEqual(try await repo.read().decks.count, 1)
            var invalid = try await repo.read()
            invalid.schemaVersion = 99
            do { try await repo.commit(invalid, expectedRevision: invalid.revision); XCTFail("Unknown schema") } catch {}
            XCTAssertEqual(try await repo.read().decks.count, 1)
        }
    }

    func testSchedulerReplaceabilityAndTransactionFailure() async throws {
        let repo = MemoryRepository()
        let app = StudyService(repository: repo, scheduler: FixedScheduler())
        let deck = try await app.createDeck(name: "Test adapter")
        _ = try await app.saveNote(NoteDraft(deckID: deck.id, kind: .basic, front: "Q", back: "A"), now: now)
        let session = try await app.startSession(deckID: nil, now: now)
        let item = try XCTUnwrap(session.current)
        _ = try await app.reveal(sessionID: session.id, presentationID: item.presentationID, now: now)
        await repo.failNextCommit()
        do { try await app.grade(sessionID: session.id, presentationID: item.presentationID, rating: .easy, mutationID: "fail", now: now); XCTFail() } catch {}
        XCTAssertEqual(try await app.snapshot().reviews.count, 0)
        try await app.grade(sessionID: session.id, presentationID: item.presentationID, rating: .easy, mutationID: "retry", now: now)
        XCTAssertEqual(try await app.snapshot().cards.first?.schedule.due, now.addingTimeInterval(400))
    }
}

private struct FixedScheduler: Scheduler {
    let identifier = "test-fixed"
    func initialState(now: Date, settings: StudySettings) throws -> ScheduleState {
        ScheduleState(schedulerID: identifier, due: now, phase: .new)
    }
    func outcomes(state: ScheduleState, history: [ReviewEvent], now: Date, settings: StudySettings) throws -> [Grade: ScheduleState] {
        Dictionary(uniqueKeysWithValues: Grade.allCases.map { grade in
            (grade, ScheduleState(schedulerID: identifier, due: now.addingTimeInterval(Double(grade.rawValue) * 100), phase: .review))
        })
    }
}
