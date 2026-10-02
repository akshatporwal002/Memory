import Foundation

public enum ReviewReconciliation {
    /// Both concurrent events survive. Stable ID is the tie-breaker for equal capture times.
    public static func replay(card: StudyCard, events: [ReviewEvent], settings: StudySettings, scheduler: any Scheduler) throws -> ScheduleState {
        let ordered = events.filter { $0.cardID == card.id }.sorted { $0.reviewedAt == $1.reviewedAt ? $0.id < $1.id : $0.reviewedAt < $1.reviewedAt }
        guard Set(ordered.map(\.id)).count == ordered.count else { throw EngramError.invalid("Duplicate review IDs require reconciliation.") }
        guard let first = ordered.first else { return card.schedule }
        // First event's before-state preserves imported baselines rather than resetting mature cards.
        var state = first.before, history: [ReviewEvent] = []
        for event in ordered {
            guard let recorded = event.settingsSnapshot ?? (event.before.settingsVersion == settings.version ? settings : nil) else { throw EngramError.invalid("A historical settings version is missing. Resolve the schedule rather than inventing it.") }
            let outcomes = try scheduler.outcomes(state:state,history:history,now:event.reviewedAt,settings:recorded)
            guard let next = outcomes[event.rating] else { throw EngramError.invalid("Review replay failed.") }
            state = next; var replayed = event; replayed.after = next; history.append(replayed)
        }
        return state
    }
}
