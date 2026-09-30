#if canImport(Security)
import Foundation
import Security

/// One atomic, device-only Keychain record. Never part of library backups or sync.
@MainActor public final class KeychainChatGPTStorage: ChatGPTCredentialStorage {
    private let service = "dev.engram.study.chatgpt.v1"
    public init() {}
    private var query: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "connections",
         kSecAttrSynchronizable: false]
    }
    public func load() throws -> ChatGPTVault? {
        var query = query; query[kSecReturnData] = true; query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let vault = try? JSONDecoder().decode(ChatGPTVault.self, from: data) else {
            throw ChatGPTAuthError.secureStorageUnavailable
        }
        return vault
    }
    public func save(_ vault: ChatGPTVault) throws {
        let data = try JSONEncoder().encode(vault)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData] = data
            item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw ChatGPTAuthError.secureStorageUnavailable }
        } else if status != errSecSuccess { throw ChatGPTAuthError.secureStorageUnavailable }
    }
}
#endif
