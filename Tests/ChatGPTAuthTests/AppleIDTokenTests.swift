#if canImport(CryptoKit) && canImport(Security)
import Foundation
import XCTest
import CryptoKit
@testable import ChatGPTAuth

@MainActor final class AppleIDTokenTests: XCTestCase {
    func testSignedIdentityAndTampering() async throws {
        let key = P256.Signing.PrivateKey()
        let publicBytes = key.publicKey.x963Representation
        let header = Base64URL.encode(try JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": "test-key"]))
        let claims = Base64URL.encode(try JSONSerialization.data(withJSONObject: ["iss": ChatGPTOAuth.issuer,
            "aud": "oaiapp_one", "sub": "learner", "nonce": "nonce", "iat": 900, "exp": 2000]))
        let message = header + "." + claims
        let signature = Base64URL.encode(try key.signature(for: Data(message.utf8)).rawRepresentation)
        let jwks = try JSONSerialization.data(withJSONObject: ["keys": [["kid": "test-key", "kty": "EC",
            "alg": "ES256", "use": "sig", "crv": "P-256", "x": Base64URL.encode(publicBytes.subdata(in: 1..<33)),
            "y": Base64URL.encode(publicBytes.subdata(in: 33..<65))]]])
        let verifier = OpenAIIDTokenVerifier()
        XCTAssertEqual(try verifier.verify(message + "." + signature, jwks: jwks, clientID: "oaiapp_one",
            nonce: "nonce", now: Date(timeIntervalSince1970: 1000)).subject, "learner")
        XCTAssertThrowsError(try verifier.verify(message + "." + Base64URL.encode(Data(repeating: 0, count: 64)),
            jwks: jwks, clientID: "oaiapp_one", nonce: "nonce", now: Date(timeIntervalSince1970: 1000)))
        XCTAssertThrowsError(try verifier.verify(message + "." + signature, jwks: jwks, clientID: "oaiapp_other",
            nonce: "nonce", now: Date(timeIntervalSince1970: 1000)))
        XCTAssertThrowsError(try verifier.verify(message + "." + signature, jwks: jwks, clientID: "oaiapp_one",
            nonce: "wrong", now: Date(timeIntervalSince1970: 1000)))
    }
    func testPKCEUsesSHA256() async throws {
        let pending = try OAuthAttempt.secure(redirectURI: URL(string: "http://127.0.0.1:54321/auth/callback")!, hostID: "urn:uuid:test")
        XCTAssertEqual(pending.challenge, Base64URL.encode(Data(SHA256.hash(data: Data(pending.verifier.utf8)))))
        XCTAssertEqual(pending.verifier.count, 43)
        XCTAssertNotEqual(pending.state, pending.nonce)
    }
}
#endif
