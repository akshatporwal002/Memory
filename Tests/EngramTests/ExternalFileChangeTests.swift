import XCTest
import LearningCore
import PersistenceAdapters

final class ExternalFileChangeTests: XCTestCase {
    func testSameRevisionExternalEditIsNotOverwritten() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("library.json")
        let repository = try AtomicFileRepository(url: url)
        var initial = LibrarySnapshot(); initial.decks = [Deck(id: "deck", name: "Original")]
        try await repository.commit(initial, expectedRevision: 0)
        let before = try await repository.read()
        var external = before; external.decks[0].name = "External same-revision edit"
        let externalData = try JSONEncoder().encode(external)
        try externalData.write(to: url, options: .atomic)
        do { try await repository.commit(before, expectedRevision: before.revision); XCTFail("Do not overwrite an external change even if revision and library ID are unchanged") }
        catch { XCTAssertEqual(error as? EngramError, .conflict) }
        XCTAssertEqual(try Data(contentsOf: url), externalData)
        let after = try await repository.read(); XCTAssertEqual(after, before)
    }
    func testExternalDeletionIsNotSilentlyRecreated() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("library.json")
        let repository = try AtomicFileRepository(url: url)
        try await repository.commit(LibrarySnapshot(), expectedRevision: 0)
        let before = try await repository.read()
        try FileManager.default.removeItem(at: url)
        do { try await repository.commit(before, expectedRevision: before.revision); XCTFail("A removed library must require reopening instead of silently reappearing") }
        catch { XCTAssertEqual(error as? EngramError, .conflict) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let after = try await repository.read(); XCTAssertEqual(after, before)
    }
}
