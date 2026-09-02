import XCTest
import LearningCore
@testable import AnkiAdapters

final class ArchiveTests: XCTestCase {
    func testPackageIdentityDigestKnownVectors() {
        XCTAssertEqual(SafeArchive.digest(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SafeArchive.digest(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(SafeArchive.digest(Data(repeating: 97, count: 1_000_000)), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }
    func testBackupRestoresMediaAndRejectsMissingPayload() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".engram")
        defer { try? FileManager.default.removeItem(at: url) }
        var library = LibrarySnapshot(); library.media = [MediaFile(name: "study.png", data: Data([1, 2, 3]))]
        try NativeBackupAdapter.write(library, to: url)
        XCTAssertEqual(try NativeBackupAdapter.read(from: url), library)
        var entries = try SafeArchive.read(url); entries.removeValue(forKey: "media-0")
        try SafeArchive.write(entries, to: url)
        XCTAssertThrowsError(try NativeBackupAdapter.read(from: url))
    }
    func testUnsafeArchiveNameRejectedBeforeWrite() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try SafeArchive.write(["../escape": Data([1])], to: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    func testModernPackageIsExplicitlyUnsupported() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".apkg")
        defer { try? FileManager.default.removeItem(at: url) }
        try SafeArchive.write(["meta": Data([8, 3]), "collection.anki21b": Data([0])], to: url)
        XCTAssertThrowsError(try AnkiPackageAdapter.inspect(url: url)) { error in
            XCTAssertTrue(error.localizedDescription.contains("zstd/protobuf"))
        }
    }
}
