import Foundation
import LearningCore

/// Device-local learner state. Independent of library sharing, research uploads and cloud consent.
/// Use one repository actor per directory. Revisions reject stale preparations across clients.
public actor LearnerModelRepository: LearnerModelStore {
    private struct Envelope: Codable {
        let account: UUID
        let library: String
        let state: LearnerState
        let workspace: LearnerWorkspace?
    }
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func load(account: UUID, library: String) throws -> LearnerState {
        let url = try file(account: account, library: library)
        guard FileManager.default.fileExists(atPath: url.path) else { return LearnerState() }
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url))
        guard envelope.account == account, envelope.library == library.lowercased() else { throw LearnerError.conflict }
        try envelope.state.validate(); return envelope.state
    }
    public func workspace(account: UUID, library: String) throws -> LearnerWorkspace {
        let url = try file(account: account, library: library)
        guard FileManager.default.fileExists(atPath: url.path) else { return LearnerWorkspace() }
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url))
        guard envelope.account == account, envelope.library == library.lowercased() else { throw LearnerError.conflict }
        let workspace = envelope.workspace ?? LearnerWorkspace(); try workspace.validate(); return workspace
    }
    public func saveWorkspace(_ workspace: LearnerWorkspace, expectedRevision: Int, account: UUID, library: String) throws {
        let prior = try self.workspace(account: account, library: library)
        guard prior.revision == expectedRevision, workspace.revision == expectedRevision else { throw LearnerError.conflict }
        try workspace.validate()
        guard workspace.candidates.allSatisfy({ $0.account == account && $0.library == library.lowercased() }) else { throw LearnerError.conflict }
        let state = try load(account: account, library: library)
        var next = workspace; next.revision += 1
        try save(state, workspace: next, account: account, library: library)
    }
    public func reconcile(_ events: [LearnerEvidence], refreshAtBoundary: Bool, account: UUID, library: String) throws {
        var state = try load(account: account, library: library)
        let workspace = try self.workspace(account: account, library: library), prior = state.configuration, before = state.revision
        for event in events { try state.append(event) }
        guard before != state.revision else { return }
        if refreshAtBoundary {
            for model in [prior.skill, prior.difficulty, prior.diagnosis] where prior.modes[model.purpose] != .off {
                if let candidate = workspace.candidate(for: model, state: state) {
                    do {
                        _ = try state.prepare(using: candidate.predictor())
                        try state.switchModel(to: model, mode: prior.modes[model.purpose] ?? .off, betweenAttempts: true)
                    } catch { /* Evidence stays durable. Stale/failed predictions remain observation-only. */ }
                }
            }
        }
        try save(state, account: account, library: library)
    }
    public func append(_ evidence: LearnerEvidence, account: UUID, library: String) throws {
        var state = try load(account: account, library: library)
        try state.append(evidence); try save(state, account: account, library: library)
    }
    public func setPracticePreferences(fixed: Bool, provisionalFeedback: Bool, account: UUID, library: String) throws {
        var state = try load(account: account, library: library)
        state.setPracticePreferences(fixed: fixed, provisionalFeedback: provisionalFeedback)
        try save(state, account: account, library: library)
    }
    public func prepare(using predictor: any LearnerPredictor, account: UUID, library: String) throws -> LearnerSnapshot {
        var state = try load(account: account, library: library)
        let snapshot = try state.prepare(using: predictor)
        try save(state, account: account, library: library); return snapshot
    }
    public func switchModel(to model: LearnerModelID, mode: LearnerMode, expectedEvidenceRevision: Int,
                            betweenAttempts: Bool, account: UUID, library: String) throws {
        var state = try load(account: account, library: library)
        guard state.revision == expectedEvidenceRevision else { throw LearnerError.conflict }
        try state.switchModel(to: model, mode: mode, betweenAttempts: betweenAttempts)
        try save(state, account: account, library: library)
    }
    public func delete(account: UUID, library: String) throws {
        let url = try file(account: account, library: library)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    private func file(account: UUID, library: String) throws -> URL {
        guard library == "default" || UUID(uuidString: library) != nil else { throw LearnerError.invalidEvidence }
        return directory.appendingPathComponent(account.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(library.lowercased()).appendingPathExtension("json")
    }
    private func save(_ state: LearnerState, workspace supplied: LearnerWorkspace? = nil, account: UUID, library: String) throws {
        try state.validate()
        let url = try file(account: account, library: library)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let workspace = try supplied ?? self.workspace(account: account, library: library)
        try workspace.validate()
        try JSONEncoder().encode(Envelope(account: account, library: library.lowercased(), state: state, workspace: workspace)).write(to: url, options: .atomic)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
    }
}
