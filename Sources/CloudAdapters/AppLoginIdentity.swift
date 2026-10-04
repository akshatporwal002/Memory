import Foundation

public struct AppLoginIdentity: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var provider: String
    public var email: String?
    public init(id: UUID, provider: String, email: String? = nil) { self.id = id; self.provider = provider; self.email = email }
    public static func buttonTitle(provider: String, identities: [Self]) -> String {
        let name = provider == "email" ? "Email" : provider.capitalized
        return (identities.contains { $0.provider == provider } ? "Manage " : "Continue with ") + name
    }
}
