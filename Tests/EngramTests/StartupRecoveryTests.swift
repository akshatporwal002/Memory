import Foundation
import XCTest
import LearningCore
import PersistenceAdapters

final class StartupRecoveryTests: XCTestCase {
    func testInvalidIncomingLibraryNeverChangesUnreadableOriginal() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("library.json")
        let bytes = Data("{broken original".utf8); try bytes.write(to: target)
        var invalid = LibrarySnapshot(); invalid.schemaVersion = 999
        let copies = root.appendingPathComponent("Recovery originals")
        XCTAssertThrowsError(try StartupLibraryRecovery.restore(invalid, to: target, expectedOriginal: bytes, preservingOriginalIn: copies))
        XCTAssertEqual(try Data(contentsOf: target), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copies.path))
    }
    func testSuccessfulRecoveryPreservesExactOriginalAndOpensValidSnapshot() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("library.json")
        let bytes = Data([0x00, 0xff, 0x31, 0x7b]); try bytes.write(to: target)
        var recovered = LibrarySnapshot(); recovered.decks = [Deck(id: "saved-deck", name: "Recovered")]
        let preserved = try XCTUnwrap(StartupLibraryRecovery.restore(recovered, to: target, expectedOriginal: bytes,
            preservingOriginalIn: root.appendingPathComponent("Recovery originals")))
        XCTAssertNotEqual(preserved, target)
        XCTAssertEqual(try Data(contentsOf: preserved), bytes)
        let reopened = try await AtomicFileRepository(url: target).read()
        XCTAssertEqual(reopened.libraryID, recovered.libraryID)
        XCTAssertEqual(reopened.decks, recovered.decks)
        XCTAssertNil(reopened.session)
    }
    func testFailedPreservationCopyCannotReplaceOriginal() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("library.json")
        let bytes = Data("unreadable original".utf8); try bytes.write(to: target)
        let blockedDirectory = root.appendingPathComponent("blocked")
        try Data("regular file blocks backup-directory creation".utf8).write(to: blockedDirectory)
        XCTAssertThrowsError(try StartupLibraryRecovery.restore(LibrarySnapshot(), to: target, expectedOriginal: bytes, preservingOriginalIn: blockedDirectory))
        XCTAssertEqual(try Data(contentsOf: target), bytes)
    }
    func testChangedOriginalRequiresFreshConfirmation() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("library.json")
        let inspected = Data("original at inspection".utf8)
        let changed = Data("changed after inspection".utf8); try changed.write(to: target)
        XCTAssertThrowsError(try StartupLibraryRecovery.restore(LibrarySnapshot(), to: target, expectedOriginal: inspected,
            preservingOriginalIn: root.appendingPathComponent("Recovery originals"))) { error in
            XCTAssertEqual(error as? EngramError, .conflict)
        }
        XCTAssertEqual(try Data(contentsOf: target), changed)
    }
    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("EngramStartupRecovery-" + UUID().uuidString, isDirectory: true)
    }
}
