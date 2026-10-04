import XCTest
import Foundation
import AIInfrastructure
@testable import Features

@MainActor private final class FixturePersonalKeyStorage: PersonalAPIKeyStorage {
    var values: [PersonalAIProvider: String] = [:]
    func load(for provider: PersonalAIProvider) throws -> String? { values[provider] }
    func save(_ key: String, for provider: PersonalAIProvider) throws { values[provider] = key }
    func remove(for provider: PersonalAIProvider) throws { values[provider] = nil }
}
final class PersonalAIConnectionTests: XCTestCase {
    @MainActor func testKeyChangesPersistGenerationButRestartPreservesAssessmentIdentity() throws {
        let suite = "engram-provider-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = FixturePersonalKeyStorage(); storage.values[.openai] = "fixture-key-123456789"
        let first = PersonalAIConnections(storage: storage, defaults: defaults)
        let previous = first.stamp
        XCTAssertTrue(first.configured.contains(.openai))
        try first.remove(.openai)
        XCTAssertNotEqual(first.stamp, previous)
        XCTAssertFalse(first.configured.contains(.openai))
        let restarted = PersonalAIConnections(storage: storage, defaults: defaults)
        XCTAssertEqual(first.stamp, restarted.stamp)
        XCTAssertNotEqual(first.runtimeStamp, restarted.runtimeStamp)
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { ($0 as? String)?.contains("fixture-key") == true })
    }
    @MainActor func testSwitchingProfilesChangesRuntimeIdentityAndDoesNotExposePreviousKey() throws {
        let suite = "engram-provider-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let local = FixturePersonalKeyStorage(); local.values[.gemini] = "fixture-local-123456789"
        let other = FixturePersonalKeyStorage()
        let connections = PersonalAIConnections(storage: local, defaults: defaults, makeStorage: { $0 == "local" ? local : other })
        let original = connections.runtimeStamp
        connections.selectAccount("other")
        XCTAssertTrue(connections.configured.isEmpty)
        XCTAssertThrowsError(try connections.token(for: "gemini"))
        connections.selectAccount("local")
        XCTAssertEqual(try connections.token(for: "gemini"), "fixture-local-123456789")
        XCTAssertNotEqual(connections.runtimeStamp, original)
    }
    @MainActor func testMalformedKeyDoesNotReplaceExistingKeyOrStartProviderRequest() async throws {
        let suite = "engram-provider-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = FixturePersonalKeyStorage(); storage.values[.openai] = "fixture-original-123456789"
        let connections = PersonalAIConnections(storage: storage, defaults: defaults)
        do { try await connections.save("short", provider: .openai); XCTFail("Expected local rejection") }
        catch { XCTAssertTrue(error is PersonalAPIKeyError) }
        XCTAssertEqual(try connections.token(for: "openai"), "fixture-original-123456789")
        XCTAssertFalse(connections.busy)
    }
}
