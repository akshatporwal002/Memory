import XCTest
import LearningCore
import StudyApplication
import PersistenceAdapters
import SchedulingAdapters
import AnkiAdapters

final class NotebookTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_393_600)

    func testWritingConversionPreservesParagraphsAndRejectsIncompleteQuestions() throws {
        let blocks = try NotebookDocument.expandWriting("# Notes\nKeep this.\nQ -> A\nMore writing\nSecond → Answer")
        XCTAssertEqual(blocks.filter { $0.kind == .question }.map(\.text), ["Q", "Second"])
        XCTAssertEqual(blocks.filter { $0.kind == .text }.map(\.text), ["# Notes\nKeep this.", "More writing"])
        XCTAssertThrowsError(try NotebookDocument.expandWriting("Q ->"))
        XCTAssertTrue(blocks.allSatisfy { $0.noteID == nil })
    }

    func testUnrelatedLibraryChangesCanSaveAgainstUnchangedNotebook() async throws {
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let deck = try await service.createDeck(from: DeckCreationDraft(title: "Notebook", document: "Q → A"))
        let before = try await service.snapshot()
        let original = NotebookDocument.blocks(for: deck, in: before)
        var edited = original
        let index = try XCTUnwrap(edited.firstIndex { $0.kind == .question })
        edited[index].answer = "Changed"
        _ = try await service.createDeck(name: "Unrelated")
        try await service.saveNotebook(deckID: deck.id, blocks: edited, expectedRevision: before.revision, originalBlocks: original)
        let after = try await service.snapshot()
        XCTAssertEqual(after.liveNotes.first?.back, "Changed")
        XCTAssertEqual(after.liveDecks.count, 2)
        do {
            try await service.saveNotebook(deckID: deck.id, blocks: original, expectedRevision: before.revision, originalBlocks: original)
            XCTFail("A truly stale notebook must still be rejected")
        } catch { }
    }

    func testLegacyNotebookReopensLatestCardTextAndKeepsProse() async throws {
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let deck = try await service.createDeck(from: DeckCreationDraft(title: "Notebook", document: "# Notes\nKeep this paragraph.\nQ → Original"), now: now)
        let before = try await service.snapshot()
        var edit = NoteDraft(note: try XCTUnwrap(before.liveNotes.first))
        edit.back = "Updated &amp; correct"
        _ = try await service.saveNote(edit, now: now)
        let after = try await service.snapshot()
        let savedDeck = try XCTUnwrap(after.liveDecks.first)
        let blocks = NotebookDocument.blocks(for: savedDeck, in: after)
        XCTAssertEqual(blocks.first(where: { $0.kind == .question })?.answer, "Updated & correct")
        XCTAssertTrue(NotebookDocument.source(blocks).contains("Keep this paragraph."))
        XCTAssertTrue(savedDeck.sourceDocument?.contains("Updated & correct") == true)
        XCTAssertEqual(after.liveCards.first?.id, before.liveCards.first?.id)
        XCTAssertEqual(after.liveCards.first?.schedule, before.liveCards.first?.schedule)
        XCTAssertEqual(savedDeck.id, deck.id)
    }

    func testEditingReorderingAndAddingPreserveExistingCardIdentitiesAndSchedules() async throws {
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let deck = try await service.createDeck(from: DeckCreationDraft(title: "Notebook", document: "First → One\nSecond → Two"), now: now)
        let before = try await service.snapshot()
        var blocks = NotebookDocument.blocks(for: deck, in: before)
        blocks.removeAll { $0.kind == .text }
        blocks.swapAt(0, 1)
        blocks[0].text = "Changed second question"
        blocks[0].answer = "A multiline\nanswer with <code> & examples"
        blocks.append(NotebookBlock(kind: .question, text: "Third", answer: "Three"))
        try await service.saveNotebook(deckID: deck.id, blocks: blocks, expectedRevision: before.revision, now: now)
        let after = try await service.snapshot()
        XCTAssertEqual(after.liveCards.count, 3)
        for card in before.liveCards {
            let current = try XCTUnwrap(after.liveCards.first { $0.id == card.id })
            XCTAssertEqual(current.schedule, card.schedule)
            XCTAssertEqual(current.noteID, card.noteID)
        }
        let currentDeck = try XCTUnwrap(after.liveDecks.first)
        let reopened = NotebookDocument.blocks(for: currentDeck, in: after)
        XCTAssertEqual(reopened[0].id, blocks[0].id)
        XCTAssertEqual(reopened[0].answer, blocks[0].answer)
        XCTAssertNotNil(reopened.last?.noteID)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".engram")
        defer { try? FileManager.default.removeItem(at: url) }
        try NativeBackupAdapter.write(after, to: url)
        XCTAssertEqual(try NativeBackupAdapter.read(from: url), after)
    }

    func testRemovedBlockRetiresOnlyItsLinkedCardAndDoesNotResurrect() async throws {
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let deck = try await service.createDeck(from: DeckCreationDraft(title: "Notebook", document: "First → One\nSecond → Two"), now: now)
        let before = try await service.snapshot()
        var blocks = NotebookDocument.blocks(for: deck, in: before)
        let removed = try XCTUnwrap(blocks.first { $0.kind == .question }?.noteID)
        blocks.removeAll { $0.noteID == removed }
        try await service.saveNotebook(deckID: deck.id, blocks: blocks, expectedRevision: before.revision)
        let after = try await service.snapshot()
        XCTAssertEqual(after.liveNotes.count, 1)
        XCTAssertTrue(after.cards.first { $0.noteID == removed }?.retired == true)
        XCTAssertFalse(NotebookDocument.blocks(for: try XCTUnwrap(after.liveDecks.first), in: after).contains { $0.noteID == removed })
    }

    func testStaleAndInvalidEditsAreAtomicAndDraftCanRetryAfterCommitFailure() async throws {
        let repository = MemoryRepository()
        let service = StudyService(repository: repository, scheduler: FSRSScheduler())
        let deck = try await service.createDeck(from: DeckCreationDraft(title: "Notebook", document: "Q → A"), now: now)
        let before = try await service.snapshot()
        var blocks = NotebookDocument.blocks(for: deck, in: before)
        blocks.append(NotebookBlock(kind: .question, text: "Incomplete", answer: ""))
        do { try await service.saveNotebook(deckID: deck.id, blocks: blocks, expectedRevision: before.revision); XCTFail("Invalid") } catch { }
        var after = try await service.snapshot()
        XCTAssertEqual(after, before)
        blocks[blocks.count - 1].answer = "Complete"
        await repository.failNextCommit()
        do { try await service.saveNotebook(deckID: deck.id, blocks: blocks, expectedRevision: before.revision); XCTFail("Commit failure") } catch { }
        after = try await service.snapshot()
        XCTAssertEqual(after, before)
        try await service.saveNotebook(deckID: deck.id, blocks: blocks, expectedRevision: before.revision)
        let saved = try await service.snapshot()
        do { try await service.saveNotebook(deckID: deck.id, blocks: blocks, expectedRevision: before.revision); XCTFail("Stale editor") } catch { }
        after = try await service.snapshot()
        XCTAssertEqual(after, saved)
    }

    func testNewPlainCardsAppearAndClozeCardsRemainUntouched() async throws {
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let deck = try await service.createDeck(name: "Existing", now: now)
        let basic = try await service.saveNote(NoteDraft(deckID: deck.id, front: "Plain", back: "Answer"), now: now)
        let cloze = try await service.saveNote(NoteDraft(deckID: deck.id, kind: .cloze, front: "A {{c1::hidden}} word"), now: now)
        let before = try await service.snapshot()
        let blocks = NotebookDocument.blocks(for: deck, in: before)
        XCTAssertEqual(blocks.compactMap(\.noteID), [basic.id])
        try await service.saveNotebook(deckID: deck.id, blocks: blocks, expectedRevision: before.revision)
        let after = try await service.snapshot()
        XCTAssertEqual(after.liveNotes.first { $0.id == cloze.id }, cloze)
        XCTAssertEqual(after.liveCards.filter { $0.noteID == cloze.id }, before.liveCards.filter { $0.noteID == cloze.id })
    }

    func testCannotAttachAnotherDecksCardOrDuplicateBlockIdentity() async throws {
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let deck = try await service.createDeck(from: DeckCreationDraft(title: "One", document: "Q → A"))
        _ = try await service.createDeck(from: DeckCreationDraft(title: "Two", document: "Other → Answer"))
        let before = try await service.snapshot()
        var blocks = NotebookDocument.blocks(for: deck, in: before).filter { $0.kind == .question }
        blocks[0].noteID = before.liveNotes.first { $0.deckID != deck.id }?.id
        do { try await service.saveNotebook(deckID: deck.id, blocks: blocks, expectedRevision: before.revision); XCTFail("Cross deck") } catch { }
        blocks = NotebookDocument.blocks(for: deck, in: before)
        blocks.append(blocks[0])
        do { try await service.saveNotebook(deckID: deck.id, blocks: blocks, expectedRevision: before.revision); XCTFail("Duplicate") } catch { }
        let after = try await service.snapshot()
        XCTAssertEqual(after, before)
    }
}
