import XCTest
import LearningCore
import StudyApplication
import PersistenceAdapters
import SchedulingAdapters
import AnkiAdapters

final class LibraryCatalogTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_393_600)

    func testLegacyDeckDecodesWithoutPresentationMetadata() throws {
        let deck = try JSONDecoder().decode(Deck.self, from: Data(#"{"id":"old","name":"Original","deleted":false}"#.utf8))
        XCTAssertNil(deck.createdAt)
        XCTAssertNil(deck.modifiedAt)
        XCTAssertNil(deck.coverMediaName)
        XCTAssertEqual(deck.id, "old")
    }

    func testReviewSortOrdersDueNewFutureAndEmptyAndIgnoresSuspended() {
        var library = LibrarySnapshot()
        add("empty", phase: nil, to: &library)
        add("future", phase: .review, offset: 100, to: &library)
        add("new", phase: .new, to: &library)
        add("due", phase: .review, offset: -10, to: &library)
        add("oldest", phase: .learning, offset: -100, to: &library)
        add("suspended", phase: .review, offset: -1_000, to: &library)
        library.cards[library.cards.count - 1].suspended = true
        let sorted = LibraryDeckSummary.sorted(LibraryDeckSummary.make(in: library, now: now), by: .nextReview)
        XCTAssertEqual(sorted.map(\.id), ["oldest", "due", "new", "future", "empty", "suspended"])
        XCTAssertEqual(sorted.last?.cardCount, 1)
        XCTAssertNil(sorted.last?.nextReview)
    }

    func testDailyLimitsDoNotHideDueCountsOrBlockShortLearningSteps() {
        var library = LibrarySnapshot()
        library.settings.newCardsPerDay = 0; library.settings.reviewsPerDay = 0
        add("new", phase: .new, to: &library)
        add("review", phase: .review, to: &library)
        add("learning", phase: .learning, to: &library)
        let entries = LibraryDeckSummary.make(in: library, now: now)
        XCTAssertTrue(entries.first { $0.id == "new" }!.limitReached)
        XCTAssertTrue(entries.first { $0.id == "review" }!.limitReached)
        XCTAssertEqual(entries.first { $0.id == "review" }!.dueCount, 1)
        XCTAssertEqual(entries.first { $0.id == "learning" }!.availableCount, 1)
    }

    func testSearchSortsAndExplicitCreationDates() {
        var library = LibrarySnapshot()
        add("b", phase: .new, to: &library)
        add("a", phase: .new, to: &library)
        library.notes[0].front = "Cloud identity"
        library.decks[0].createdAt = now
        library.decks[1].createdAt = now.addingTimeInterval(-100)
        let entries = LibraryDeckSummary.make(in: library, now: now)
        XCTAssertEqual(LibraryDeckSummary.sorted(entries, by: .alphabetical).map(\.id), ["a", "b"])
        XCTAssertEqual(LibraryDeckSummary.sorted(entries, by: .reverseAlphabetical).map(\.id), ["b", "a"])
        XCTAssertEqual(LibraryDeckSummary.sorted(entries, by: .recentlyCreated).map(\.id), ["b", "a"])
        XCTAssertEqual(LibraryDeckSummary.sorted(entries, by: .nextReview, query: "CLOUD identity").map(\.id), ["b"])
        XCTAssertTrue(LibraryDeckSummary.sorted(entries, by: .nextReview, query: "missing").isEmpty)
    }

    func testNestedListPreservesParentDeckAndVirtualFoldersWithoutDuplicates() {
        var library = LibrarySnapshot()
        add("a", name: "AWS::Compute", phase: .new, to: &library)
        add("b", name: "AWS::Storage::S3", phase: .new, to: &library)
        add("c", name: "AWS", phase: nil, to: &library)
        let tree = LibraryFolder.tree(LibraryDeckSummary.make(in: library, now: now))
        XCTAssertEqual(tree.count, 1)
        XCTAssertEqual(tree[0].deck?.id, "c")
        XCTAssertEqual(tree[0].deckCount, 3)
        XCTAssertEqual(tree[0].children.map(\.title), ["Compute", "Storage"])
        XCTAssertEqual(tree[0].children[1].children.first?.deck?.id, "b")
    }

    func testCoverSurvivesNativeBackupWithoutChangingCardsOrReviews() async throws {
        var library = LibrarySnapshot()
        add("deck", phase: .review, to: &library)
        let service = StudyService(repository: MemoryRepository(initial: library), scheduler: FSRSScheduler())
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9]) // Resource round-trip, not an image-decoder test.
        try await service.setDeckCover(id: "deck", jpeg: jpeg, now: now)
        let saved = try await service.snapshot()
        XCTAssertEqual(saved.cards, library.cards)
        XCTAssertEqual(saved.reviews, library.reviews)
        XCTAssertEqual(saved.decks[0].modifiedAt, now)
        XCTAssertEqual(saved.media.first?.name, saved.decks[0].coverMediaName)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".engram")
        defer { try? FileManager.default.removeItem(at: url) }
        try NativeBackupAdapter.write(saved, to: url)
        XCTAssertEqual(try NativeBackupAdapter.read(from: url), saved)
        try await service.setDeckCover(id: "deck", jpeg: nil)
        let cleared = try await service.snapshot()
        XCTAssertNil(cleared.decks[0].coverMediaName)
        XCTAssertEqual(cleared.cards, library.cards)
        XCTAssertEqual(cleared.media, saved.media, "Removing a cover must not delete media another note could reference.")
    }

    func testInvalidCoverLeavesRepositoryUntouched() async throws {
        var library = LibrarySnapshot()
        add("deck", phase: nil, to: &library)
        let service = StudyService(repository: MemoryRepository(initial: library), scheduler: FSRSScheduler())
        do { try await service.setDeckCover(id: "deck", jpeg: Data("not jpeg".utf8)); XCTFail("Expected rejection") } catch { }
        let after = try await service.snapshot()
        XCTAssertEqual(after, library)
        library.decks[0].coverMediaName = "missing.jpg"
        XCTAssertThrowsError(try LibraryValidation.validate(library))
    }

    private func add(_ id: String, name: String? = nil, phase: LearningPhase?, offset: TimeInterval = 0, to library: inout LibrarySnapshot) {
        library.decks.append(Deck(id: id, name: name ?? id))
        guard let phase else { return }
        library.notes.append(Note(id: "note-" + id, deckID: id, kind: .basic, front: "Question", back: "Answer", modifiedAt: now))
        library.cards.append(StudyCard(id: "card-" + id, noteID: "note-" + id, deckID: id, ordinal: 0,
            schedule: ScheduleState(schedulerID: "test", implementationVersion: "1", due: now.addingTimeInterval(offset), phase: phase)))
    }
}
