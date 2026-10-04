import XCTest
import LearningCore
import PersistenceAdapters

final class TutorWorkspaceRepositoryTests: XCTestCase {
    func testDurabilityAccountIsolationAndStaleWrites() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tutor-repository-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = TutorWorkspaceRepository(directory: directory)
        let owner = UUID()
        var workspace = TutorWorkspace(ownerID: owner, title: "AWS")
        try await repository.save(workspace, expectedVersion: nil)
        let restarted = TutorWorkspaceRepository(directory: directory)
        let saved = try await restarted.load(ownerID: owner)
        XCTAssertEqual(saved, [workspace])
        let otherAccount = try await restarted.load(ownerID: UUID())
        XCTAssertTrue(otherAccount.isEmpty)
        workspace.title = "Cloud"; workspace.version = 2
        try await restarted.save(workspace, expectedVersion: 1)
        do { try await repository.save(workspace, expectedVersion: 1); XCTFail("Stale write accepted") }
        catch { XCTAssertEqual(error as? EngramError, .conflict) }
        let updated = try await repository.load(ownerID: owner)
        XCTAssertEqual(updated, [workspace])
    }
}
