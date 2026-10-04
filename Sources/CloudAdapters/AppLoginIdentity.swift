import Foundation

public struct AppLoginIdentity: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var provider: String
    public init(id: UUID, provider: String) { self.id = id; self.provider = provider }
}
