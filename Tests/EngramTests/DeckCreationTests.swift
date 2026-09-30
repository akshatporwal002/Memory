import XCTest
import LearningCore
import StudyApplication
import PersistenceAdapters
import SchedulingAdapters
import AnkiAdapters

final class DeckCreationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_393_600)

    func testColonFormatDoesNotTreatURLsTimesOrFolderPathsAsCards() {
        let parsed = DeckDocument.parse("What is S3?: Object storage: buckets and objects\nhttps://aws.amazon.com\nMeet at 12:30\nAWS::Compute\n# Topic: storage\n\\Note: keep this as prose\nIncomplete:\nLegacy: wording -> Answer")
        XCTAssertEqual(parsed.questions.map(\.front), ["What is S3?", "Legacy: wording"])
        XCTAssertEqual(parsed.questions.map(\.back), ["Object storage: buckets and objects", "Answer"])
        XCTAssertEqual(parsed.issues.map(\.line), [7])
    }

    func testAWSPracticeSampleCreatesTwentyFourLinkedCards() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Sources/Features/Resources/AWS-Cloud-Practitioner-Sample.txt"), encoding: .utf8)
        let parsed = DeckDocument.parse(text)
        XCTAssertTrue(parsed.issues.isEmpty)
        XCTAssertEqual(parsed.questions.count, 24)
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let deck = try await service.createDeck(from: DeckCreationDraft(title: "AWS sample", document: text))
        let snapshot = try await service.snapshot()
        XCTAssertEqual(deck.documentFormatVersion, 2)
        XCTAssertEqual(snapshot.liveCards.count, 24)
        XCTAssertEqual(NotebookDocument.blocks(for: deck, in: snapshot).filter { $0.kind == .question }.count, 24)
    }

    func testLegacyDocumentColonProseDoesNotShiftExistingCardLinks() {
        let deck = Deck(id: "legacy", name: "Legacy", sourceDocument: "Reminder: revise this\nQuestion -> Original")
        var library = LibrarySnapshot()
        library.decks = [deck]
        library.notes = [Note(id: "legacy-note-0", deckID: deck.id, kind: .basic, front: "Question", back: "Edited")]
        let blocks = NotebookDocument.blocks(for: deck, in: library)
        XCTAssertEqual(blocks.filter { $0.kind == .question }.map(\.answer), ["Edited"])
        XCTAssertTrue(blocks.contains { $0.kind == .text && $0.text.contains("Reminder: revise this") })
    }

    func testDocumentParsesArrowsAndKeepsHeadingsAndProseOutOfCards() {
        let parsed = DeckDocument.parse("# Heading -> not a card\nA note about revision.\nFirst? -> Answer -> detail\nSecond? → Yes\n\\A -> B is a diagram\n#hashtag? -> A tag")
        XCTAssertTrue(parsed.issues.isEmpty)
        XCTAssertEqual(parsed.questions.map(\.line), [3, 4, 6])
        XCTAssertEqual(parsed.questions.map(\.front), ["First?", "Second?", "#hashtag?"])
        XCTAssertEqual(parsed.questions.map(\.back), ["Answer -> detail", "Yes", "A tag"])
    }

    func testIncompleteLinesUseCorrectLineNumbersIncludingWindowsNewlines() {
        let parsed = DeckDocument.parse("Q -> A\r\nMissing? ->\r\n-> Missing question\nNotes")
        XCTAssertEqual(parsed.questions.count, 1)
        XCTAssertEqual(parsed.issues.map(\.line), [2, 3])
    }

    func testLimitsAreReportedInsteadOfTruncatingTheDocument() {
        XCTAssertFalse(DeckDocument.parse(String(repeating: "a", count: DeckDocument.byteLimit + 1)).issues.isEmpty)
        let many = Array(repeating: "Q -> A", count: 1_001).joined(separator: "\n")
        XCTAssertEqual(DeckDocument.parse(many).questions.count, 1_001)
        XCTAssertFalse(DeckDocument.parse(many).issues.isEmpty)
    }

    func testCreateCommitsAllCardsOnceAndPreservesSourceInNativeBackup() async throws {
        let repository = MemoryRepository()
        let service = StudyService(repository: repository, scheduler: FSRSScheduler())
        let draft = DeckCreationDraft(title: "Cloud concepts", subject: "AWS", document: "# Fundamentals\nKeep these notes.\nCloud? -> On demand\nS3? → Object storage")
        let deck = try await service.createDeck(from: draft, now: now)
        let saved = try await service.snapshot()
        XCTAssertEqual(saved.revision, 1)
        XCTAssertEqual(deck.name, "AWS::Cloud concepts")
        XCTAssertEqual(deck.sourceDocument, draft.document)
        XCTAssertEqual(saved.liveNotes.count, 2)
        XCTAssertEqual(saved.liveCards.count, 2)
        XCTAssertTrue(saved.liveCards.allSatisfy { $0.deckID == deck.id && $0.schedule.phase == .new })
        XCTAssertEqual(QueuePolicy.dueCards(in: saved, deckID: deck.id, now: now).count, 2)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".engram")
        defer { try? FileManager.default.removeItem(at: url) }
        try NativeBackupAdapter.write(saved, to: url)
        XCTAssertEqual(try NativeBackupAdapter.read(from: url), saved)
    }

    func testInvalidDocumentCannotLeaveAnEmptyDeckOrPartialCards() async throws {
        let repository = MemoryRepository()
        let before = try await repository.read()
        let service = StudyService(repository: repository, scheduler: FSRSScheduler())
        let draft = DeckCreationDraft(title: "Invalid", document: "Valid? -> Yes\nIncomplete? ->")
        do { _ = try await service.createDeck(from: draft, now: now); XCTFail("Should reject incomplete Q&A") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Line 2")) }
        let after = try await repository.read()
        XCTAssertEqual(after, before)
    }

    func testCommitFailureCanBeRetriedAndRepeatedSuccessDoesNotDuplicate() async throws {
        let repository = MemoryRepository()
        let before = try await repository.read()
        let service = StudyService(repository: repository, scheduler: FSRSScheduler())
        let draft = DeckCreationDraft(title: "Retry", document: "Q -> A\nQ2 -> A2")
        await repository.failNextCommit()
        do { _ = try await service.createDeck(from: draft, now: now); XCTFail("Expected injected failure") } catch { }
        let failed = try await repository.read()
        XCTAssertEqual(failed, before)
        let first = try await service.createDeck(from: draft, now: now)
        let saved = try await service.snapshot()
        let repeated = try await service.createDeck(from: draft, now: now.addingTimeInterval(10))
        let after = try await service.snapshot()
        XCTAssertEqual(repeated, first)
        XCTAssertEqual(after, saved)
        var changed = draft; changed.document += "\nQ3 -> A3"
        do { _ = try await service.createDeck(from: changed, now: now); XCTFail("Changed retry must not mutate an existing deck") } catch { }
        let unchanged = try await service.snapshot()
        XCTAssertEqual(unchanged, saved)
    }

    func testPlainTextMarkupCharactersStayLiteral() async throws {
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        _ = try await service.createDeck(from: DeckCreationDraft(title: "Code", document: "What is <body>? -> An HTML element & container"), now: now)
        let saved = try await service.snapshot()
        XCTAssertEqual(saved.liveNotes.first?.front, "What is &lt;body&gt;?")
        XCTAssertEqual(saved.liveNotes.first?.back, "An HTML element &amp; container")
    }

    func testNoteOnlyAndEmptyDeckCreationAreAllowed() async throws {
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let notes = DeckCreationDraft(title: "Notes", document: "# To learn\nA paragraph to keep.")
        let deck = try await service.createDeck(from: notes, now: now)
        XCTAssertEqual(deck.sourceDocument, notes.document)
        _ = try await service.createDeck(from: DeckCreationDraft(title: "Empty"), now: now)
        let saved = try await service.snapshot()
        XCTAssertEqual(saved.liveDecks.count, 2)
        XCTAssertTrue(saved.liveCards.isEmpty)
    }

    func testDraftRoundTripRetainsIdentitySubjectAndIncompleteText() throws {
        let draft = DeckCreationDraft(title: "Work in progress", subject: "AWS::Networking", document: "# Notes\nIncomplete? ->")
        let restored = try JSONDecoder().decode(DeckCreationDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(restored, draft)
        XCTAssertEqual(restored.deckName, "AWS::Networking::Work in progress")
        XCTAssertFalse(restored.isEmpty)
        XCTAssertTrue(DeckCreationDraft().isEmpty)
    }

    func testDuplicateNameDoesNotAffectExistingDeck() async throws {
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        _ = try await service.createDeck(name: "Existing", now: now)
        let before = try await service.snapshot()
        do {
            _ = try await service.createDeck(from: DeckCreationDraft(title: "existing", document: "Q -> A"), now: now)
            XCTFail("Duplicate names should be rejected")
        } catch { }
        let after = try await service.snapshot()
        XCTAssertEqual(after, before)
    }
}
