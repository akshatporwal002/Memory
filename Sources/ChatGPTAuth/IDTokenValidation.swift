import Foundation

enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func decode(_ value: String) throws -> Data {
        guard !value.isEmpty, value.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0)
            || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { throw ChatGPTAuthError.invalidIdentity }
        var padded = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        padded += String(repeating: "=", count: (4 - padded.count % 4) % 4)
        guard let data = Data(base64Encoded: padded) else { throw ChatGPTAuthError.invalidIdentity }
        return data
    }
}

struct IDTokenClaims: Decodable {
    let iss: String
    let sub: String
    let aud: Audience
    let exp: Double
    let iat: Double
    let nbf: Double?
    let nonce: String?
    let azp: String?
    let email: String?
    let name: String?
    enum Audience: Decodable {
        case single(String), multiple([String])
        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let single = try? value.decode(String.self) { self = .single(single) }
            else { self = .multiple(try value.decode([String].self)) }
        }
        var values: [String] { switch self { case .single(let value): return [value]; case .multiple(let values): return values } }
    }
    func validate(clientID: String, expectedNonce: String?, now: Date) throws -> VerifiedChatGPTIdentity {
        let time = now.timeIntervalSince1970
        guard iss == ChatGPTOAuth.issuer, !sub.isEmpty, aud.values.contains(clientID),
              exp.isFinite, exp > time, iat.isFinite, iat <= time + 60, iat < exp,
              nbf.map({ $0.isFinite && $0 <= time + 60 }) ?? true,
              azp == nil || azp == clientID,
              aud.values.count <= 1 || azp == clientID,
              expectedNonce == nil || nonce == expectedNonce else { throw ChatGPTAuthError.invalidIdentity }
        return VerifiedChatGPTIdentity(subject: sub, email: email, name: name)
    }
}

#if canImport(Security) && canImport(CryptoKit)
import Security
import CryptoKit

struct JSONWebKey: Decodable {
    let kid: String
    let kty: String
    let alg: String?
    let use: String?
    let n: String?
    let e: String?
    let crv: String?
    let x: String?
    let y: String?
}

@MainActor public struct OpenAIIDTokenVerifier: ChatGPTIdentityVerifying {
    public init() {}
    public func verify(_ token: String, jwks: Data, clientID: String, nonce: String?, now: Date) throws -> VerifiedChatGPTIdentity {
        do {
            guard token.utf8.count <= 65_536 else { throw ChatGPTAuthError.invalidIdentity }
            let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3 else { throw ChatGPTAuthError.invalidIdentity }
            struct Header: Decodable { let alg: String; let kid: String; let crit: [String]? }
            struct Keys: Decodable { let keys: [JSONWebKey] }
            let header = try JSONDecoder().decode(Header.self, from: Base64URL.decode(parts[0]))
            guard ["RS256", "ES256"].contains(header.alg), header.crit?.isEmpty ?? true else {
                throw ChatGPTAuthError.invalidIdentity
            }
            let keys = try JSONDecoder().decode(Keys.self, from: jwks).keys.filter { $0.kid == header.kid }
            guard keys.count == 1, let key = keys.first, key.alg == nil || key.alg == header.alg,
                  key.use == nil || key.use == "sig" else { throw ChatGPTAuthError.invalidIdentity }
            let message = Data((parts[0] + "." + parts[1]).utf8)
            let signature = try Base64URL.decode(parts[2])
            let valid: Bool
            if header.alg == "ES256" {
                guard key.kty == "EC", key.crv == "P-256", let x = key.x, let y = key.y else { throw ChatGPTAuthError.invalidIdentity }
                let xData = try Base64URL.decode(x), yData = try Base64URL.decode(y)
                guard xData.count == 32, yData.count == 32 else { throw ChatGPTAuthError.invalidIdentity }
                let publicKey = try P256.Signing.PublicKey(x963Representation: Data([4]) + xData + yData)
                valid = publicKey.isValidSignature(try P256.Signing.ECDSASignature(rawRepresentation: signature), for: message)
            } else {
                guard key.kty == "RSA", let n = key.n, let e = key.e else { throw ChatGPTAuthError.invalidIdentity }
                let modulus = try Base64URL.decode(n), exponent = try Base64URL.decode(e)
                guard modulus.count >= 256, modulus.count <= 1024, exponent.count <= 8 else { throw ChatGPTAuthError.invalidIdentity }
                let encoded = Self.der(0x30, Self.integer(modulus) + Self.integer(exponent))
                let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA,
                    kSecAttrKeyClass: kSecAttrKeyClassPublic, kSecAttrKeySizeInBits: modulus.count * 8]
                guard let publicKey = SecKeyCreateWithData(encoded as CFData, attributes as CFDictionary, nil),
                      SecKeyIsAlgorithmSupported(publicKey, .verify, .rsaSignatureMessagePKCS1v15SHA256) else {
                    throw ChatGPTAuthError.invalidIdentity
                }
                valid = SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256,
                    message as CFData, signature as CFData, nil)
            }
            guard valid else { throw ChatGPTAuthError.invalidIdentity }
            let claims = try JSONDecoder().decode(IDTokenClaims.self, from: Base64URL.decode(parts[1]))
            return try claims.validate(clientID: clientID, expectedNonce: nonce, now: now)
        } catch { throw ChatGPTAuthError.invalidIdentity }
    }
    private static func integer(_ data: Data) -> Data {
        let bytes = Data(data.drop(while: { $0 == 0 }))
        return der(0x02, (bytes.first.map { $0 & 0x80 != 0 } == true ? Data([0]) : Data()) + bytes)
    }
    private static func der(_ tag: UInt8, _ payload: Data) -> Data {
        var length = payload.count
        var bytes = [UInt8]()
        repeat { bytes.insert(UInt8(length & 255), at: 0); length >>= 8 } while length > 0
        let prefix = payload.count < 128 ? Data([UInt8(payload.count)]) : Data([0x80 | UInt8(bytes.count)] + bytes)
        return Data([tag]) + prefix + payload
    }
}

extension OAuthAttempt {
    public static func secure(redirectURI: URL, hostID: String, registration: ChatGPTRegistration? = nil) throws -> OAuthAttempt {
        func random() throws -> String {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                throw ChatGPTAuthError.secureStorageUnavailable
            }
            return Base64URL.encode(Data(bytes))
        }
        let verifier = try random()
        return try OAuthAttempt(redirectURI: redirectURI, state: random(), nonce: random(), verifier: verifier,
            challenge: Base64URL.encode(Data(SHA256.hash(data: Data(verifier.utf8)))), hostID: hostID, registration: registration)
    }
}
#endif
