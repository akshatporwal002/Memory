import Foundation
import Observation
import AIInfrastructure

@MainActor @Observable final class PersonalAIConnections {
    private var storage: any PersonalAPIKeyStorage
    private let defaults: UserDefaults
    private let makeStorage: (@MainActor (String) -> any PersonalAPIKeyStorage)?
    private(set) var accountID = "local"
    private(set) var revision = 0
    private(set) var sessionRevision = 0
    private(set) var configured: Set<PersonalAIProvider> = []
    private(set) var catalogs: [PersonalAIProvider: [AIModelDescriptor]] = [:]
    private(set) var busy = false
    var error: String?
    var stamp: String { accountID + ":" + String(revision) }
    var runtimeStamp: String { stamp + ":session:" + String(sessionRevision) }
    private var revisionKey: String { "engram.personalAI.revision:" + accountID }
    init(storage: any PersonalAPIKeyStorage, defaults: UserDefaults = .standard, makeStorage: (@MainActor (String) -> any PersonalAPIKeyStorage)? = nil) {
        self.storage = storage
        self.defaults = defaults; self.makeStorage = makeStorage
        revision = defaults.integer(forKey: "engram.personalAI.revision:local")
        inspectStoredKeys()
    }
    private func advanceRevision() {
        revision += 1; sessionRevision += 1
        defaults.set(revision, forKey: revisionKey)
    }
    static func live() -> PersonalAIConnections {
        #if canImport(Security)
        return PersonalAIConnections(storage: KeychainPersonalAPIKeyStorage(), makeStorage: { KeychainPersonalAPIKeyStorage(accountID: $0) })
        #else
        return PersonalAIConnections(storage: UnavailablePersonalKeyStorage())
        #endif
    }
    func selectAccount(_ id: String) {
        guard id != accountID else { return }
        accountID = id; revision = defaults.integer(forKey: revisionKey)
        sessionRevision += 1; catalogs = [:]; configured = []; error = nil
        if let makeStorage { storage = makeStorage(id) }
        inspectStoredKeys()
    }
    private func inspectStoredKeys() {
        do { configured = Set(try PersonalAIProvider.allCases.filter { try storage.load(for: $0) != nil }) }
        catch { self.error = error.localizedDescription }
    }
    func token(for provider: String) throws -> String {
        guard let provider = PersonalAIProvider(rawValue: provider), let key = try storage.load(for: provider) else {
            throw AIProviderError.unavailable
        }
        return key
    }
    func save(_ value: String, provider: PersonalAIProvider) async throws {
        guard !busy else { throw AIProviderError.unavailable }
        busy = true; error = nil; defer { busy = false }
        let before = runtimeStamp, key = try PersonalAPIKeyValidation.normalized(value)
        let models = try await AIProviderRegistry.provider(provider.rawValue).models(token: key)
        guard before == runtimeStamp else { throw AIProviderError.incomplete }
        try storage.save(key, for: provider)
        configured.insert(provider); catalogs[provider] = models; advanceRevision()
    }
    func remove(_ provider: PersonalAIProvider) throws {
        guard !busy else { throw AIProviderError.unavailable }
        try storage.remove(for: provider); configured.remove(provider); catalogs[provider] = nil; advanceRevision()
    }
    func refresh(_ provider: PersonalAIProvider) async throws -> [AIModelDescriptor] {
        let before = runtimeStamp, key = try token(for: provider.rawValue)
        let models = try await AIProviderRegistry.provider(provider.rawValue).models(token: key)
        guard before == runtimeStamp else { throw AIProviderError.incomplete }
        catalogs[provider] = models; return models
    }
}
#if !canImport(Security)
@MainActor private struct UnavailablePersonalKeyStorage: PersonalAPIKeyStorage {
    func load(for provider: PersonalAIProvider) throws -> String? { nil }
    func save(_ key: String, for provider: PersonalAIProvider) throws { throw PersonalAPIKeyError.inaccessible }
    func remove(for provider: PersonalAIProvider) throws { throw PersonalAPIKeyError.inaccessible }
}
#endif
