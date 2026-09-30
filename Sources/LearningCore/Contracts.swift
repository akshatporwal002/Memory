import Foundation

public protocol LibraryRepository: Sendable {
    func read() async throws -> LibrarySnapshot
    /// Validates and durably writes the complete transaction, or changes nothing.
    func commit(_ snapshot: LibrarySnapshot, expectedRevision: Int) async throws
}
public protocol Scheduler: Sendable {
    var identifier: String { get }
    func initialState(now: Date, settings: StudySettings) throws -> ScheduleState
    func outcomes(state: ScheduleState, history: [ReviewEvent], now: Date, settings: StudySettings) throws -> [Grade: ScheduleState]
}

/// Optional adapter capability, used only after explicit scheduling-treatment confirmation.
/// Source defaults/weights and originals stay in sourceSchedule for round-trip and disclosure.
public protocol ImportedScheduleMapping: Scheduler {
    func importState(due: Date, phase: LearningPhase, sourceValues: [String: String], settings: StudySettings) throws -> ScheduleState
}

/// Optional read-only estimate. Nil means the state cannot be estimated safely.
public protocol MemoryEstimating: Sendable {
    func recallProbability(state: ScheduleState, now: Date, settings: StudySettings) -> Double?
}
