import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct OpenAIDiscovery: Decodable {
    let issuer: String
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    let jwksURI: URL
    let revocationEndpoint: URL?
    enum CodingKeys: String, CodingKey {
        case issuer, authorizationEndpoint = "authorization_endpoint", tokenEndpoint = "token_endpoint"
        case jwksURI = "jwks_uri", revocationEndpoint = "revocation_endpoint"
    }
    func validate() throws {
        guard issuer == ChatGPTOAuth.issuer,
              [authorizationEndpoint, tokenEndpoint, jwksURI].allSatisfy(ChatGPTOAuth.trustedEndpoint),
              revocationEndpoint.map(ChatGPTOAuth.trustedEndpoint) ?? true else {
            throw ChatGPTAuthError.invalidConfiguration
        }
    }
}

/// Browser authentication and session lifecycle only. No inference or resource uploads.
@MainActor public final class ChatGPTOAuthClient {
    private let transport: any ChatGPTHTTPTransport
    private let verifier: any ChatGPTIdentityVerifying
    private var discovery: OpenAIDiscovery?
    public init(transport: any ChatGPTHTTPTransport, verifier: any ChatGPTIdentityVerifying) {
        self.transport = transport; self.verifier = verifier
    }

    private func configuration() async throws -> OpenAIDiscovery {
        if let discovery { return discovery }
        let data = try await get(URL(string: ChatGPTOAuth.issuer + "/.well-known/openid-configuration")!)
        let result: OpenAIDiscovery
        do { result = try JSONDecoder().decode(OpenAIDiscovery.self, from: data) }
        catch { throw ChatGPTAuthError.invalidConfiguration }
        try result.validate(); discovery = result
        return result
    }

    public func authorizationURL(for attempt: OAuthAttempt) async throws -> URL {
        let config = try await configuration()
        return try attempt.authorizationURL(endpoint: config.authorizationEndpoint)
    }

    public func exchange(_ callback: OAuthCallback, attempt: OAuthAttempt, now: Date = Date()) async throws -> ChatGPTRegistration {
        let config = try await configuration()
        let data = try await post(config.tokenEndpoint, fields: ["grant_type": "authorization_code",
            "client_id": callback.clientID, "code": callback.code, "code_verifier": attempt.verifier,
            "redirect_uri": attempt.redirectURI.absoluteString, "resource": ChatGPTOAuth.resource])
        let response = try tokenResponse(data)
        let credentials = try response.credentials(now: now)
        let keys = try await get(config.jwksURI)
        let identity = try verifier.verify(credentials.idToken, jwks: keys, clientID: callback.clientID, nonce: attempt.nonce, now: now)
        if let previous = attempt.registration, identity.subject != previous.subject { throw ChatGPTAuthError.invalidIdentity }
        var registration = ChatGPTRegistration(clientID: callback.clientID, subject: identity.subject,
            email: identity.email, name: identity.name, credentials: credentials)
        registration.acknowledgedPlanUsage = attempt.registration?.acknowledgedPlanUsage ?? false
        return registration
    }

    public func refresh(_ registration: ChatGPTRegistration, now: Date = Date()) async throws -> ChatGPTRegistration {
        guard let previous = registration.credentials, let refreshToken = previous.refreshToken else {
            throw ChatGPTAuthError.signInRequired
        }
        let config = try await configuration()
        let data = try await post(config.tokenEndpoint, fields: ["grant_type": "refresh_token",
            "client_id": registration.clientID, "refresh_token": refreshToken, "resource": ChatGPTOAuth.resource])
        let response = try tokenResponse(data)
        var result = registration
        let credentials = try response.credentials(previous: previous, now: now)
        if let token = response.idToken {
            let keys = try await get(config.jwksURI)
            let identity = try verifier.verify(token, jwks: keys, clientID: registration.clientID, nonce: nil, now: now)
            guard identity.subject == registration.subject else { throw ChatGPTAuthError.invalidIdentity }
            result.email = identity.email ?? result.email; result.name = identity.name ?? result.name
        }
        result.credentials = credentials
        return result
    }

    public func revoke(_ registration: ChatGPTRegistration) async throws {
        guard let token = registration.credentials?.refreshToken else { throw ChatGPTAuthError.signInRequired }
        guard let endpoint = try await configuration().revocationEndpoint else { throw ChatGPTAuthError.invalidConfiguration }
        _ = try await post(endpoint, fields: ["token": token, "token_type_hint": "refresh_token", "client_id": registration.clientID])
    }

    private func tokenResponse(_ data: Data) throws -> OAuthTokenResponse {
        do { return try JSONDecoder().decode(OAuthTokenResponse.self, from: data) }
        catch { throw ChatGPTAuthError.invalidTokenResponse }
    }
    private func get(_ url: URL) async throws -> Data { try await send(URLRequest(url: url)) }
    private func post(_ url: URL, fields: [String: String]) async throws -> Data {
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.httpBody = ChatGPTOAuth.form(fields)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        return try await send(request)
    }
    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data; let response: HTTPURLResponse
        do { (data, response) = try await transport.send(request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw ChatGPTAuthError.requestFailed }
        guard response.url == request.url, response.statusCode == 200, data.count <= 1_048_576 else {
            if response.statusCode == 400 || response.statusCode == 401 { throw ChatGPTAuthError.signInRequired }
            throw ChatGPTAuthError.requestFailed
        }
        return data
    }
}
