import Foundation
import LearningCore

public struct LearnerQMatrix: Sendable {
    public let revision: String
    public let skillIDs: [String]
    public let questions: [ReviewedLearnerQuestion]
    /// Question-to-skill edges only; no inferred skill prerequisites.
    public var edges: [(questionID: String, version: Int, skillID: String)] {
        questions.flatMap { question in question.mapping.skillIDs.map { (question.mapping.questionID, question.mapping.questionVersion, $0) } }
    }
}

extension StudyService {
    public func learnerQMatrix(revision: String) async throws -> LearnerQMatrix {
        guard let coordinator = learnerCoordinator else { throw LearnerError.unavailable }
        let context = try await coordinator.context(), workspace = try await coordinator.store.workspace(account: context.account, library: context.library)
        let questions = workspace.questions.filter { $0.mapping.revision == revision }
        guard !questions.isEmpty else { throw LearnerError.unavailable }
        try await coordinator.check(context)
        return LearnerQMatrix(revision: revision, skillIDs: Array(Set(questions.flatMap { $0.mapping.skillIDs })).sorted(), questions: questions)
    }
    /// Explicit review of the captured question content. Does not infer mappings for legacy history.
    /// Matrix revisions can change without changing question-content versions.
    public func correctLearnerMapping(attemptID: String, reviewedQuestion: ReviewedLearnerQuestion) async throws {
        guard let coordinator = learnerCoordinator else { throw LearnerError.unavailable }
        try reviewedQuestion.validate()
        let context = try await coordinator.context()
        var workspace = try await coordinator.store.workspace(account: context.account, library: context.library)
        let state = try await coordinator.store.load(account: context.account, library: context.library)
        guard workspace.questions.contains(reviewedQuestion), let index = workspace.captures.firstIndex(where: { $0.attemptID == attemptID }) else { throw LearnerError.unavailable }
        let capture = workspace.captures[index]
        guard capture.questionID == reviewedQuestion.mapping.questionID, capture.questionVersion == reviewedQuestion.mapping.questionVersion,
              capture.kind == reviewedQuestion.kind, capture.questionPrompt == reviewedQuestion.prompt,
              capture.questionExpectedAnswer == reviewedQuestion.expectedAnswer else { throw LearnerError.invalidEvidence }
        if capture.mapping == reviewedQuestion.mapping { return }
        var updated = LearnerCapture(attemptID: capture.attemptID, presentationID: capture.presentationID, sessionID: capture.sessionID,
            capturedCardVersion: capture.capturedCardVersion, questionID: capture.questionID, questionVersion: capture.questionVersion,
            kind: capture.kind, mapping: reviewedQuestion.mapping, startedAt: capture.startedAt, assisted: capture.assisted,
            studySeconds: capture.studySeconds, delaySeconds: capture.delaySeconds, unfamiliar: capture.unfamiliar,
            assessmentID: capture.assessmentID, assessmentSessionID: capture.assessmentSessionID, sourceEvidence: capture.sourceEvidence,
            questionPrompt: capture.questionPrompt, questionExpectedAnswer: capture.questionExpectedAnswer,
            configuration: capture.configuration, policyRevision: capture.policyRevision)
        updated.abandonedAt = capture.abandonedAt
        updated.confirmedErrorSkillIDs = capture.confirmedErrorSkillIDs?.filter { reviewedQuestion.mapping.skillIDs.contains($0) }
        workspace.captures[index] = updated; try await coordinator.save(workspace, context: context)
        if let prior = state.latest.first(where: { $0.attemptID == attemptID }) {
            let correction = updated.evidence(revision: prior.revision + 1, acceptance: prior.acceptance, correct: prior.correct,
                method: prior.gradingMethod, knownAssistance: prior.assisted)
            try await coordinator.store.reconcile([correction], refreshAtBoundary: !coordinator.isAttemptInProgress(workspace: workspace, state: state, snapshot: context.snapshot),
                account: context.account, library: context.library)
        }
    }
    /// Recurring-error labels require explicit validated/human-confirmed skills, not a wrong answer alone.
    public func confirmLearnerSkillErrors(attemptID: String, skillIDs: [String]) async throws {
        guard let coordinator = learnerCoordinator else { throw LearnerError.unavailable }
        let context = try await coordinator.context()
        var workspace = try await coordinator.store.workspace(account: context.account, library: context.library)
        let state = try await coordinator.store.load(account: context.account, library: context.library)
        guard let prior = state.latest.first(where: { $0.attemptID == attemptID && $0.acceptance == .accepted && $0.correct == false }),
              let index = workspace.captures.firstIndex(where: { $0.attemptID == attemptID }),
              Set(skillIDs).count == skillIDs.count, Set(skillIDs).isSubset(of: Set(prior.mapping?.skillIDs ?? [])) else { throw LearnerError.invalidEvidence }
        workspace.captures[index].confirmedErrorSkillIDs = skillIDs
        try await coordinator.save(workspace, context: context)
        if prior.errorSkillIDs == skillIDs { return }
        let correction = workspace.captures[index].evidence(revision: prior.revision + 1, acceptance: .accepted, correct: false,
            method: prior.gradingMethod, knownAssistance: prior.assisted)
        try await coordinator.store.reconcile([correction], refreshAtBoundary: !coordinator.isAttemptInProgress(workspace: workspace, state: state, snapshot: context.snapshot),
            account: context.account, library: context.library)
    }
}
