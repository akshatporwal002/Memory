import Foundation
import LearningCore

extension StudyService {
    /// Newly instrumented presentations only; no historical mappings/assistance are fabricated.
    public func captureCurrentLearnerRecall(now: Date = Date()) async throws {
        guard let coordinator = learnerCoordinator else { return }
        let context = try await coordinator.context()
        let workspace = try await coordinator.store.workspace(account: context.account, library: context.library)
        guard workspace.recordingEnabled, let item = context.snapshot.session?.current, item.revealedAt == nil,
              let note = context.snapshot.liveNotes.first(where: { $0.id == item.card.noteID }),
              !workspace.captures.contains(where: { $0.presentationID == item.presentationID }) else { return }
        let rendered = try CardRenderer.render(note: note, card: item.card, revealed: true)
        let state = try await coordinator.store.load(account: context.account, library: context.library)
        let accepted = Set(state.latest.filter { $0.kind == .recall && $0.acceptance == .accepted }.map(\.attemptID))
        let previous = workspace.captures.filter { accepted.contains($0.attemptID) && $0.kind == .recall
            && $0.questionID == item.card.id && $0.questionPrompt == rendered.prompt && $0.questionExpectedAnswer == rendered.answer && $0.startedAt <= now }.max { $0.startedAt < $1.startedAt }
        try await coordinator.check(context)
        _ = try await coordinator.beginRecall(presentationID: item.presentationID, assisted: nil, now: now,
            delaySeconds: previous.map { now.timeIntervalSince($0.startedAt) }, assessmentID: nil, assessmentSessionID: nil)
    }
}
