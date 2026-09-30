import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ChatGPTAuthError: Error, LocalizedError, Equatable {
    case invalidCallback, invalidIdentity, invalidConfiguration, invalidTokenResponse
    case denied, cancelled, timedOut, listenerUnavailable, browserUnavailable
    case requestFailed, signInRequired, planPermissionMissing, secureStorageUnavailable
    public var errorDescription: String? {
        switch self {
        case .invalidCallback: return "The sign-in callback could not be verified. Please try again."
        case .invalidIdentity: return "OpenAI's account identity could not be verified. Please sign in again."
        case .invalidConfiguration: return "OpenAI's sign-in configuration could not be verified."
        case .invalidTokenResponse: return "OpenAI returned an incomplete sign-in response. Please try again."
        case .denied: return "ChatGPT access was not granted. You can continue studying without connecting."
        case .cancelled: return "Sign-in was cancelled."
        case .timedOut: return "Sign-in timed out. Please try again."
        case .listenerUnavailable: return "Engram could not start the local sign-in callback. Please try again."
        case .browserUnavailable: return "Engram could not open the sign-in browser."
        case .requestFailed: return "Could not connect to OpenAI. Check your connection and try again."
        case .signInRequired: return "Please reconnect your ChatGPT account."
        case .planPermissionMissing: return "This account has not granted permission to use its ChatGPT plan."
        case .secureStorageUnavailable: return "Engram could not access its secure Keychain storage."
        }
    }
}

public enum ChatGPTOAuth {
    public static let issuer = "https://auth.openai.com"
    public static let resource = "https://api.openai.com/v1"
    public static let scopes = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    public static let dynamicClientID = "dynamic_agent_client"
    public static let usageURL = URL(string: "https://chatgpt.com/settings/usage")!
    public static let accessURL = URL(string: "https://chatgpt.com/settings/security")!

    static func trustedEndpoint(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "auth.openai.com" && (url.port == nil || url.port == 443)
            && url.user == nil && url.password == nil && url.fragment == nil
    }

    static func form(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return Data(fields.sorted { $0.key < $1.key }.map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").utf8)
    }
}

public struct OAuthAttempt: Sendable {
    public let redirectURI: URL
    public let state: String
    public let nonce: String
    public let verifier: String
    public let challenge: String
    public let hostID: String
    public let registration: ChatGPTRegistration?

    public init(redirectURI: URL, state: String, nonce: String, verifier: String, challenge: String,
                hostID: String, registration: ChatGPTRegistration? = nil) throws {
        guard redirectURI.scheme == "http", redirectURI.host == "127.0.0.1", redirectURI.port != nil,
              redirectURI.path == "/auth/callback", redirectURI.query == nil, redirectURI.fragment == nil,
              redirectURI.user == nil, redirectURI.password == nil,
              !state.isEmpty, !nonce.isEmpty, (43...128).contains(verifier.count), !challenge.isEmpty,
              hostID.hasPrefix("urn:uuid:"),
              registration == nil || registration?.clientID != ChatGPTOAuth.dynamicClientID else {
            throw ChatGPTAuthError.invalidConfiguration
        }
        self.redirectURI = redirectURI; self.state = state; self.nonce = nonce
        self.verifier = verifier; self.challenge = challenge; self.hostID = hostID; self.registration = registration
    }

    public func authorizationURL(endpoint: URL) throws -> URL {
        guard ChatGPTOAuth.trustedEndpoint(endpoint) else { throw ChatGPTAuthError.invalidConfiguration }
        var fields = ["client_id": registration?.clientID ?? ChatGPTOAuth.dynamicClientID,
                      "ext_agent_host_id": hostID, "response_type": "code", "redirect_uri": redirectURI.absoluteString,
                      "scope": ChatGPTOAuth.scopes, "resource": ChatGPTOAuth.resource, "state": state,
                      "nonce": nonce, "code_challenge_method": "S256", "code_challenge": challenge]
        if let registration {
            if let idToken = registration.credentials?.idToken { fields["id_token_hint"] = idToken }
            if let email = registration.email { fields["login_hint"] = email }
        } else { fields["agent_name_hint"] = "Engram" }
        var url = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        url.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let result = url.url else { throw ChatGPTAuthError.invalidConfiguration }
        return result
    }

    public func callback(_ url: URL) throws -> OAuthCallback {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == redirectURI.scheme, parts.host == redirectURI.host, parts.port == redirectURI.port,
              parts.path == redirectURI.path, parts.user == nil, parts.password == nil, parts.fragment == nil else {
            throw ChatGPTAuthError.invalidCallback
        }
        let items = parts.queryItems ?? []
        guard Set(items.map(\.name)).count == items.count else { throw ChatGPTAuthError.invalidCallback }
        let fields = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        guard fields["state"] == state else { throw ChatGPTAuthError.invalidCallback }
        if fields["error"] != nil { throw ChatGPTAuthError.denied }
        guard let code = fields["code"], !code.isEmpty else { throw ChatGPTAuthError.invalidCallback }
        let clientID: String
        if let registration {
            guard fields["client_id"] == nil || fields["client_id"] == registration.clientID else {
                throw ChatGPTAuthError.invalidCallback
            }
            clientID = registration.clientID
        } else {
            guard let issued = fields["client_id"], issued.hasPrefix("oaiapp_"), issued.count > 7 else {
                throw ChatGPTAuthError.invalidCallback
            }
            clientID = issued
        }
        return OAuthCallback(code: code, clientID: clientID)
    }
}

public struct OAuthCallback: Sendable { public let code: String; public let clientID: String }

public struct ChatGPTCredentials: Codable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var idToken: String
    public var scopes: Set<String>
    public var expiresAt: Date
}

public struct ChatGPTRegistration: Codable, Identifiable, Sendable {
    public var id: String { clientID }
    public let clientID: String
    public let subject: String
    public var email: String?
    public var name: String?
    public var credentials: ChatGPTCredentials?
    public var acknowledgedPlanUsage = false
    public var label: String { email ?? name ?? "ChatGPT account" }
    public var planUsageEnabled: Bool { credentials?.scopes.isSuperset(of: ["chatgpt.tokens.use.direct", "resource.invoke"]) == true }
    public init(clientID: String, subject: String, email: String? = nil, name: String? = nil, credentials: ChatGPTCredentials? = nil) {
        self.clientID = clientID; self.subject = subject; self.email = email; self.name = name; self.credentials = credentials
    }
}

public struct ChatGPTVault: Codable, Sendable {
    public var hostID: String
    public var registrations: [ChatGPTRegistration] = []
    public var activeClientID: String?
    public init(hostID: String = "urn:uuid:" + UUID().uuidString.lowercased()) { self.hostID = hostID }
}

struct OAuthTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
    let tokenType: String
    let expiresIn: Double
    let scope: String?
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", refreshToken = "refresh_token", idToken = "id_token"
        case tokenType = "token_type", expiresIn = "expires_in", scope
    }
    func credentials(previous: ChatGPTCredentials? = nil, now: Date) throws -> ChatGPTCredentials {
        guard !accessToken.isEmpty, tokenType.lowercased() == "bearer", expiresIn.isFinite, expiresIn > 0,
              let identity = idToken ?? previous?.idToken, !identity.isEmpty,
              scope != nil || previous != nil else { throw ChatGPTAuthError.invalidTokenResponse }
        let scopes = scope.map { Set($0.split(separator: " ").map(String.init)) } ?? previous!.scopes
        return ChatGPTCredentials(accessToken: accessToken, refreshToken: refreshToken ?? previous?.refreshToken,
                                  idToken: identity, scopes: scopes, expiresAt: now.addingTimeInterval(expiresIn))
    }
}

public struct VerifiedChatGPTIdentity: Sendable {
    public let subject: String
    public let email: String?
    public let name: String?
}

@MainActor public protocol ChatGPTCredentialStorage {
    func load() throws -> ChatGPTVault?
    func save(_ vault: ChatGPTVault) throws
}

@MainActor public protocol ChatGPTHTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

@MainActor public protocol ChatGPTIdentityVerifying {
    func verify(_ token: String, jwks: Data, clientID: String, nonce: String?, now: Date) throws -> VerifiedChatGPTIdentity
}
