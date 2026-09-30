import Foundation
import XCTest
@testable import ChatGPTAuth
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class OAuthSecurityTests: XCTestCase {
    private func attempt(registration: ChatGPTRegistration? = nil) throws -> OAuthAttempt {
        try OAuthAttempt(redirectURI: URL(string: "http://127.0.0.1:54321/auth/callback")!, state: "expected-state",
            nonce: "expected-nonce", verifier: String(repeating: "v", count: 43), challenge: "challenge",
            hostID: "urn:uuid:test", registration: registration)
    }
    func testNewRegistrationUsesHostPKCEAndPlanScopes() throws {
        let url = try attempt().authorizationURL(endpoint: URL(string: ChatGPTOAuth.issuer + "/api/accounts/authorize")!)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        let fields = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value!) })
        XCTAssertEqual(fields["client_id"], "dynamic_agent_client")
        XCTAssertEqual(fields["agent_name_hint"], "Engram")
        XCTAssertEqual(fields["resource"], "https://api.openai.com/v1")
        XCTAssertEqual(fields["code_challenge_method"], "S256")
        XCTAssertTrue(fields["scope"]!.contains("chatgpt.tokens.use.direct"))
        XCTAssertNil(fields["code_verifier"])
    }
    func testForgedCallbacksAreRejected() throws {
        let pending = try attempt()
        for url in ["http://localhost:54321/auth/callback?state=expected-state&code=x&client_id=oaiapp_one",
                    "http://127.0.0.1:54322/auth/callback?state=expected-state&code=x&client_id=oaiapp_one",
                    "http://127.0.0.1:54321/callback?state=expected-state&code=x&client_id=oaiapp_one",
                    "http://127.0.0.1:54321/auth/callback?state=wrong&code=x&client_id=oaiapp_one",
                    "http://127.0.0.1:54321/auth/callback?state=expected-state&state=expected-state&code=x&client_id=oaiapp_one",
                    "http://127.0.0.1:54321/auth/callback?state=expected-state&code=x&client_id=dynamic_agent_client",
                    "http://127.0.0.1:54321/auth/callback?state=expected-state&code=x"] {
            XCTAssertThrowsError(try pending.callback(URL(string: url)!))
        }
    }
    func testDenialRequiresMatchingState() throws {
        XCTAssertThrowsError(try attempt().callback(URL(string: "http://127.0.0.1:54321/auth/callback?state=wrong&error=access_denied")!)) {
            XCTAssertEqual($0 as? ChatGPTAuthError, .invalidCallback)
        }
        XCTAssertThrowsError(try attempt().callback(URL(string: "http://127.0.0.1:54321/auth/callback?state=expected-state&error=access_denied")!)) {
            XCTAssertEqual($0 as? ChatGPTAuthError, .denied)
        }
    }
    func testReturningRegistrationCannotBeReplacedByCallback() throws {
        let pending = try attempt(registration: ChatGPTRegistration(clientID: "oaiapp_existing", subject: "one"))
        XCTAssertEqual(try pending.callback(URL(string: "http://127.0.0.1:54321/auth/callback?state=expected-state&code=x")!).clientID, "oaiapp_existing")
        XCTAssertThrowsError(try pending.callback(URL(string: "http://127.0.0.1:54321/auth/callback?state=expected-state&code=x&client_id=oaiapp_other")!))
    }
    func testTokenClaimsRequireIssuerAudienceNonceAndExpiry() throws {
        let valid: [String: Any] = ["iss": ChatGPTOAuth.issuer, "sub": "subject", "aud": "oaiapp_one", "exp": 2000,
                                   "iat": 900, "nonce": "nonce"]
        func claims(_ fields: [String: Any]) throws -> IDTokenClaims {
            try JSONDecoder().decode(IDTokenClaims.self, from: JSONSerialization.data(withJSONObject: fields))
        }
        XCTAssertEqual(try claims(valid).validate(clientID: "oaiapp_one", expectedNonce: "nonce", now: Date(timeIntervalSince1970: 1000)).subject, "subject")
        for (key, value) in [("iss", "https://attacker.test"), ("aud", "another-app"), ("nonce", "wrong"), ("sub", "")] {
            var invalid = valid; invalid[key] = value
            XCTAssertThrowsError(try claims(invalid).validate(clientID: "oaiapp_one", expectedNonce: "nonce", now: Date(timeIntervalSince1970: 1000)))
        }
        XCTAssertThrowsError(try claims(valid).validate(clientID: "oaiapp_one", expectedNonce: "nonce", now: Date(timeIntervalSince1970: 2000)))
    }
    func testScopeAndRefreshRotationComeFromTokenResponse() throws {
        let data = Data(#"{"access_token":"access","refresh_token":"rotated","id_token":"identity","token_type":"Bearer","expires_in":3600,"scope":"openid"}"#.utf8)
        let response = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        let previous = ChatGPTCredentials(accessToken: "old", refreshToken: "old-refresh", idToken: "old-id",
            scopes: ["chatgpt.tokens.use.direct", "resource.invoke"], expiresAt: .distantPast)
        let credentials = try response.credentials(previous: previous, now: Date())
        XCTAssertEqual(credentials.refreshToken, "rotated")
        XCTAssertEqual(credentials.scopes, ["openid"])
        XCTAssertFalse(ChatGPTRegistration(clientID: "oaiapp_one", subject: "one", credentials: credentials).planUsageEnabled)
    }
    func testFormEncodingDoesNotSplitCredentials() {
        XCTAssertEqual(String(data: ChatGPTOAuth.form(["token": "a+b&c=d %"]), encoding: .utf8), "token=a%2Bb%26c%3Dd%20%25")
    }
    func testDiscoveryRejectsExternalTokenEndpoint() throws {
        let data = Data(#"{"issuer":"https://auth.openai.com","authorization_endpoint":"https://auth.openai.com/api/accounts/authorize","token_endpoint":"https://attacker.test/token","jwks_uri":"https://auth.openai.com/.well-known/jwks.json"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(OpenAIDiscovery.self, from: data).validate())
    }
}

@MainActor final class OAuthClientTests: XCTestCase {
    final class Transport: ChatGPTHTTPTransport {
        var requests: [URLRequest] = []
        var tokenScope = ChatGPTOAuth.scopes
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            requests.append(request)
            let body: String
            if request.url!.path.contains("openid-configuration") {
                body = #"{"issuer":"https://auth.openai.com","authorization_endpoint":"https://auth.openai.com/api/accounts/authorize","token_endpoint":"https://auth.openai.com/api/accounts/oauth/token","jwks_uri":"https://auth.openai.com/.well-known/jwks.json","revocation_endpoint":"https://auth.openai.com/revoke"}"#
            } else if request.url!.path.contains("jwks") { body = #"{"keys":[]}"# }
            else if request.url!.path.contains("revoke") { body = "" }
            else { body = "{\"access_token\":\"new-access\",\"refresh_token\":\"new-refresh\",\"id_token\":\"signed-token\",\"token_type\":\"Bearer\",\"expires_in\":3600,\"scope\":\"\(tokenScope)\"}" }
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }
    final class Verifier: ChatGPTIdentityVerifying {
        var subject = "subject"
        var observedNonce: String?
        func verify(_ token: String, jwks: Data, clientID: String, nonce: String?, now: Date) throws -> VerifiedChatGPTIdentity {
            observedNonce = nonce
            return VerifiedChatGPTIdentity(subject: subject, email: "learner@example.test", name: nil)
        }
    }
    func testExchangeVerifiesNonceAndExactRedirect() async throws {
        let transport = Transport(), verifier = Verifier()
        let client = ChatGPTOAuthClient(transport: transport, verifier: verifier)
        let pending = try OAuthAttempt(redirectURI: URL(string: "http://127.0.0.1:54321/auth/callback")!, state: "state",
            nonce: "nonce", verifier: String(repeating: "v", count: 43), challenge: "challenge", hostID: "urn:uuid:test")
        let result = try await client.exchange(OAuthCallback(code: "code", clientID: "oaiapp_one"), attempt: pending)
        XCTAssertEqual(verifier.observedNonce, "nonce")
        XCTAssertTrue(result.planUsageEnabled)
        let body = String(data: transport.requests.first { $0.httpMethod == "POST" }!.httpBody!, encoding: .utf8)!
        XCTAssertTrue(body.contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A54321%2Fauth%2Fcallback"))
        XCTAssertTrue(body.contains("client_id=oaiapp_one"))
        XCTAssertFalse(body.contains("client_secret"))
    }
    func testRefreshCannotChangeVerifiedAccount() async throws {
        let transport = Transport(), verifier = Verifier(); verifier.subject = "attacker"
        let client = ChatGPTOAuthClient(transport: transport, verifier: verifier)
        let credentials = ChatGPTCredentials(accessToken: "old", refreshToken: "refresh", idToken: "id",
            scopes: [], expiresAt: .distantPast)
        do { _ = try await client.refresh(ChatGPTRegistration(clientID: "oaiapp_one", subject: "subject", credentials: credentials)); XCTFail("Accepted changed identity") }
        catch { XCTAssertEqual(error as? ChatGPTAuthError, .invalidIdentity) }
    }
}
