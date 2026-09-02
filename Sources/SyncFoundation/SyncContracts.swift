import Foundation
import LearningCore

/// Identifies one authenticated user's library on one installed device.
/// Credentials deliberately remain outside this module and are owned by the platform auth client.
public struct SyncIdentity: Codable, Equatable, Sendable {
    public let accountID: UUID
    public let libraryID: String
    public let deviceID: UUID

    public init(accountID: UUID, libraryID: String, deviceID: UUID) throws {
        guard !libraryID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EngramError.invalid("A sync library identifier is required.")
        }
        self.accountID = accountID
        self.libraryID = libraryID
        self.deviceID = deviceID
    }
}

/// The server-assigned, monotonically increasing position in a library operation log.
public struct SyncCursor: Codable, Equatable, Comparable, Sendable {
    public let value: Int64
    public init(_ value: Int64 = 0) { self.value = value }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }
}

/// Operations are immutable. Payloads are opaque to the sync layer so an encryption implementation
/// can be supplied without changing its conflict or retry semantics.
public enum SyncOperationKind: String, Codable, CaseIterable, Sendable {
    case librarySnapshot
    case deckUpsert
    case noteUpsert
    case cardUpsert
    case reviewRecorded
    case reviewCorrected
    case settingsChanged
    case mediaReference
    case tombstone
}

public struct SyncOperation: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let deviceID: UUID
    public let sequence: Int64
    public let kind: SyncOperationKind
    public let payload: Data
    public let payloadFormat: String
    public let createdAt: Date

    public init(id: UUID = UUID(), deviceID: UUID, sequence: Int64, kind: SyncOperationKind,
                payload: Data, payloadFormat: String = "application/vnd.engram.sync+json;v=1",
                createdAt: Date = Date()) throws {
        guard sequence > 0 else { throw EngramError.invalid("Sync operation sequences start at 1.") }
        guard !payload.isEmpty else { throw EngramError.invalid("Sync operations need an opaque payload.") }
        guard !payloadFormat.isEmpty else { throw EngramError.invalid("Sync operations need a payload format.") }
        self.id = id
        self.deviceID = deviceID
        self.sequence = sequence
        self.kind = kind
        self.payload = payload
        self.payloadFormat = payloadFormat
        self.createdAt = createdAt
    }
}

public struct RemoteSyncOperation: Codable, Equatable, Sendable {
    public let cursor: SyncCursor
    public let operation: SyncOperation
    public init(cursor: SyncCursor, operation: SyncOperation) {
        self.cursor = cursor
        self.operation = operation
    }
}

public struct SyncPushReceipt: Codable, Equatable, Sendable {
    public let acceptedOperationIDs: [UUID]
    public let cursor: SyncCursor
    public init(acceptedOperationIDs: [UUID], cursor: SyncCursor) {
        self.acceptedOperationIDs = acceptedOperationIDs
        self.cursor = cursor
    }
}

public struct SyncPullResult: Codable, Equatable, Sendable {
    public let operations: [RemoteSyncOperation]
    public let cursor: SyncCursor
    public init(operations: [RemoteSyncOperation], cursor: SyncCursor) throws {
        guard operations.allSatisfy({ $0.cursor <= cursor }) else {
            throw EngramError.invalid("A pulled operation cannot be after its advertised cursor.")
        }
        guard operations == operations.sorted(by: { $0.cursor < $1.cursor }) else {
            throw EngramError.invalid("Remote operations must be ordered by server cursor.")
        }
        self.operations = operations
        self.cursor = cursor
    }
}

/// Transport boundary for Supabase (or a later self-hosted compatible service).
/// A transport receives a user access token from its platform composition root; it never receives a service-role key.
public protocol EngramSyncTransport: Sendable {
    func push(_ operations: [SyncOperation], for identity: SyncIdentity) async throws -> SyncPushReceipt
    func pull(for identity: SyncIdentity, after cursor: SyncCursor) async throws -> SyncPullResult
}

/// Durable outbox semantics can be supplied by a repository. The app only removes operations whose UUIDs
/// the server explicitly accepted, which makes network retries safe.
public protocol SyncOutbox: Sendable {
    func pending(for identity: SyncIdentity) async throws -> [SyncOperation]
    func acknowledge(_ operationIDs: [UUID], for identity: SyncIdentity) async throws
    func cursor(for identity: SyncIdentity) async throws -> SyncCursor
    func saveCursor(_ cursor: SyncCursor, for identity: SyncIdentity) async throws
}

public struct SyncCycle: Equatable, Sendable {
    public let uploadedOperationIDs: [UUID]
    public let downloadedOperations: [RemoteSyncOperation]
    public let cursor: SyncCursor
    public init(uploadedOperationIDs: [UUID], downloadedOperations: [RemoteSyncOperation], cursor: SyncCursor) {
        self.uploadedOperationIDs = uploadedOperationIDs
        self.downloadedOperations = downloadedOperations
        self.cursor = cursor
    }
}

/// Coordinates transport only. Applying remote operations remains an explicit application-level transaction:
/// sync must not silently reschedule cards or mutate a current study session.
public struct SyncCoordinator: Sendable {
    private let transport: any EngramSyncTransport
    private let outbox: any SyncOutbox

    public init(transport: any EngramSyncTransport, outbox: any SyncOutbox) {
        self.transport = transport
        self.outbox = outbox
    }

    public func sync(identity: SyncIdentity) async throws -> SyncCycle {
        let pending = try await outbox.pending(for: identity)
        let receipt = try await transport.push(pending, for: identity)
        let pendingIDs = Set(pending.map(\.id))
        let accepted = receipt.acceptedOperationIDs.filter { pendingIDs.contains($0) }
        try await outbox.acknowledge(accepted, for: identity)

        let previousCursor = try await outbox.cursor(for: identity)
        let pulled = try await transport.pull(for: identity, after: previousCursor)
        guard pulled.cursor >= previousCursor else {
            throw EngramError.invalid("The sync server returned a cursor behind this device.")
        }
        try await outbox.saveCursor(pulled.cursor, for: identity)
        return SyncCycle(uploadedOperationIDs: accepted, downloadedOperations: pulled.operations, cursor: pulled.cursor)
    }
}
