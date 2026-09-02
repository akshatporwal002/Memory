import Foundation
import LearningCore
import FSRS

public struct FSRSScheduler: ImportedScheduleMapping {
    public let identifier = "fsrs-6"
    public static let implementation = "swift-fsrs-4fbaf201"
    public init() {}
    public func initialState(now: Date, settings: StudySettings) throws -> ScheduleState {
        try envelope(Card(due: now), settings: settings)
    }
    public func importState(due: Date, phase: LearningPhase, sourceValues: [String: String], settings: StudySettings) throws -> ScheduleState {
        if phase == .new { return try envelope(Card(due: due), settings: settings) }
        guard phase == .review,
              let stability = Double(sourceValues["s"] ?? ""), stability > 0, stability.isFinite,
              let difficulty = Double(sourceValues["d"] ?? ""), (1...10).contains(difficulty),
              let last = Double(sourceValues["lrt"] ?? ""), last.isFinite else {
            throw EngramError.unsupported("Only new cards and FSRS review cards with stability, difficulty and last-review timestamps can preserve scheduling. Learning/relearning and legacy SM-2 states require an explicit content-only import. Originals and history remain in native backups.")
        }
        let card = Card(due: due, stability: stability, difficulty: difficulty,
            scheduledDays: max(0, Double(sourceValues["ivl"] ?? "") ?? 0),
            reps: max(0, Int(sourceValues["reps"] ?? "") ?? 0), lapses: max(0, Int(sourceValues["lapses"] ?? "") ?? 0),
            state: .review, lastReview: Date(timeIntervalSince1970: last))
        return try envelope(card, settings: settings)
    }
    public func outcomes(state: ScheduleState, history: [ReviewEvent], now: Date, settings: StudySettings) throws -> [Grade: ScheduleState] {
        guard state.schedulerID == identifier, state.schemaVersion == 1, state.implementationVersion == Self.implementation else {
            throw EngramError.unsupported("This card uses an unsupported scheduler state. Export a backup before choosing an explicit migration.")
        }
        guard now.timeIntervalSince1970.isFinite, (0.7...0.99).contains(settings.desiredRetention) else { throw EngramError.invalid("Invalid scheduling time or retention setting.") }
        let card = try JSONDecoder().decode(Card.self, from: state.payload)
        guard card.due == state.due, card.lastReview == nil || card.lastReview! <= now,
              card.stability.isFinite, card.difficulty.isFinite, card.stability >= 0,
              card.reps >= 0, card.lapses >= 0 else { throw EngramError.invalid("The saved scheduling state is invalid or the clock moved backwards.") }
        let params = FSRSParameters(requestRetention: settings.desiredRetention, maximumInterval: 36_500,
            w: FSRSDefaults.defaultWv6, enableFuzz: false, enableShortTerm: true,
            learningSteps: ["1m", "10m"], relearningSteps: ["10m"])
        // The vendor engine is local to this call, avoiding shared mutable algorithm state.
        let engine = FSRS(parameters: params)
        var results: [Grade: ScheduleState] = [:]
        for grade in Grade.allCases {
            guard let rating = Rating(rawValue: grade.rawValue) else { continue }
            let result = try engine.next(card: card, now: now, grade: rating)
            results[grade] = try envelope(result.card, settings: settings)
        }
        return results
    }
    private func envelope(_ card: Card, settings: StudySettings) throws -> ScheduleState {
        let phase: LearningPhase
        switch card.state { case .new: phase = .new; case .learning: phase = .learning; case .review: phase = .review; case .relearning: phase = .relearning }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return ScheduleState(schedulerID: identifier, implementationVersion: Self.implementation, settingsVersion: settings.version,
            due: card.due, phase: phase, payload: try encoder.encode(card))
    }
}
