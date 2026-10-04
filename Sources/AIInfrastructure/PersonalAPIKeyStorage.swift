import Foundation
#if canImport(Security)
import Security
#endif

public enum PersonalAIProvider: String, CaseIterable, Sendable {
    case openai, gemini
    public var title: String { self == .openai ? "OpenAI API" : "Google Gemini API" }
}
public enum PersonalAPIKeyError: Error, LocalizedError {
    case invalid, inaccessible
    public var errorDescription: String? {
        switch self {
        case .invalid: "Enter an API key without spaces or line breaks."
        case .inaccessible: "Unable to access device-secure API key storage. Unlock your device and try again."
        }
    }
}
@MainActor public protocol PersonalAPIKeyStorage {
    func load(for provider: PersonalAIProvider) throws -> String?
    func save(_ key: String, for provider: PersonalAIProvider) throws
    func remove(for provider: PersonalAIProvider) throws
}
public enum PersonalAPIKeyValidation {
    public static func normalized(_ value: String) throws -> String {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (16...4096).contains(key.utf8.count), key.allSatisfy({ $0.isASCII && !$0.isWhitespace && !$0.isNewline && !$0.isControlCharacter }) else {
            throw PersonalAPIKeyError.invalid
        }
        return key
    }
}
private extension Character {
    var isControlCharacter: Bool { unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) } }
}
#if canImport(Security)
/// Keys never enter Codable library entities, UserDefaults, logs or cloud backups.
@MainActor public final class KeychainPersonalAPIKeyStorage: PersonalAPIKeyStorage {
    private let accountID: String
    public init(accountID: String = "local") { self.accountID = accountID }
    private func query(_ provider: PersonalAIProvider) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: "dev.engram.study.personal-ai.v1",
         kSecAttrAccount: accountID + ":" + provider.rawValue, kSecAttrSynchronizable: false]
    }
    public func load(for provider: PersonalAIProvider) throws -> String? {
        var query = query(provider); query[kSecReturnData] = true; query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data, let key = String(data: data, encoding: .utf8) else { throw PersonalAPIKeyError.inaccessible }
        return key
    }
    public func save(_ key: String, for provider: PersonalAIProvider) throws {
        let data = Data(try PersonalAPIKeyValidation.normalized(key).utf8)
        let query = query(provider)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData] = data; item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw PersonalAPIKeyError.inaccessible }
        } else if status != errSecSuccess { throw PersonalAPIKeyError.inaccessible }
    }
    public func remove(for provider: PersonalAIProvider) throws {
        let status = SecItemDelete(query(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw PersonalAPIKeyError.inaccessible }
    }
}
#endif
