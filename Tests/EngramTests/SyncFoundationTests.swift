import XCTest
import LearningCore
import SyncFoundation

final class SyncFoundationTests: XCTestCase {
    func testOperationRequiresSequenceAndPayload() throws {
        let device = UUID()
        XCTAssertThrowsError(try SyncOperation(deviceID: device, sequence: 0, kind: .noteUpsert, payload: Data([1])))
        XCTAssertThrowsError(try SyncOperation(deviceID: device, sequence: 1, kind: .noteUpsert, payload: Data()))
    }

    func testPullRejectsUnorderedOperations() throws {
        let operation = try SyncOperation(deviceID: UUID(), sequence: 1, kind: .reviewRecorded, payload: Data([7]))
        XCTAssertThrowsError(try SyncPullResult(operations: [
            RemoteSyncOperation(cursor: SyncCursor(2), operation: operation),
            RemoteSyncOperation(cursor: SyncCursor(1), operation: operation)
        ], cursor: SyncCursor(2)))
    }

    func testCycleAcknowledgesOnlyPendingAcceptedIDsAndSavesCursor() async throws {
        let identity = try SyncIdentity(accountID: UUID(), libraryID: "library", deviceID: UUID())
        let pending = try SyncOperation(deviceID: identity.deviceID, sequence: 1, kind: .noteUpsert, payload: Data([1]))
        let unexpected = UUID()
        let outbox = TestOutbox(pending: [pending], cursor: SyncCursor(4))
        let remote = try SyncOperation(deviceID: UUID(), sequence: 1, kind: .reviewRecorded, payload: Data([2]))
        let transport = TestTransport(receipt: SyncPushReceipt(acceptedOperationIDs: [pending.id, unexpected], cursor: SyncCursor(5)), pull: try SyncPullResult(operations: [RemoteSyncOperation(cursor: SyncCursor(5), operation: remote)], cursor: SyncCursor(5)))

        let cycle = try await SyncCoordinator(transport: transport, outbox: outbox).sync(identity: identity)

        XCTAssertEqual(cycle.uploadedOperationIDs, [pending.id])
        XCTAssertEqual(cycle.downloadedOperations.map(\.operation.id), [remote.id])
        let acknowledged = await outbox.acknowledged
        let savedCursor = await outbox.savedCursor
        XCTAssertEqual(acknowledged, [pending.id])
        XCTAssertEqual(savedCursor, SyncCursor(5))
    }

    func testCycleRejectsCursorRegressionWithoutAcknowledgingRemoteCursor() async throws {
        let identity = try SyncIdentity(accountID: UUID(), libraryID: "library", deviceID: UUID())
        let outbox = TestOutbox(pending: [], cursor: SyncCursor(9))
        let transport = TestTransport(receipt: SyncPushReceipt(acceptedOperationIDs: [], cursor: SyncCursor(9)), pull: try SyncPullResult(operations: [], cursor: SyncCursor(8)))

        await XCTAssertThrowsErrorAsync(try await SyncCoordinator(transport: transport, outbox: outbox).sync(identity: identity))
        let savedCursor = await outbox.savedCursor
        XCTAssertNil(savedCursor)
    }
}

private actor TestOutbox: SyncOutbox {
    private var queued: [SyncOperation]
    private var position: SyncCursor
    private(set) var acknowledged: [UUID] = []
    private(set) var savedCursor: SyncCursor?
    init(pending: [SyncOperation], cursor: SyncCursor) { queued = pending; position = cursor }
    func pending(for identity: SyncIdentity) -> [SyncOperation] { queued }
    func acknowledge(_ operationIDs: [UUID], for identity: SyncIdentity) { acknowledged = operationIDs }
    func cursor(for identity: SyncIdentity) -> SyncCursor { position }
    func saveCursor(_ cursor: SyncCursor, for identity: SyncIdentity) { savedCursor = cursor; position = cursor }
}

private struct TestTransport: EngramSyncTransport {
    let receipt: SyncPushReceipt
    let pull: SyncPullResult
    func push(_ operations: [SyncOperation], for identity: SyncIdentity) async throws -> SyncPushReceipt { receipt }
    func pull(for identity: SyncIdentity, after cursor: SyncCursor) async throws -> SyncPullResult { pull }
}

private func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
    do { _ = try await expression(); XCTFail("Expected an error", file: file, line: line) }
    catch { }
}
