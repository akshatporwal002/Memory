import Foundation
import LearningCore

extension StudyService {
    public func setLearnerPractice(fixed: Bool, provisionalFeedback: Bool) async throws {
        guard let coordinator = learnerCoordinator else { throw LearnerError.unavailable }
        let context = try await coordinator.context()
        let workspace = try await coordinator.store.workspace(account: context.account, library: context.library)
        let state = try await coordinator.store.load(account: context.account, library: context.library)
        guard !coordinator.isAttemptInProgress(workspace: workspace, state: state, snapshot: context.snapshot) else { throw LearnerError.conflict }
        try await coordinator.check(context)
        try await coordinator.store.setPracticePreferences(fixed: fixed, provisionalFeedback: provisionalFeedback,
            account: context.account, library: context.library)
    }
    /// Independent application attempt. It neither creates nor updates an FSRS review.
    /// Generated content must already have been source-grounded and reviewed by its existing workflow.
    public func beginLearnerApplication(question: ReviewedLearnerQuestion, attemptID: String = UUID().uuidString,
                                        sessionID: String, sourceEvidence: [AttemptEvidence], assisted: Bool? = nil,
                                        unfamiliar: Bool? = nil, assessmentID: String? = nil, assessmentSessionID: String? = nil,
                                        now: Date = Date()) async throws -> String {
        guard let coordinator = learnerCoordinator else { throw LearnerError.unavailable }
        let context = try await coordinator.context()
        var workspace = try await coordinator.store.workspace(account: context.account, library: context.library)
        let state = try await coordinator.store.load(account: context.account, library: context.library)
        try question.validate()
        guard workspace.recordingEnabled, question.kind != .recall,
              question.kind != .generatedApplication || !state.configuration.fixedPractice,
              workspace.questions.contains(question), !sourceEvidence.isEmpty,
              sourceEvidence.allSatisfy({ EvidenceRetrieval.isCurrent($0, in: context.snapshot) }),
              !coordinator.isAttemptInProgress(workspace: workspace, state: state, snapshot: context.snapshot) else { throw LearnerError.unavailable }
        guard !workspace.captures.contains(where: { $0.attemptID == attemptID }) else { throw LearnerError.conflict }
        let capture = LearnerCapture(attemptID: attemptID, presentationID: attemptID, sessionID: sessionID, capturedCardVersion: 0,
            questionID: question.mapping.questionID, questionVersion: question.mapping.questionVersion, kind: question.kind,
            mapping: question.mapping, startedAt: now, assisted: assisted, unfamiliar: unfamiliar,
            assessmentID: assessmentID, assessmentSessionID: assessmentSessionID, sourceEvidence: sourceEvidence,
            questionPrompt: question.prompt, questionExpectedAnswer: question.expectedAnswer, configuration: state.configuration)
        try capture.validate(); workspace.captures.append(capture); try await coordinator.save(workspace, context: context)
        return attemptID
    }
    /// Uses the existing source-evidence acceptance boundary and binds output to this attempt.
    /// A deeper/corrected assessment updates this same capture, never a second logical attempt.
    public func acceptLearnerApplicationAssessment(attemptID: String, assessmentJSON: String, confirmedErrorSkillIDs suppliedErrors: [String]? = nil) async throws {
        guard let coordinator = learnerCoordinator else { throw LearnerError.unavailable }
        let context = try await coordinator.context()
        var workspace = try await coordinator.store.workspace(account: context.account, library: context.library)
        let state = try await coordinator.store.load(account: context.account, library: context.library)
        guard workspace.recordingEnabled, let capture = workspace.captures.first(where: { $0.attemptID == attemptID && $0.kind != .recall }),
              capture.abandonedAt == nil, capture.sourceEvidence.allSatisfy({ EvidenceRetrieval.isCurrent($0, in: context.snapshot) }),
              assessmentJSON.utf8.count <= 100000, let bytes = assessmentJSON.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], object["attempt_id"] as? String == attemptID else { throw LearnerError.invalidEvidence }
        let assessment = try LocalAnswerEvidence.validate(assessmentJSON, allowedIDs: Set(capture.sourceEvidence.map(\.id)))
        let correct: Bool? = assessment.outcome == .correct ? true : assessment.outcome == .incorrect ? false : nil
        let prior = state.latest.first { $0.attemptID == attemptID }
        let confirmedErrorSkillIDs = suppliedErrors ?? (correct == false ? capture.confirmedErrorSkillIDs ?? prior?.errorSkillIDs ?? [] : [])
        guard confirmedErrorSkillIDs.isEmpty || correct == false else { throw LearnerError.invalidEvidence }
        if prior?.acceptance == .accepted && prior?.correct == correct && prior?.gradingMethod == assessment.method && prior?.errorSkillIDs == confirmedErrorSkillIDs { return }
        let event = capture.evidence(revision: (prior?.revision ?? 0) + 1, acceptance: .accepted, correct: correct, method: assessment.method, errorSkillIDs: confirmedErrorSkillIDs)
        try event.validate()
        let index = workspace.captures.firstIndex { $0.attemptID == attemptID }!
        workspace.captures[index].confirmedErrorSkillIDs = confirmedErrorSkillIDs
        try await coordinator.save(workspace, context: context)
        try await coordinator.check(context)
        try await coordinator.store.reconcile([event], refreshAtBoundary: true, account: context.account, library: context.library)
    }
    public func abandonLearnerApplication(attemptID: String, now: Date = Date()) async throws {
        guard let coordinator = learnerCoordinator else { throw LearnerError.unavailable }
        let context = try await coordinator.context()
        var workspace = try await coordinator.store.workspace(account: context.account, library: context.library)
        let state = try await coordinator.store.load(account: context.account, library: context.library)
        guard let index = workspace.captures.firstIndex(where: { $0.attemptID == attemptID && $0.kind != .recall }),
              state.latest.first(where: { $0.attemptID == attemptID })?.acceptance != .accepted else { throw LearnerError.conflict }
        workspace.captures[index].abandonedAt = now; try await coordinator.save(workspace, context: context)
        let revision = (state.latest.first { $0.attemptID == attemptID }?.revision ?? 0) + 1
        try await coordinator.store.reconcile([workspace.captures[index].evidence(revision: revision, acceptance: .retracted, correct: nil, method: "abandoned")],
            refreshAtBoundary: true, account: context.account, library: context.library)
    }
    /// Active skill predictions can order application candidates. Observe/Off, unknown items,
    /// inference errors and fixed practice preserve the supplied order. FSRS is never involved.
    /// Target probability is an explicit practice-policy heuristic, not a fitted coefficient.
    public func orderLearnerApplicationQuestions(_ questions: [ReviewedLearnerQuestion], targetProbability: Double = 0.75,
                                                now: Date = Date()) async throws -> [ReviewedLearnerQuestion] {
        guard targetProbability.isFinite, (0...1).contains(targetProbability) else { throw LearnerError.invalidEvidence }
        let status = try await learnerStatus()
        guard !status.state.configuration.fixedPractice, status.state.configuration.modes[.skill] == .active else { return questions }
        var scored: [(Int, Double)] = []
        for (index, question) in questions.enumerated() {
            guard question.kind != .recall else { return questions }
            let prediction = try? await learnerPrediction(model: status.state.configuration.skill, questionID: question.mapping.questionID,
                questionVersion: question.mapping.questionVersion, mapping: question.mapping, now: now)
            guard let probability = prediction?.probabilityCorrect else { return questions }
            scored.append((index, abs(probability - targetProbability)))
        }
        return scored.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }.map { questions[$0.0] }
    }
}
