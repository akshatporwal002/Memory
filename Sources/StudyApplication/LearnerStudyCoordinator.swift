import Foundation
import LearningCore

/// Opt-in device-local integration. Durable pre-answer captures are reconciled from
/// accepted reviews after each study commit and on read/restart. A learner-store failure
/// cannot roll back a successful FSRS commit or falsely authorize a stale prediction.
actor LearnerStudyCoordinator {
    let store: any LearnerModelStore
    let spaces: LibrarySpaceRepository
    let accountProvider: @Sendable () async -> UUID?
    private(set) var lastError: String?
    init(store: any LearnerModelStore, spaces: LibrarySpaceRepository, accountProvider: @escaping @Sendable () async -> UUID?) {
        self.store = store; self.spaces = spaces; self.accountProvider = accountProvider
    }
    struct Context: Sendable {
        let account: UUID
        let library: String
        let snapshot: LibrarySnapshot
    }
    func context() async throws -> Context {
        guard let account = await accountProvider() else { throw LearnerError.unavailable }
        let library = await spaces.selectedID, snapshot = try await spaces.read()
        let context = Context(account: account, library: library, snapshot: snapshot)
        try await check(context); return context
    }
    func check(_ context: Context) async throws {
        guard await accountProvider() == context.account, await spaces.selectedID == context.library,
              try await spaces.read().repositoryContext == context.snapshot.repositoryContext else { throw LearnerError.conflict }
    }
    func save(_ workspace: LearnerWorkspace, context: Context) async throws {
        try await check(context)
        try await store.saveWorkspace(workspace, expectedRevision: workspace.revision, account: context.account, library: context.library)
        try await check(context)
    }
    func synchronize(_ snapshot: LibrarySnapshot) async {
        do {
            let context = try await context()
            guard context.snapshot.repositoryContext == snapshot.repositoryContext,
                  context.snapshot.revision == snapshot.revision else { return }
            try await synchronize(context); lastError = nil
        } catch { lastError = "Learner evidence needs reconciliation: \(error.localizedDescription)" }
    }
    func synchronize(_ context: Context) async throws {
        let workspace = try await store.workspace(account: context.account, library: context.library)
        let state = try await store.load(account: context.account, library: context.library)
        let latest = Dictionary(uniqueKeysWithValues: state.latest.map { ($0.attemptID, $0) })
        var updates: [LearnerEvidence] = []
        for capture in workspace.captures where capture.kind == .recall {
            let prior = latest[capture.attemptID]
            let attempt = context.snapshot.answerAttempts?.first { $0.id == capture.attemptID }
            let reviews = context.snapshot.activeReviews.filter { review in
                review.cardID == capture.questionID && review.sessionID == capture.sessionID
                    && (review.presentationID == capture.presentationID || review.id == "answer-" + capture.presentationID || attempt.map { review.reviewedAt == $0.createdAt && review.assessment == $0.assessment } == true)
            }
            let accepted = reviews.last { $0.assessment != nil && $0.gradingMethod != "manual" }
            let row: LearnerEvidence
            if let accepted, let assessment = accepted.assessment, assessment.rating == accepted.rating,
               accepted.gradingMethod == assessment.method,
               ["ai", "mcq-local", "local-exact"].contains(assessment.method) {
                let correct: Bool? = assessment.outcome == .correct ? true : assessment.outcome == .incorrect ? false : nil
                row = capture.evidence(revision: (prior?.revision ?? 0) + 1, acceptance: .accepted, correct: correct,
                    method: assessment.method, knownAssistance: attempt?.assisted)
            } else if reviews.contains(where: { $0.gradingMethod == "manual" }) {
                row = capture.evidence(revision: (prior?.revision ?? 0) + 1, acceptance: .accepted, correct: nil, method: "manual-self-report")
            } else if reviews.contains(where: { $0.gradingMethod == nil && $0.assessment != nil }) {
                row = capture.evidence(revision: (prior?.revision ?? 0) + 1, acceptance: .accepted, correct: nil, method: "unknown-grading-provenance")
            } else if prior?.acceptance == .accepted || prior?.acceptance == .retracted {
                row = capture.evidence(revision: prior!.revision + 1, acceptance: .retracted, correct: nil, method: "review-reconciliation")
            } else { continue }
            if let prior {
                let comparable = LearnerEvidence(attemptID: row.attemptID, revision: prior.revision, questionID: row.questionID,
                    questionVersion: row.questionVersion, occurredAt: row.occurredAt, kind: row.kind, mapping: row.mapping,
                    assisted: row.assisted, acceptance: row.acceptance, correct: row.correct, gradingMethod: row.gradingMethod,
                    unfamiliar: row.unfamiliar, delaySeconds: row.delaySeconds, studySeconds: row.studySeconds,
                    errorSkillIDs: row.errorSkillIDs, assessmentID: row.assessmentID, assessmentSessionID: row.assessmentSessionID,
                    configuration: row.configuration, policyRevision: row.policyRevision)
                if comparable == prior { continue }
            }
            updates.append(row)
        }
        try await check(context)
        let boundary = !isAttemptInProgress(workspace: workspace, state: state, snapshot: context.snapshot)
        try await store.reconcile(updates, refreshAtBoundary: boundary, account: context.account, library: context.library)
    }
    nonisolated func isAttemptInProgress(workspace: LearnerWorkspace, state: LearnerState, snapshot: LibrarySnapshot) -> Bool {
        if workspace.understanding?.sessions.contains(where: { $0.endedAt == nil && $0.current != nil }) == true { return true }
        if workspace.captures.contains(where: { capture in
            capture.kind != .recall && capture.abandonedAt == nil &&
                ![LearnerEvidence.Acceptance.accepted, .retracted].contains(state.latest.first(where: { $0.attemptID == capture.attemptID })?.acceptance ?? .provisional)
        }) { return true }
        guard let presentation = snapshot.session?.current?.presentationID, snapshot.session?.current?.revealedAt == nil else { return false }
        return workspace.captures.contains { capture in
            capture.presentationID == presentation && state.latest.first(where: { $0.attemptID == capture.attemptID })?.acceptance != .accepted
        }
    }
    func setRecording(_ enabled: Bool) async throws {
        let context = try await context()
        var workspace = try await store.workspace(account: context.account, library: context.library)
        workspace.recordingEnabled = enabled
        if !enabled, var understanding = workspace.understanding {
            for si in understanding.sessions.indices {
                for ai in understanding.sessions[si].attempts.indices where understanding.sessions[si].attempts[ai].status != .assessed {
                    understanding.sessions[si].attempts[ai].recordingEnabled = false
                }
            }
            workspace.understanding = understanding
        }
        try await save(workspace, context: context)
        if !enabled {
            let state = try await store.load(account: context.account, library: context.library)
            for model in [state.configuration.skill, state.configuration.difficulty, state.configuration.diagnosis] {
                try await store.switchModel(to: model, mode: .off, expectedEvidenceRevision: state.revision, betweenAttempts: false, account: context.account, library: context.library)
            }
        }
    }
    func reviewQuestion(_ question: ReviewedLearnerQuestion, expectedAccount: UUID? = nil, expectedLibrary: String? = nil) async throws {
        try question.validate(); let context = try await context()
        guard expectedAccount.map({ $0 == context.account }) ?? true, expectedLibrary.map({ $0 == context.library }) ?? true else { throw LearnerError.conflict }
        var workspace = try await store.workspace(account: context.account, library: context.library)
        for existing in workspace.questions where existing.mapping.questionID == question.mapping.questionID && existing.mapping.questionVersion == question.mapping.questionVersion {
            guard existing.prompt == question.prompt, existing.expectedAnswer == question.expectedAnswer, existing.kind == question.kind else { throw LearnerError.conflict }
        }
        if let existing = workspace.questions.first(where: { $0.mapping.questionID == question.mapping.questionID && $0.mapping.questionVersion == question.mapping.questionVersion && $0.mapping.revision == question.mapping.revision }) {
            guard existing == question else { throw LearnerError.conflict }; return
        }
        workspace.questions.append(question); try await save(workspace, context: context)
    }
    func beginRecall(presentationID: String, assisted: Bool?, now: Date, delaySeconds: Double?, assessmentID: String?, assessmentSessionID: String?) async throws -> String {
        let context = try await context()
        var workspace = try await store.workspace(account: context.account, library: context.library)
        guard workspace.recordingEnabled, let session = context.snapshot.session, let item = session.current,
              item.presentationID == presentationID, item.revealedAt == nil,
              let note = context.snapshot.liveNotes.first(where: { $0.id == item.card.noteID }) else { throw LearnerError.unavailable }
        let attemptID = "attempt-" + presentationID
        guard !(context.snapshot.answerAttempts ?? []).contains(where: { $0.id == attemptID && !$0.originalAnswer.isEmpty }) else { throw LearnerError.conflict }
        if let captured = workspace.captures.first(where: { $0.attemptID == attemptID }) { return captured.attemptID }
        let rendered = try CardRenderer.render(note: note, card: item.card, revealed: true)
        let state = try await store.load(account: context.account, library: context.library)
        let question = workspace.questions.last { $0.mapping.questionID == item.card.id && $0.prompt == rendered.prompt && $0.expectedAnswer == rendered.answer && $0.kind == .recall }
        let capture = LearnerCapture(attemptID: attemptID, presentationID: presentationID, sessionID: session.id,
            capturedCardVersion: item.card.version, questionID: item.card.id, questionVersion: question?.mapping.questionVersion ?? item.card.version,
            kind: .recall, mapping: question?.mapping, startedAt: now, assisted: assisted, delaySeconds: delaySeconds,
            assessmentID: assessmentID, assessmentSessionID: assessmentSessionID, questionPrompt: rendered.prompt,
            questionExpectedAnswer: rendered.answer, configuration: state.configuration)
        try capture.validate(); workspace.captures.append(capture); try await save(workspace, context: context); return attemptID
    }
    func measure(attemptID: String, seconds: Double?, assisted: Bool?) async throws {
        let context = try await context()
        var workspace = try await store.workspace(account: context.account, library: context.library)
        let state = try await store.load(account: context.account, library: context.library)
        guard let index = workspace.captures.firstIndex(where: { $0.attemptID == attemptID }),
              state.latest.first(where: { $0.attemptID == attemptID })?.acceptance != .accepted else { throw LearnerError.conflict }
        if let seconds { workspace.captures[index].studySeconds = seconds }
        if let assisted { workspace.captures[index].assisted = assisted }
        try workspace.captures[index].validate(); try await save(workspace, context: context)
    }
    func provisional(attemptID: String, method: String) async throws {
        let context = try await context(), workspace = try await store.workspace(account: context.account, library: context.library)
        let state = try await store.load(account: context.account, library: context.library)
        guard workspace.recordingEnabled, state.configuration.provisionalFeedback,
              let capture = workspace.captures.first(where: { $0.attemptID == attemptID }),
              state.latest.first(where: { $0.attemptID == attemptID })?.acceptance != .accepted else { throw LearnerError.conflict }
        let revision = (state.latest.first { $0.attemptID == attemptID }?.revision ?? 0) + 1
        try await store.reconcile([capture.evidence(revision: revision, acceptance: .provisional, correct: nil, method: method)], refreshAtBoundary: false, account: context.account, library: context.library)
    }
    func switchModel(to model: LearnerModelID, mode: LearnerMode) async throws {
        let context = try await context(); try await synchronize(context)
        let state = try await store.load(account: context.account, library: context.library)
        let workspace = try await store.workspace(account: context.account, library: context.library)
        let boundary = !isAttemptInProgress(workspace: workspace, state: state, snapshot: context.snapshot)
        guard mode == .off || (workspace.recordingEnabled && boundary) else { throw LearnerError.conflict }
        if mode != .off {
            guard let candidate = workspace.candidate(for: model, state: state) else { throw LearnerError.unavailable }
            _ = try await store.prepare(using: candidate.predictor(), account: context.account, library: context.library)
        }
        try await check(context)
        try await store.switchModel(to: model, mode: mode, expectedEvidenceRevision: state.revision, betweenAttempts: boundary, account: context.account, library: context.library)
    }
}

actor LearnerObservingRepository: LibraryRepository {
    let base: LibrarySpaceRepository
    let coordinator: LearnerStudyCoordinator
    init(base: LibrarySpaceRepository, coordinator: LearnerStudyCoordinator) { self.base = base; self.coordinator = coordinator }
    func read() async throws -> LibrarySnapshot {
        let value = try await base.read(); await coordinator.synchronize(value); return value
    }
    func commit(_ snapshot: LibrarySnapshot, expectedRevision: Int) async throws {
        try await base.commit(snapshot, expectedRevision: expectedRevision)
        // The durable study transaction is authoritative; failures recover on read/restart.
        if let committed = try? await base.read() { await coordinator.synchronize(committed) }
    }
}
