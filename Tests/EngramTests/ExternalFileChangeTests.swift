import XCTest
import LearningCore
import PersistenceAdapters
#if os(Windows)
import WinSDK
#endif

final class ExternalFileChangeTests: XCTestCase {
    func testAtomicReplacementFailurePreservesCachedBytesAndAllowsRetry() async throws {
        #if os(Windows)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("library.json")
        let repository = try AtomicFileRepository(url: url)
        try await repository.commit(LibrarySnapshot(), expectedRevision: 0)
        let before = try await repository.read(), bytes = try Data(contentsOf: url)
        var changed = before; changed.decks.append(Deck(id: "new", name: "Saved after retry"))
        // A test-owned Windows file handle permits reads and writes but denies DELETE
        // sharing, so the byte check succeeds and the atomic replacement itself fails.
        let widePath = Array(url.path.utf16) + [0]
        let handle = widePath.withUnsafeBufferPointer {
            CreateFileW($0.baseAddress, DWORD(GENERIC_READ), DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE), nil,
                DWORD(OPEN_EXISTING), DWORD(FILE_ATTRIBUTE_NORMAL), nil)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else { return XCTFail("Could not create replacement-blocking test handle") }
        var isOpen = true
        defer { if isOpen { CloseHandle(handle) } }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        do { try await repository.commit(changed, expectedRevision: before.revision); XCTFail("Atomic replacement should fail while DELETE sharing is denied") }
        catch {
            XCTAssertFalse(error is EngramError, "The test must reach the Foundation atomic write, not the conflict guard")
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
            print("Verified atomic replacement fault: \((error as NSError).domain) code \((error as NSError).code)")
        }
        let failed = try await repository.read(); XCTAssertEqual(failed, before)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        CloseHandle(handle); isOpen = false
        try await repository.commit(changed, expectedRevision: before.revision)
        let reopened = try await AtomicFileRepository(url: url).read()
        XCTAssertEqual(reopened.decks, changed.decks)
        XCTAssertEqual(reopened.revision, before.revision + 1)
        #else
        throw XCTSkip("Windows sharing-mode fault fixture; equivalent Apple filesystem fault injection remains an Apple verification gate.")
        #endif
    }
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
