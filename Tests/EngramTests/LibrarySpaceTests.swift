import XCTest
import LearningCore
import PersistenceAdapters
import SchedulingAdapters
@testable import StudyApplication

final class LibrarySpaceTests: XCTestCase {
    func testSwitchingLibrariesPreservesDecksAndScopesStudyAndChat() async throws {
        let base = MemoryRepository()
        let service = StudyService(repository: base, scheduler: FSRSScheduler())
        let first = try await service.createDeck(name: "Exam")
        var chat = LearningConversation(id: "today:none")
        chat.messages = [LearningChatMessage(role: "user", text: "Private first library")]
        try await service.saveConversation(chat)
        let second = try await service.createLibrary(name: "University")
        try await service.selectLibrary(second.id)
        let empty = try await service.snapshot()
        XCTAssertTrue(empty.decks.isEmpty)
        XCTAssertTrue(empty.assistantState?.conversations.isEmpty ?? true)
        let other = try await service.createDeck(name: "Exam") // Names may repeat between libraries.
        XCTAssertNotEqual(first.id, other.id)
        try await service.selectLibrary(LibrarySpace.defaultID)
        let restored = try await service.snapshot()
        XCTAssertEqual(restored.decks.map(\.id), [first.id])
        XCTAssertEqual(restored.assistantState?.conversations.first?.messages.first?.text, "Private first library")
        let full = try await base.read()
        XCTAssertEqual(full.decks.count, 2)
    }

    func testSwitchInvalidatesInflightSnapshotEvenWithoutContentEdits() async throws {
        let scoped = LibrarySpaceRepository(base: MemoryRepository())
        let space = try await scoped.create(name: "Other", deviceOnly: false)
        let stale = try await scoped.read()
        try await scoped.select(space.id)
        do { try await scoped.commit(stale, expectedRevision: stale.revision); XCTFail("Stale library mutation accepted") }
        catch EngramError.conflict { }
    }

    func testFoldersAndFilesRemainScopedAndSurviveRestart() async throws {
        let base = MemoryRepository(), scheduler = FSRSScheduler()
        let service = StudyService(repository: base, scheduler: scheduler)
        _ = try await service.createFolder(name: "Sources")
        let space = try await service.createLibrary(name: "Second")
        try await service.selectLibrary(space.id)
        let empty = try await service.snapshot()
        XCTAssertTrue(empty.folders?.isEmpty ?? true)
        _ = try await service.createFolder(name: "Sources")
        let restarted = StudyService(repository: base, scheduler: scheduler)
        try await restarted.selectLibrary(space.id)
        let read = try await restarted.snapshot()
        XCTAssertEqual(read.folders, ["Sources"])
        XCTAssertNil(read.librarySpaces, "Scoped backups must not disclose other libraries")
        let spaces = try await restarted.librarySpaces(); XCTAssertEqual(spaces.count, 2)
    }

    func testMovingDeckKeepsStableIdentityWithoutCopying() async throws {
        let base = MemoryRepository(), service = StudyService(repository: base, scheduler: FSRSScheduler())
        let deck = try await service.createDeck(name: "AWS")
        let space = try await service.createLibrary(name: "Exams")
        try await service.moveDeckToLibrary(deck.id, libraryID: space.id)
        let beforeMove = try await service.snapshot(); XCTAssertTrue(beforeMove.decks.isEmpty)
        try await service.selectLibrary(space.id)
        let afterMove = try await service.snapshot(); XCTAssertEqual(afterMove.decks.first?.id, deck.id)
        let full = try await base.read(); XCTAssertEqual(full.decks.count, 1)
    }

    func testDeviceOnlyProjectionExcludesContentAndIdentity() async throws {
        let base = MemoryRepository(), service = StudyService(repository: base, scheduler: FSRSScheduler())
        let cloudDeck = try await service.createDeck(name: "Cloud")
        let space = try await service.createLibrary(name: "Private device", deviceOnly: true)
        try await service.selectLibrary(space.id)
        let localDeck = try await service.createDeck(name: "Local")
        let projected = LibrarySpaceScope.syncable(try await base.read())
        XCTAssertEqual(projected.decks.map(\.id), [cloudDeck.id])
        XCTAssertFalse(projected.decks.contains { $0.id == localDeck.id })
        XCTAssertFalse(projected.librarySpaces?.spaces.contains { $0.id == space.id } ?? true)
        XCTAssertFalse(projected.librarySpaces?.membership.values.contains(space.id) ?? true)
    }

    func testChatGPTLocalProfileNeverQueuesCloudUploads() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: path) }
        let repository = try SQLiteLibraryRepository(url: path)
        try await repository.selectAccount("chatgpt-test", syncEnabled: false)
        let service = StudyService(repository: repository, scheduler: FSRSScheduler())
        _ = try await service.createDeck(name: "Local identity")
        let pending = try await repository.pendingOperations(); XCTAssertTrue(pending.isEmpty)
        try await repository.selectAccount(nil)
        let local = try await repository.read(); XCTAssertTrue(local.decks.isEmpty)
    }

    func testGoogleHandoffCopiesChatGPTLibraryAndPreservesOriginal() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: path) }
        let repository = try SQLiteLibraryRepository(url: path)
        let service = StudyService(repository: repository, scheduler: FSRSScheduler())
        _ = try await service.createDeck(name: "Guest")
        try await repository.selectAccount("chatgpt-test", syncEnabled: false)
        let deck = try await service.createDeck(name: "My ChatGPT library")
        try await repository.selectAccount("google-user", uploadLocal: true, copyCurrentChatGPTProfile: true)
        let copied = try await repository.read()
        XCTAssertEqual(copied.decks.map(\.id), [deck.id])
        let pending = try await repository.pendingOperations()
        XCTAssertEqual(pending.count, 1)
        try await repository.selectAccount("chatgpt-test", syncEnabled: false)
        let original = try await repository.read()
        XCTAssertEqual(original.decks.map(\.id), [deck.id])
        do {
            try await repository.selectAccount("google-user", uploadLocal: true, copyCurrentChatGPTProfile: true)
            XCTFail("An existing account library must not be replaced")
        } catch EngramError.invalid { }
        let unchanged = try await repository.read()
        XCTAssertEqual(unchanged.decks.map(\.id), [deck.id])
        try await repository.selectAccount(nil)
        let guest = try await repository.read()
        XCTAssertEqual(guest.decks.map(\.name), ["Guest"])
    }

    func testProfileHandoffCannotCopyAnotherCloudAccount() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: path) }
        let repository = try SQLiteLibraryRepository(url: path)
        try await repository.selectAccount("first-user")
        do {
            try await repository.selectAccount("second-user", uploadLocal: true, copyCurrentChatGPTProfile: true)
            XCTFail("Only the active ChatGPT local profile may be copied")
        } catch EngramError.conflict { }
        let exists = try await repository.hasAccount("second-user")
        XCTAssertFalse(exists)
    }
}
