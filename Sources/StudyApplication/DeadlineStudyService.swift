import Foundation
import LearningCore

extension StudyService {
    func plannedSessionCards(_ session: StudySession, in library: LibrarySnapshot, now: Date) -> [StudyCard] {
        guard let ids = session.deadlineCardIDs else { return QueuePolicy.dueCards(in: library, deckID: session.deckID, now: now) }
        let completed = Set(library.activeReviews.filter { $0.sessionID == session.id }.map(\.cardID))
        let eligible = QueuePolicy.eligibleCards(in: library, deckID: session.deckID)
        return ids.filter { !completed.contains($0) && !(session.skippedCardIDs ?? []).contains($0) }
            .compactMap { id in eligible.first { $0.id == id } }
    }
    public func deadlineRecord(deckID: String) async throws -> DeadlineRecord? {
        guard let coordinator = learnerCoordinator else { throw LearnerError.unavailable }
        let context = try await coordinator.context()
        let workspace = try await coordinator.store.workspace(account: context.account, library: context.library)
        try await coordinator.check(context)
        return workspace.deadlineRecords?.first { $0.goal.deckID == deckID }
    }
    /// Explicit saving freezes the target content. Reading analytics never changes the blueprint.
    public func saveDeadlineGoal(deckID: String, deadline: Date, target: Double, dailyMinutes: Int, now: Date = Date()) async throws {
        guard let coordinator = learnerCoordinator else { throw LearnerError.unavailable }
        let context = try await coordinator.context()
        guard context.snapshot.liveDecks.contains(where: { $0.id == deckID }), !context.snapshot.isDeckSuspended(deckID) else { throw LearnerError.unavailable }
        var workspace = try await coordinator.store.workspace(account: context.account, library: context.library)
        let notes = Dictionary(uniqueKeysWithValues: context.snapshot.liveNotes.map { ($0.id, $0) })
        let items = try context.snapshot.liveCards.filter { $0.deckID == deckID && !$0.suspended }.sorted { $0.id < $1.id }.compactMap { card -> DeadlineGoal.Item? in
            guard let note = notes[card.noteID], note.kind != .unsupported else { return nil }
            let rendered = try CardRenderer.render(note: note, card: card, revealed: true)
            guard let answer = rendered.answer, !answer.isEmpty else { return nil }
            let reviewed = workspace.questions.last { $0.mapping.questionID == card.id && $0.prompt == rendered.prompt && $0.expectedAnswer == rendered.answer }
            return DeadlineGoal.Item(id: card.id, prompt: rendered.prompt, answer: answer, questionType: note.canonicalQuestionType,
                         questionVersion: reviewed?.mapping.questionVersion ?? card.version)
        }
        let goal = DeadlineGoal(deckID: deckID, createdAt: now, deadline: deadline, target: target, dailyMinutes: dailyMinutes, items: items)
        try goal.validate()
        var records = workspace.deadlineRecords ?? []
        records.removeAll { $0.goal.deckID == deckID }; records.append(DeadlineRecord(goal: goal))
        workspace.deadlineRecords = records
        try await coordinator.save(workspace, context: context)
        _ = try await deadlinePlan(deckID: deckID, now: now, saveForecast: true)
    }
    public func deadlinePlan(deckID: String, now: Date = Date(), saveForecast: Bool = false) async throws -> DeadlinePlan {
        guard let coordinator = learnerCoordinator else { throw LearnerError.unavailable }
        let context = try await coordinator.context()
        try await coordinator.synchronize(context)
        var workspace = try await coordinator.store.workspace(account: context.account, library: context.library)
        let state = try await coordinator.store.load(account: context.account, library: context.library)
        guard let index = workspace.deadlineRecords?.firstIndex(where: { $0.goal.deckID == deckID }) else { throw LearnerError.unavailable }
        let goal = workspace.deadlineRecords![index].goal
        let notes = Dictionary(uniqueKeysWithValues: context.snapshot.liveNotes.map { ($0.id, $0) })
        let cards = Dictionary(uniqueKeysWithValues: context.snapshot.liveCards.map { ($0.id, $0) })
        let stale = goal.items.filter { item in
            guard !context.snapshot.isDeckSuspended(deckID), let card = cards[item.id], card.deckID == deckID, !card.suspended,
                  let note = notes[card.noteID], let rendered = try? CardRenderer.render(note: note, card: card, revealed: true) else { return true }
            return item.prompt != rendered.prompt || item.answer != rendered.answer || item.questionType != note.canonicalQuestionType
        }.count
        // Scheduling revisions can change without content changing. Exact durable
        // pre-answer captures verify these attempts against the frozen blueprint.
        let items = Dictionary(uniqueKeysWithValues: goal.items.map { ($0.id, $0) })
        let verified = Set(workspace.captures.filter { capture in
            guard let item = items[capture.questionID] else { return false }
            return capture.questionPrompt == item.prompt && capture.questionExpectedAnswer == item.answer
        }.map(\.attemptID))
        // Manual review is not a correctness label, but still prevents immediate redundant practice.
        let recent = Set(context.snapshot.activeReviews.filter { $0.reviewedAt <= now && now.timeIntervalSince($0.reviewedAt) < 86400 }.map(\.cardID))
        let plan = try await Task.detached {
            try DeadlinePlanner.make(goal: goal, evidence: state.latest, evidenceRevision: state.revision, staleItems: stale, verifiedAttemptIDs: verified, recentlyPractisedIDs: recent, now: now)
        }.value
        try await coordinator.check(context)
        guard try await coordinator.store.load(account: context.account, library: context.library).revision == state.revision,
              try await coordinator.spaces.read().revision == context.snapshot.revision else { throw LearnerError.conflict }
        if saveForecast {
            workspace.deadlineRecords![index].forecasts.append(plan)
            workspace.deadlineRecords![index].forecasts = Array(workspace.deadlineRecords![index].forecasts.suffix(100))
            try await coordinator.save(workspace, context: context)
        }
        return plan
    }
    public func removeDeadlineGoal(deckID: String) async throws {
        guard let coordinator = learnerCoordinator else { throw LearnerError.unavailable }
        let context = try await coordinator.context()
        var workspace = try await coordinator.store.workspace(account: context.account, library: context.library)
        workspace.deadlineRecords?.removeAll { $0.goal.deckID == deckID }
        try await coordinator.save(workspace, context: context)
    }
}
