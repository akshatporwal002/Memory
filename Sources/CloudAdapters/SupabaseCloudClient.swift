import Foundation
import Supabase
import LearningCore

public enum JSONValue: Codable, Equatable, Sendable {
    case object([String:JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let b = try? value.decode(Bool.self) { self = .bool(b) }
        else if let n = try? value.decode(Double.self) { self = .number(n) }
        else if let s = try? value.decode(String.self) { self = .string(s) }
        else if let a = try? value.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try value.decode([String:JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let o): try value.encode(o)
        case .array(let a): try value.encode(a)
        case .string(let s): try value.encode(s)
        case .number(let n): try value.encode(n)
        case .bool(let b): try value.encode(b)
        case .null: try value.encodeNil()
        }
    }
    public static func encode<T:Encodable>(_ value: T) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self,from:JSONEncoder().encode(value)) }
    public func decode<T:Decodable>(_ type: T.Type) throws -> T { try JSONDecoder().decode(type,from:JSONEncoder().encode(self)) }
}
public struct CloudChange: Codable, Sendable {
    public var sequence: Int64
    public var kind: String
    public var entity_id: String
    public var deck_id: String?
    public var learner_id: UUID?
    public var version: Int64
    public var payload: JSONValue
    public var deleted: Bool
}
public struct CloudApply: Encodable, Sendable {
    public var operation_id: UUID
    public var entity_kind: String
    public var entity_id: String
    public var target_deck: String?
    public var base_version: Int64
    public var content: JSONValue
    public var is_deleted: Bool
    public init(operationID: UUID,kind: String,id: String,deckID: String?,version: Int64,content: JSONValue,deleted: Bool = false) {
        operation_id = operationID; entity_kind = kind; entity_id = id; target_deck = deckID; base_version = version; self.content = content; is_deleted = deleted
    }
    private enum CodingKeys: String, CodingKey { case operation_id, entity_kind, entity_id, target_deck, base_version, content, is_deleted }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy:CodingKeys.self)
        try container.encode(operation_id,forKey:.operation_id)
        try container.encode(entity_kind,forKey:.entity_kind)
        try container.encode(entity_id,forKey:.entity_id)
        // PostgREST requires the named argument even for learner-private entities.
        try container.encode(target_deck,forKey:.target_deck)
        try container.encode(base_version,forKey:.base_version)
        try container.encode(content,forKey:.content)
        try container.encode(is_deleted,forKey:.is_deleted)
    }
}
public struct CloudApplyResult: Codable, Sendable {
    public var status: String
    public var version: Int64?
    public var payload: JSONValue?
    public var deleted: Bool?
}
public struct CloudDeckAccess: Codable, Identifiable, Sendable {
    public var id: String
    public var owner_id: UUID
    public var deleted: Bool
}
public struct CloudMembership: Codable, Sendable { public var deck_id: String; public var user_id: UUID; public var role: String }
public struct CloudInvitation: Codable, Sendable { public var id: UUID; public var token: String }

/// App-account credentials and refresh are owned by Supabase Auth, separate from ChatGPT.
public protocol CloudTransport: Sendable {
    func currentUserID() async throws -> UUID
    func apply(_ operation: CloudApply) async throws -> CloudApplyResult
    func changes(after sequence: Int64) async throws -> [CloudChange]
    func decks() async throws -> [CloudDeckAccess]
    func memberships() async throws -> [CloudMembership]
    func uploadPrivateDocument(path: String,data: Data) async throws
    func downloadPrivateDocument(path: String) async throws -> Data
}
public extension CloudTransport {
    func uploadPrivateDocument(path: String,data: Data) async throws { throw EngramError.storage("Private document storage is unavailable; local work remains saved.") }
    func downloadPrivateDocument(path: String) async throws -> Data { throw EngramError.storage("Private document storage is unavailable; try synchronization again.") }
}
public actor SupabaseCloudClient: CloudTransport {
    private let client: SupabaseClient
    public init(url: URL,publishableKey: String) throws {
        guard url.scheme == "https" || ["localhost","127.0.0.1"].contains(url.host ?? ""), !publishableKey.hasPrefix("sb_secret_") else { throw EngramError.invalid("Use a project URL and publishable key.") }
        if publishableKey.split(separator:".").count == 3 {
            var payload = String(publishableKey.split(separator:".")[1]).replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/")
            payload += String(repeating:"=",count:(4-payload.count % 4) % 4)
            guard let bytes = Data(base64Encoded:payload),let claims = try? JSONSerialization.jsonObject(with:bytes) as? [String:Any], claims["role"] as? String == "anon" else { throw EngramError.invalid("Privileged database keys cannot be used in the app.") }
        } else if !publishableKey.hasPrefix("sb_publishable_") { throw EngramError.invalid("Use a publishable project key.") }
        client = SupabaseClient(supabaseURL:url,supabaseKey:publishableKey)
    }
    public func currentUserID() async throws -> UUID { try await client.auth.session.user.id }
    public func signIn(provider: String) async throws -> UUID {
        guard ["apple","google"].contains(provider) else { throw EngramError.invalid("Unsupported app-account provider.") }
        let session = try await client.auth.signInWithOAuth(provider:provider == "apple" ? .apple : .google,redirectTo:URL(string:"engram://app-auth"))
        return session.user.id
    }
    public func signOut() async throws { try await client.auth.signOut(scope: .local) }
    public func loginIdentities() async throws -> [AppLoginIdentity] {
        try await client.auth.userIdentities().map { identity in
            let email: String?
            if case .string(let value) = identity.identityData?["email"] { email = value } else { email = nil }
            return AppLoginIdentity(id: identity.identityId, provider: identity.provider, email: email)
        }
    }
    public func removeLoginIdentity(_ identityID: UUID, expectedUserID: UUID) async throws {
        guard try await currentUserID() == expectedUserID else { throw EngramError.conflict }
        let identities = try await client.auth.userIdentities()
        guard identities.count > 1 else { throw EngramError.invalid("Keep at least one login method to access your Engram account.") }
        guard let identity = identities.first(where: { $0.identityId == identityID }), identity.provider != "email" else {
            throw EngramError.invalid("This login method cannot be removed here.")
        }
        try await client.auth.unlinkIdentity(identity)
    }
    public func linkProvider(_ provider: String, expectedUserID: UUID) async throws {
        guard ["google", "apple"].contains(provider), try await currentUserID() == expectedUserID else { throw EngramError.conflict }
        try await client.auth.linkIdentity(provider: provider == "google" ? .google : .apple, redirectTo: URL(string: "engram://app-auth"))
    }
    public func completeIdentityLink(_ url: URL, expectedUserID: UUID) async throws {
        guard url.scheme == "engram", url.host == "app-auth", try await currentUserID() == expectedUserID else { throw EngramError.conflict }
        let session = try await client.auth.session(from: url)
        guard session.user.id == expectedUserID else {
            try? await client.auth.signOut()
            throw EngramError.invalid("This login belongs to another account. Sign in explicitly to switch; libraries were not merged.")
        }
    }
    public func linkApple(idToken: String, nonce: String, expectedUserID: UUID) async throws {
        guard try await currentUserID() == expectedUserID else { throw EngramError.conflict }
        let session = try await client.auth.linkIdentityWithIdToken(credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce))
        guard session.user.id == expectedUserID else { try? await client.auth.signOut(); throw EngramError.conflict }
    }
    public func requestEmailLink(_ email: String, expectedUserID: UUID) async throws {
        guard try await currentUserID() == expectedUserID else { throw EngramError.conflict }
        _ = try await client.auth.update(user: UserAttributes(email: email), redirectTo: URL(string: "engram://app-auth"))
    }
    public func verifyEmailLink(_ email: String, code: String, expectedUserID: UUID) async throws -> Bool {
        guard try await currentUserID() == expectedUserID else { throw EngramError.conflict }
        let response = try await client.auth.verifyOTP(email: email, token: code, type: .emailChange)
        guard response.user.id == expectedUserID else { try? await client.auth.signOut(); throw EngramError.conflict }
        return response.user.email?.caseInsensitiveCompare(email) == .orderedSame
    }
    public func sendEmailCode(email: String) async throws {
        try await client.auth.signInWithOTP(email: email, redirectTo: URL(string: "engram://app-auth"))
    }
    public func verifyEmailCode(email: String, code: String) async throws -> UUID {
        let response = try await client.auth.verifyOTP(email: email, token: code, type: .email)
        return response.user.id
    }
    public func signInWithApple(idToken: String, nonce: String) async throws -> UUID {
        let session = try await client.auth.signInWithIdToken(credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce))
        return session.user.id
    }
    public func apply(_ operation: CloudApply) async throws -> CloudApplyResult { try await client.rpc("engram_apply",params:operation).execute().value }
    public func changes(after sequence: Int64) async throws -> [CloudChange] { try await client.from("engram_changes").select().gt("sequence",value:String(sequence)).order("sequence").limit(500).execute().value }
    public func decks() async throws -> [CloudDeckAccess] { try await client.from("engram_decks").select().execute().value }
    public func memberships() async throws -> [CloudMembership] { try await client.from("engram_members").select().execute().value }
    public func uploadPrivateDocument(path: String,data: Data) async throws {
        try PrivateCloudDocument.validate(path:path,data:data,userID:try await currentUserID())
        _ = try await client.storage.from("engram-private-pdfs").upload(path,data:data,options:FileOptions(cacheControl:"0",contentType:"application/json",upsert:true))
    }
    public func downloadPrivateDocument(path: String) async throws -> Data {
        let user = try await currentUserID()
        try PrivateCloudDocument.validatePath(path,userID:user)
        let data = try await client.storage.from("engram-private-pdfs").download(path:path)
        try PrivateCloudDocument.validate(path:path,data:data,userID:user)
        return data
    }
    /// Notifications are only download hints. The incremental HTTP cursor remains authoritative.
    public func notifications() -> AsyncThrowingStream<Void,Error> {
        let client = self.client
        return AsyncThrowingStream { continuation in
            let channel = client.channel("engram-changes-" + UUID().uuidString)
            let changes = channel.postgresChange(AnyAction.self,schema:"public",table:"engram_changes",select:["sequence"])
            let task = Task {
                do {
                    try await channel.subscribeWithError()
                    for await _ in changes { try Task.checkCancellation(); continuation.yield(()) }
                    continuation.finish()
                } catch { continuation.finish(throwing:error) }
                await client.removeChannel(channel)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    public func invite(deckID: String,role: String) async throws -> CloudInvitation {
        try await client.rpc("engram_invite",params:["target_deck":JSONValue.string(deckID),"member_role":.string(role),"valid_hours":.number(168)]).execute().value
    }
    public func accept(token: String) async throws -> String { try await client.rpc("engram_accept",params:["invitation_token":token]).execute().value }
    public func revoke(deckID: String,userID: UUID? = nil,invitationID: UUID? = nil) async throws {
        _ = try await client.rpc("engram_revoke",params:["target_deck":JSONValue.string(deckID),"member_user":userID.map { .string($0.uuidString) } ?? .null,"invitation_id":invitationID.map { .string($0.uuidString) } ?? .null]).execute()
    }
}

