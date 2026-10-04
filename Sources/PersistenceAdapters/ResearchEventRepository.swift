import Foundation
import LearningCore

/// Separate from library backup/sync; research cannot leak into shared decks.
public actor ResearchEventRepository {
    public struct State: Codable, Sendable {
        public var consent = ResearchConsent()
        public var events: [ResearchEvent] = []
        public var seen: [String: Date] = [:]
        public init() {}
    }
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func load(account: UUID) throws -> State {
        let url = file(account)
        guard FileManager.default.fileExists(atPath: url.path) else { return State() }
        var state = try JSONDecoder().decode(State.self, from: Data(contentsOf: url))
        let cutoff = Date().addingTimeInterval(-365 * 86400)
        let prior = state.events.count + state.seen.count
        state.events.removeAll { $0.occurredAt < cutoff }
        state.seen = state.seen.filter { $0.value >= cutoff }
        if prior != state.events.count + state.seen.count { try save(state, account: account) }
        return state
    }
    public func setConsent(_ consent: ResearchConsent, account: UUID) throws {
        var state = try load(account: account); state.consent = consent
        if !consent.metrics { state.events = []; state.seen = [:] }
        else if !consent.answerContent { for i in state.events.indices { state.events[i].answerText = nil } }
        for i in state.events.indices { state.events[i].consentRevision = consent.revision }
        try save(state, account: account)
    }
    public func append(_ supplied: ResearchEvent, deduplicationKey: String, account: UUID, now: Date = Date()) throws {
        var state = try load(account: account)
        guard let event = supplied.permitted(by: state.consent, now: now), state.seen[deduplicationKey] == nil else { return }
        state.events.removeAll { $0.occurredAt < now.addingTimeInterval(-365 * 86400) }
        state.seen = state.seen.filter { $0.value >= now.addingTimeInterval(-365 * 86400) }
        state.events.append(event); state.seen[deduplicationKey] = event.occurredAt
        // Bounded local storage; dropping oldest metrics never blocks study.
        if state.events.count > 10_000 { state.events.removeFirst(state.events.count - 10_000) }
        try save(state, account: account)
    }
    public func acknowledge(_ ids: Set<UUID>, account: UUID) throws {
        var state = try load(account: account); state.events.removeAll { ids.contains($0.id) }; try save(state, account: account)
    }
    public func delete(account: UUID) throws {
        let url = file(account); if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    private func file(_ account: UUID) -> URL { directory.appendingPathComponent(account.uuidString.lowercased()).appendingPathExtension("json") }
    private func save(_ state: State, account: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = file(account)
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
        var excluded = url; var resource = URLResourceValues(); resource.isExcludedFromBackup = true
        try excluded.setResourceValues(resource)
    }
}
