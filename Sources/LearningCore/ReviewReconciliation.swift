import Foundation

public enum ReviewReconciliation {
    /// Both concurrent events survive. Stable ID is the tie-breaker for equal capture times.
    public static func replay(card: StudyCard, events: [ReviewEvent], settings: StudySettings, scheduler: any Scheduler, baseline: ScheduleState? = nil) throws -> ScheduleState {
        let ordered = events.filter { $0.cardID == card.id }.sorted { $0.reviewedAt == $1.reviewedAt ? $0.id < $1.id : $0.reviewedAt < $1.reviewedAt }
        guard Set(ordered.map(\.id)).count == ordered.count else { throw EngramError.invalid("Duplicate review IDs require reconciliation.") }
        guard let first = ordered.first else { return baseline ?? card.schedule }
        // First event's before-state preserves imported baselines rather than resetting mature cards.
        var state = baseline ?? first.before, history: [ReviewEvent] = []
        for event in ordered {
            // A sequential historical event already records its exact transition. Replay is
            // required only after concurrent events diverge from that captured before-state.
            if event.before == state { state = event.after; history.append(event); continue }
            guard let recorded = event.settingsSnapshot ?? (event.before.settingsVersion == settings.version ? settings : nil) else { throw EngramError.invalid("A historical settings version is missing. Resolve the schedule rather than inventing it.") }
            let outcomes = try scheduler.outcomes(state:state,history:history,now:event.reviewedAt,settings:recorded)
            guard let next = outcomes[event.rating] else { throw EngramError.invalid("Review replay failed.") }
            state = next; var replayed = event; replayed.after = next; history.append(replayed)
        }
        return state
    }
    /// Corrected/undone events are audit evidence, not active grades. Their
    /// earliest before-state still anchors imported progress when the first
    /// active event changes. Otherwise a later event can resurrect a removed grade.
    public static func replay(card: StudyCard, allEvents: [ReviewEvent], corrections: [ReviewCorrection], settings: StudySettings, scheduler: any Scheduler) throws -> ScheduleState {
        let events = allEvents.filter { $0.cardID == card.id }
        let baseline = events.min { $0.reviewedAt == $1.reviewedAt ? $0.id < $1.id : $0.reviewedAt < $1.reviewedAt }?.before
        let removed = Set(corrections.map(\.reviewID))
        return try replay(card: card, events: events.filter { !removed.contains($0.id) }, settings: settings, scheduler: scheduler, baseline: baseline)
    }
}
