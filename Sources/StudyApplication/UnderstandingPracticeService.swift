import Foundation
import LearningCore

extension StudyService {
    private func understandingContext() async throws -> (LearnerStudyCoordinator, LearnerStudyCoordinator.Context, LearnerWorkspace) {
        guard let coordinator = learnerCoordinator else { throw LearnerError.unavailable }
        let context = try await coordinator.context()
        var workspace = try await coordinator.store.workspace(account: context.account, library: context.library)
        if workspace.understanding == nil { workspace.understanding = UnderstandingWorkspace() }
        try await coordinator.check(context)
        return (coordinator, context, workspace)
    }
    public func setUnderstandingSettings(deckID: String, settings: UnderstandingSettings?, expectedRevision: Int) async throws {
        try settings?.validate()
        var library = try await repository.read()
        guard library.revision == expectedRevision, let index = library.decks.firstIndex(where: { $0.id == deckID && !$0.deleted }) else { throw EngramError.conflict }
        library.decks[index].understandingSettings = settings
        try await repository.commit(library, expectedRevision: library.revision)
    }
    public func understandingSessions() async throws -> [UnderstandingSession] {
        let (coordinator, context, workspace) = try await understandingContext()
        // Recover accepted grades after an interrupted evidence write. Never invent legacy labels.
        for session in workspace.understanding!.sessions {
            for attempt in session.attempts where attempt.recordingEnabled && attempt.status == .assessed {
                try await reconcileUnderstanding(attempt, coordinator: coordinator, context: context)
            }
        }
        try await coordinator.check(context)
        return workspace.understanding!.sessions
    }
    public func startUnderstandingSession(deckID: String, defaults: UnderstandingSettings, providerIdentity: String, gradingModel: String, now: Date = Date(), expectedAccount: UUID? = nil, expectedLibrary: String? = nil) async throws -> UnderstandingSession {
        let (coordinator, context, workspace) = try await understandingContext()
        guard expectedAccount.map({ $0 == context.account }) ?? true, expectedLibrary.map({ $0 == context.library }) ?? true else { throw LearnerError.conflict }
        guard let deck = context.snapshot.liveDecks.first(where: { $0.id == deckID }),
              workspace.understanding!.sessions.allSatisfy({ $0.endedAt != nil }) else { throw LearnerError.conflict }
        let settings = deck.understandingSettings ?? defaults; try settings.validate()
        guard settings.enabled, !providerIdentity.isEmpty, !gradingModel.isEmpty else { throw LearnerError.unavailable }
        if workspace.recordingEnabled {
            // The desired notebook selections never authorize an unavailable artifact.
            try await coordinator.store.setPracticePreferences(fixed: false, provisionalFeedback: settings.quickFeedback, account: context.account, library: context.library)
            for model in [settings.configuration.skill, settings.configuration.difficulty, settings.configuration.diagnosis] {
                let mode = settings.configuration.modes[model.purpose] ?? .off
                do { try await coordinator.switchModel(to: model, mode: mode) }
                catch LearnerError.unavailable {
                    // Fail closed rather than using a previous notebook's active model.
                    try await coordinator.switchModel(to: model, mode: .off)
                }
            }
        }
        var session = UnderstandingSession(deckID: deckID, now: now, settings: settings)
        guard let attempt = try await nextUnderstandingAttempt(session: session, context: context, workspace: workspace, providerIdentity: providerIdentity, gradingModel: gradingModel, now: now) else { throw EngramError.invalid("Prepare source-checked question approaches before starting understanding practice.") }
        session.attempts.append(attempt)
        var next = workspace; next.understanding!.sessions.append(session)
        try await saveUnderstanding(next, coordinator: coordinator, context: context)
        return session
    }
    public func submitUnderstandingAnswer(sessionID: String, attemptID: String, answer: String, assisted: Bool?, activeSeconds: Double?, provisional: Grade? = nil, now: Date = Date(), expectedAccount: UUID? = nil, expectedLibrary: String? = nil) async throws -> UnderstandingSession {
        let (coordinator, context, workspace) = try await understandingContext()
        guard expectedAccount.map({ $0 == context.account }) ?? true, expectedLibrary.map({ $0 == context.library }) ?? true else { throw LearnerError.conflict }
        var next = workspace
        guard let si = next.understanding!.sessions.firstIndex(where: { $0.id == sessionID }),
              next.understanding!.sessions[si].endedAt == nil,
              let ai = next.understanding!.sessions[si].attempts.firstIndex(where: { $0.id == attemptID && $0.status == .presented }),
              !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, answer.utf8.count <= 16000,
              activeSeconds.map({ $0.isFinite && $0 >= 0 }) ?? true else { throw LearnerError.conflict }
        var attempt = next.understanding!.sessions[si].attempts[ai]
        guard currentUnderstandingSource(attempt, in: context.snapshot) else { throw EngramError.conflict }
        attempt.answer = answer; attempt.assisted = assisted; attempt.activeSeconds = activeSeconds; attempt.submittedAt = now; attempt.status = .queued
        attempt.provisional = next.understanding!.sessions[si].settings.quickFeedback ? provisional : nil
        next.understanding!.sessions[si].attempts[ai] = attempt
        let session = next.understanding!.sessions[si]
        if let following = try await nextUnderstandingAttempt(session: session, context: context, workspace: next, providerIdentity: attempt.providerIdentity, gradingModel: attempt.gradingModel, now: now) {
            next.understanding!.sessions[si].attempts.append(following)
        } else { next.understanding!.sessions[si].endedAt = now }
        try await saveUnderstanding(next, coordinator: coordinator, context: context)
        return next.understanding!.sessions[si]
    }
    public func endUnderstandingSession(id: String, now: Date = Date()) async throws {
        let (coordinator, context, workspace) = try await understandingContext(); var next = workspace
        guard let index = next.understanding!.sessions.firstIndex(where: { $0.id == id }) else { throw LearnerError.unavailable }
        next.understanding!.sessions[index].endedAt = now
        for ai in next.understanding!.sessions[index].attempts.indices where next.understanding!.sessions[index].attempts[ai].status == .presented {
            next.understanding!.sessions[index].attempts[ai].status = .abandoned
        }
        try await saveUnderstanding(next, coordinator: coordinator, context: context)
    }
    public func saveUnderstandingDraft(sessionID: String, attemptID: String, answer: String, assisted: Bool?, activeSeconds: Double?, now: Date = Date(), expectedAccount: UUID? = nil, expectedLibrary: String? = nil) async throws {
        let (coordinator, context, workspace) = try await understandingContext(); var next = workspace
        guard expectedAccount.map({ $0 == context.account }) ?? true, expectedLibrary.map({ $0 == context.library }) ?? true,
              answer.utf8.count <= 16000, activeSeconds.map({ $0.isFinite && $0 >= 0 }) ?? true else { throw LearnerError.conflict }
        guard let si = next.understanding!.sessions.firstIndex(where: { $0.id == sessionID && $0.endedAt == nil }),
              let ai = next.understanding!.sessions[si].attempts.firstIndex(where: { $0.id == attemptID && $0.status == .presented }) else { return }
        if let previous = next.understanding!.sessions[si].attempts[ai].draftModifiedAt, previous >= now { return }
        next.understanding!.sessions[si].attempts[ai].answer = answer
        next.understanding!.sessions[si].attempts[ai].assisted = assisted
        next.understanding!.sessions[si].attempts[ai].activeSeconds = activeSeconds
        next.understanding!.sessions[si].attempts[ai].draftModifiedAt = now
        try await saveUnderstanding(next, coordinator: coordinator, context: context)
    }
    public func understandingBatch(providerIdentity: String) async throws -> [UnderstandingAttempt] {
        let (coordinator, context, prior) = try await understandingContext(); var workspace = prior
        var changed = false
        for si in workspace.understanding!.sessions.indices {
            for ai in workspace.understanding!.sessions[si].attempts.indices where workspace.understanding!.sessions[si].attempts[ai].status == .queued {
                let attempt = workspace.understanding!.sessions[si].attempts[ai]
                if !currentUnderstandingSource(attempt, in: context.snapshot) || attempt.providerIdentity != providerIdentity {
                    workspace.understanding!.sessions[si].attempts[ai].status = .attention
                    workspace.understanding!.sessions[si].attempts[ai].error = "Source or grading connection changed. Restore the source/connection or request a new assessment."
                    changed = true
                }
            }
        }
        if changed { try await saveUnderstanding(workspace, coordinator: coordinator, context: context) }
        let sessions = workspace.understanding!.sessions
        for session in sessions {
            guard session.settings.reviewTiming == .background || session.endedAt != nil else { continue }
            let eligible = session.attempts.filter { $0.status == .queued && $0.providerIdentity == providerIdentity && currentUnderstandingSource($0, in: context.snapshot) }
            guard let first = eligible.first else { continue }
            // Flush short background batches only after the session has ended.
            guard session.endedAt != nil || eligible.count >= session.settings.batchSize else { continue }
            return Array(eligible.filter { $0.gradingModel == first.gradingModel }.prefix(session.settings.batchSize))
        }
        return []
    }
    /// Existing source-evidence acceptance boundary; corrections preserve this exact attempt.
    public func acceptUnderstandingAssessment(attemptID: String, json: String, providerIdentity: String, expectedAccount: UUID? = nil, expectedLibrary: String? = nil) async throws {
        let (coordinator, context, workspace) = try await understandingContext(); var next = workspace
        guard expectedAccount.map({ $0 == context.account }) ?? true, expectedLibrary.map({ $0 == context.library }) ?? true else { throw LearnerError.conflict }
        guard let si = next.understanding!.sessions.firstIndex(where: { $0.attempts.contains { $0.id == attemptID } }),
              let ai = next.understanding!.sessions[si].attempts.firstIndex(where: { $0.id == attemptID }) else { throw LearnerError.unavailable }
        var attempt = next.understanding!.sessions[si].attempts[ai]
        guard [.queued, .attention, .assessed].contains(attempt.status), providerIdentity == attempt.providerIdentity,
              currentUnderstandingSource(attempt, in: context.snapshot), json.utf8.count <= 100000,
              let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any], object["attempt_id"] as? String == attemptID else { throw LearnerError.conflict }
        let assessment = try LocalAnswerEvidence.validate(json, allowedIDs: Set(attempt.variant.evidence.map(\.id)))
        let errors = object["error_skill_ids"] as? [String] ?? []
        guard object["error_skill_ids"] == nil || object["error_skill_ids"] is [String], Set(errors).count == errors.count,
              Set(errors).isSubset(of: Set(attempt.variant.validation!.mapping.skillIDs)), errors.isEmpty || assessment.outcome == .incorrect else { throw LearnerError.invalidEvidence }
        if attempt.assessment == assessment && attempt.status == .assessed && (attempt.errorSkillIDs ?? []) == errors {
            try await reconcileUnderstanding(attempt, coordinator: coordinator, context: context); return
        }
        if let prior = attempt.assessment { attempt.assessmentRevisions.append(prior) }
        attempt.assessment = assessment; attempt.assessmentJSON = json; attempt.errorSkillIDs = errors; attempt.status = .assessed; attempt.error = nil
        next.understanding!.sessions[si].attempts[ai] = attempt
        // Persist accepted assessment first; replay recovers on restart if the evidence write fails.
        try await saveUnderstanding(next, coordinator: coordinator, context: context)
        try await reconcileUnderstanding(attempt, coordinator: coordinator, context: context)
    }
    public func retryUnderstandingAssessment(attemptID: String, providerIdentity: String, gradingModel: String? = nil, reason: String? = nil) async throws {
        let (coordinator, context, workspace) = try await understandingContext(); var next = workspace
        for si in next.understanding!.sessions.indices {
            if let ai = next.understanding!.sessions[si].attempts.firstIndex(where: { $0.id == attemptID }) {
                guard currentUnderstandingSource(next.understanding!.sessions[si].attempts[ai], in: context.snapshot), next.understanding!.sessions[si].attempts[ai].status != .presented else { throw LearnerError.conflict }
                next.understanding!.sessions[si].attempts[ai].providerIdentity = providerIdentity
                if let gradingModel, !gradingModel.isEmpty { next.understanding!.sessions[si].attempts[ai].gradingModel = gradingModel }
                next.understanding!.sessions[si].attempts[ai].correctionReason = reason.map { String($0.prefix(1500)) }
                next.understanding!.sessions[si].attempts[ai].status = .queued; next.understanding!.sessions[si].attempts[ai].error = nil
                try await saveUnderstanding(next, coordinator: coordinator, context: context)
                if let capture = next.captures.first(where: { $0.attemptID == attemptID }), workspace.recordingEnabled {
                    let state = try await coordinator.store.load(account: context.account, library: context.library)
                    if let prior = state.latest.first(where: { $0.attemptID == attemptID && $0.acceptance == .accepted }) {
                        try await coordinator.store.reconcile([capture.evidence(revision: prior.revision + 1, acceptance: .provisional, correct: nil, method: "assessment-disputed")], refreshAtBoundary: false, account: context.account, library: context.library)
                    }
                }
                return
            }
        }
        throw LearnerError.unavailable
    }
    public func failUnderstandingAssessment(attemptID: String, message: String, expectedAccount: UUID? = nil, expectedLibrary: String? = nil) async throws {
        let (coordinator, context, workspace) = try await understandingContext(); var next = workspace
        guard expectedAccount.map({ $0 == context.account }) ?? true, expectedLibrary.map({ $0 == context.library }) ?? true else { throw LearnerError.conflict }
        for si in next.understanding!.sessions.indices {
            if let ai = next.understanding!.sessions[si].attempts.firstIndex(where: { $0.id == attemptID && $0.status == .queued }) {
                next.understanding!.sessions[si].attempts[ai].status = .attention
                next.understanding!.sessions[si].attempts[ai].error = String(message.prefix(1000))
                try await saveUnderstanding(next, coordinator: coordinator, context: context); return
            }
        }
    }
    private func saveUnderstanding(_ workspace: LearnerWorkspace, coordinator: LearnerStudyCoordinator, context: LearnerStudyCoordinator.Context) async throws {
        try await coordinator.save(workspace, context: context)
    }
    private func currentUnderstandingSource(_ attempt: UnderstandingAttempt, in library: LibrarySnapshot) -> Bool {
        guard let note = library.liveNotes.first(where: { $0.id == attempt.noteID }), note.front == attempt.sourceOriginalFront, note.back == attempt.sourceOriginalBack else { return false }
        return note.questionFamily?.available(in: library, note: note).contains(attempt.variant) == true
    }
    private func nextUnderstandingAttempt(session: UnderstandingSession, context: LearnerStudyCoordinator.Context, workspace: LearnerWorkspace, providerIdentity: String, gradingModel: String, now: Date) async throws -> UnderstandingAttempt? {
        guard session.attempts.count < 10 else { return nil }
        let prior = workspace.understanding!.sessions.flatMap(\.attempts)
        let state = try await learnerCoordinator!.store.load(account: context.account, library: context.library)
        var candidates: [(Note, QuestionVariant, Int, Double?, Double?)] = []
        for note in context.snapshot.liveNotes where note.deckID == session.deckID {
            let available = note.questionFamily?.available(in: context.snapshot, note: note) ?? []
            for variant in available.prefix(session.settings.variantCount) {
                guard let validation = variant.validation, validation.supports(variant, questionID: note.id + ":variant:" + variant.id),
                      !session.attempts.contains(where: { $0.noteID == note.id && $0.variant.id == variant.id }) else { continue }
                let prediction = workspace.recordingEnabled ? try? await learnerPrediction(model: state.configuration.skill, questionID: validation.mapping.questionID, questionVersion: validation.mapping.questionVersion, mapping: validation.mapping, now: now) : nil
                let difficulty = workspace.recordingEnabled && state.configuration.modes[.difficulty] == .active
                    ? try? await learnerPrediction(model: state.configuration.difficulty, questionID: validation.mapping.questionID, questionVersion: validation.mapping.questionVersion, mapping: validation.mapping, now: now) : nil
                if validation.harder && !(session.settings.harderProgression && state.configuration.modes[.skill] == .active && (prediction?.probabilityCorrect ?? 0) >= 0.8) { continue }
                let count = prior.filter { $0.noteID == note.id && $0.variant.id == variant.id && $0.status != .abandoned }.count
                candidates.append((note, variant, count, state.configuration.modes[.skill] == .active ? prediction?.probabilityCorrect : nil, difficulty?.probabilityCorrect))
            }
        }
        // Rotation is deterministic; uncertainty/unavailable models retain that safe fallback.
        let scored = !candidates.isEmpty && candidates.allSatisfy { $0.3 != nil }
        let difficultyScored = !candidates.isEmpty && candidates.allSatisfy { $0.4 != nil }
        candidates.sort { a, b in
            if a.2 != b.2 { return a.2 < b.2 }
            if scored, abs(a.3! - 0.75) != abs(b.3! - 0.75) { return abs(a.3! - 0.75) < abs(b.3! - 0.75) }
            if difficultyScored, abs(a.4! - 0.75) != abs(b.4! - 0.75) { return abs(a.4! - 0.75) < abs(b.4! - 0.75) }
            return a.0.id == b.0.id ? a.1.id < b.1.id : a.0.id < b.0.id
        }
        guard let first = candidates.first else { return nil }
        return UnderstandingAttempt(note: first.0, variant: first.1, now: now, providerIdentity: providerIdentity, gradingModel: gradingModel, recordingEnabled: workspace.recordingEnabled, configuration: state.configuration)
    }
    private func reconcileUnderstanding(_ attempt: UnderstandingAttempt, coordinator: LearnerStudyCoordinator, context: LearnerStudyCoordinator.Context) async throws {
        let workspace = try await coordinator.store.workspace(account: context.account, library: context.library)
        guard workspace.recordingEnabled, attempt.recordingEnabled, let assessment = attempt.assessment, let validation = attempt.variant.validation else { return }
        var next = workspace
        if !next.captures.contains(where: { $0.attemptID == attempt.id }) {
            let session = next.understanding!.sessions.first { $0.attempts.contains { $0.id == attempt.id } }!
            next.questions.append(ReviewedLearnerQuestion(mapping: validation.mapping, prompt: attempt.variant.front, expectedAnswer: attempt.variant.back, kind: .generatedApplication))
            // Deduplicate reviewed rows while keeping previous content/mapping revisions.
            next.questions = next.questions.enumerated().filter { index, question in !next.questions.prefix(index).contains(question) }.map(\.element)
            next.captures.append(LearnerCapture(attemptID: attempt.id, presentationID: attempt.id, sessionID: session.id, capturedCardVersion: 0,
                questionID: validation.mapping.questionID, questionVersion: validation.mapping.questionVersion, kind: .generatedApplication, mapping: validation.mapping,
                startedAt: attempt.presentedAt, assisted: attempt.assisted, studySeconds: attempt.activeSeconds, unfamiliar: attempt.exposed ? false : nil,
                sourceEvidence: attempt.variant.evidence, questionPrompt: attempt.variant.front, questionExpectedAnswer: attempt.variant.back,
                configuration: attempt.configuration, policyRevision: "understanding-rotation-v1"))
            try await coordinator.save(next, context: context)
        }
        let state = try await coordinator.store.load(account: context.account, library: context.library)
        let prior = state.latest.first { $0.attemptID == attempt.id }
        let correct: Bool? = assessment.outcome == .correct ? true : assessment.outcome == .incorrect ? false : nil
        let capture = next.captures.first { $0.attemptID == attempt.id }!
        let errors = (attempt.errorSkillIDs ?? []).filter { capture.mapping?.skillIDs.contains($0) == true }
        if prior?.correct == correct && prior?.acceptance == .accepted && prior?.gradingMethod == assessment.method && prior?.errorSkillIDs == errors { return }
        let event = capture.evidence(revision: (prior?.revision ?? 0) + 1, acceptance: .accepted, correct: correct, method: assessment.method, errorSkillIDs: errors)
        try await coordinator.check(context)
        let boundary = !coordinator.isAttemptInProgress(workspace: next, state: state, snapshot: context.snapshot)
        try await coordinator.store.reconcile([event], refreshAtBoundary: boundary, account: context.account, library: context.library)
    }
}
