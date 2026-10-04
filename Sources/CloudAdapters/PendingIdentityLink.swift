import Foundation

/// Callback ownership metadata only. Contains no OAuth token or credentials.
public struct PendingIdentityLink: Codable, Equatable, Sendable {
    public let userID: UUID
    public let startedAt: Date
    public init(userID: UUID, startedAt: Date = Date()) {
        self.userID = userID; self.startedAt = startedAt
    }
    public func isValid(for userID: UUID, at now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(startedAt)
        return self.userID == userID && age >= 0 && age <= 15 * 60
    }
}
