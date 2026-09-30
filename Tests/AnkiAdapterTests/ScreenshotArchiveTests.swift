import XCTest
import LearningCore
@testable import AnkiAdapters

final class ScreenshotArchiveTests: XCTestCase {
    private let png = Data([137, 80, 78, 71, 13, 10, 26, 10, 0])

    func testExportRoundTripsImagesAndManifestButIsNotLibraryBackup() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        defer { try? FileManager.default.removeItem(at: url) }
        let metadata = Data("{\"files\":[\"001-settings-01.png\"]}".utf8)
        try ScreenshotArchive.write(images: ["001-settings-01.png": png], manifest: metadata, to: url)
        XCTAssertEqual(try SafeArchive.read(url), ["001-settings-01.png": png, "screenshots.json": metadata])
        XCTAssertThrowsError(try NativeBackupAdapter.read(from: url))
    }

    func testInvalidExportsNeverCreateAFile() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        for images in [[String: Data](), ["../outside.png": png], ["private.json": png], ["001.png": Data("not an image".utf8)]] {
            XCTAssertThrowsError(try ScreenshotArchive.write(images: images, manifest: Data(), to: url))
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
        let tooMany = Dictionary(uniqueKeysWithValues: (0...100).map { ("\($0).png", png) })
        XCTAssertThrowsError(try ScreenshotArchive.write(images: tooMany, manifest: Data(), to: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
