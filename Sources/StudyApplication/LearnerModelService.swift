import Foundation
import LearningCore

public struct LearnerStudyStatus: Sendable {
    public let recordingEnabled: Bool
    public let state: LearnerState
    public let dashboard: LearnerDashboard
    public let models: [LearnerModelDescription]
    public let calibrationReports: [LearnerCalibrationReport]
    public let reconciliationError: String?
}

extension StudyService {
    public func reviewedLearnerQuestions() async throws -> [ReviewedLearnerQuestion] {
        let coordinator = try learner(), context = try await coordinator.context()
        let workspace = try await coordinator.store.workspace(account: context.account, library: context.library)
        try await coordinator.check(context); return workspace.questions
    }
    private func learner() throws -> LearnerStudyCoordinator {
        guard let learnerCoordinator else { throw LearnerError.unavailable }; return learnerCoordinator
    }
    public func setLearnerRecordingEnabled(_ enabled: Bool) async throws { try await learner().setRecording(enabled) }
    public func reviewLearnerQuestion(_ question: ReviewedLearnerQuestion, expectedAccount: UUID? = nil, expectedLibrary: String? = nil) async throws { try await learner().reviewQuestion(question, expectedAccount: expectedAccount, expectedLibrary: expectedLibrary) }
    public func beginLearnerRecall(presentationID: String, assisted: Bool? = nil, now: Date = Date(),
                                   delaySeconds: Double? = nil, assessmentID: String? = nil, assessmentSessionID: String? = nil) async throws -> String {
        try await learner().beginRecall(presentationID: presentationID, assisted: assisted, now: now,
            delaySeconds: delaySeconds, assessmentID: assessmentID, assessmentSessionID: assessmentSessionID)
    }
    /// The UI supplies measured active duration; no elapsed wall-clock estimate is inferred here.
    public func recordLearnerMeasurements(attemptID: String, activeSeconds: Double? = nil, assisted: Bool? = nil) async throws {
        try await learner().measure(attemptID: attemptID, seconds: activeSeconds, assisted: assisted)
    }
    /// Provisional feedback may be displayed by an existing authorized local engine.
    /// It never supplies correctness, scheduling or calibrated training labels.
    public func recordProvisionalLearnerFeedback(attemptID: String, method: String = "laya-provisional") async throws {
        try await learner().provisional(attemptID: attemptID, method: method)
    }
    public func switchLearnerModel(to model: LearnerModelID, mode: LearnerMode) async throws {
        try await learner().switchModel(to: model, mode: mode)
    }
    public func learnerStatus() async throws -> LearnerStudyStatus {
        let coordinator = try learner(), context = try await coordinator.context()
        try await coordinator.synchronize(context)
        let state = try await coordinator.store.load(account: context.account, library: context.library)
        let workspace = try await coordinator.store.workspace(account: context.account, library: context.library)
        let predictors = try LearnerModelID.allCases.compactMap { model in try workspace.candidate(for: model, state: state)?.predictor() }
        try await coordinator.check(context)
        return LearnerStudyStatus(recordingEnabled: workspace.recordingEnabled, state: state, dashboard: LearnerDashboard(state: state),
            models: LearnerModelDescription.catalog(predictors: predictors, history: state.latest), calibrationReports: workspace.candidates.map(\.report), reconciliationError: await coordinator.lastError)
    }
    /// Local fitting only. A chronological cut avoids training on future answers.
    /// DINA needs held-out learners from an explicitly permitted dataset, not one personal sequence.
    public func fitPersonalLearnerModel(_ model: LearnerModelID, options: LearnerFitOptions = LearnerFitOptions()) async throws -> LearnerCalibrationReport {
        try options.validate()
        let coordinator = try learner(), context = try await coordinator.context()
        try await coordinator.synchronize(context)
        let state = try await coordinator.store.load(account: context.account, library: context.library)
        guard model != .dina else { throw LearnerError.unavailable }
        let eligible = state.latest.filter { row in
            row.acceptance == .accepted && row.correct != nil && row.assisted == false && row.mapping != nil
                && (model != .bkt || row.mapping!.skillIDs.count == 1)
        }
        // A fitter consumes one coherent reviewed Q revision. Historical mappings are never rewritten.
        guard let mappingRevision = eligible.last?.mapping?.revision else { throw LearnerError.unavailable }
        let rows = eligible.filter { $0.mapping?.revision == mappingRevision }
        guard rows.count >= options.minimumTraining + options.minimumValidation else { throw LearnerError.unavailable }
        let count = max(options.minimumTraining, rows.count - max(options.minimumValidation, rows.count / 5))
        let cutoff = rows[count].occurredAt
        let target = context.account.uuidString.lowercased()
        let training = rows.filter { $0.occurredAt < cutoff }.map { LearnerTrainingRow(learnerID: target, evidence: $0) }
        let validation = rows.filter { $0.occurredAt >= cutoff }.map { LearnerTrainingRow(learnerID: target, evidence: $0) }
        return try await fitPermittedLearnerDataset(model, training: training, validation: validation, options: options)
    }
    /// Callers must supply data they are permitted to use. This method performs no uploads,
    /// community queries, external downloads or implicit fitting on another account/library.
    public func fitPermittedLearnerDataset(_ model: LearnerModelID, training: [LearnerTrainingRow], validation: [LearnerTrainingRow],
                                          options: LearnerFitOptions = LearnerFitOptions()) async throws -> LearnerCalibrationReport {
        let coordinator = try learner(), context = try await coordinator.context()
        try await coordinator.synchronize(context)
        let state = try await coordinator.store.load(account: context.account, library: context.library)
        let workspace = try await coordinator.store.workspace(account: context.account, library: context.library)
        guard workspace.recordingEnabled else { throw LearnerError.unavailable }
        let candidate = try await Task.detached {
            try LearnerCalibration.fit(model: model, training: training, validation: validation,
                targetLearner: context.account.uuidString.lowercased(), account: context.account, library: context.library,
                evidenceRevision: state.revision, options: options)
        }.value
        try await coordinator.check(context)
        let current = try await coordinator.store.load(account: context.account, library: context.library)
        guard current.revision == state.revision else { throw LearnerError.conflict }
        var updated = try await coordinator.store.workspace(account: context.account, library: context.library)
        updated.candidates.append(candidate); try await coordinator.save(updated, context: context)
        return candidate.report
    }
    public func reviewLearnerCalibration(artifactID: String, reviewedBy: String, now: Date = Date(), expectedAccount: UUID? = nil, expectedLibrary: String? = nil) async throws {
        let coordinator = try learner(), context = try await coordinator.context()
        guard expectedAccount.map({ $0 == context.account }) ?? true, expectedLibrary.map({ $0 == context.library }) ?? true else { throw LearnerError.conflict }
        var workspace = try await coordinator.store.workspace(account: context.account, library: context.library)
        let state = try await coordinator.store.load(account: context.account, library: context.library)
        guard !reviewedBy.isEmpty, let candidate = workspace.candidates.first(where: { $0.report.id == artifactID }),
              candidate.report.eligibleForReview, candidate.sourceRevisions.allSatisfy({ key, revision in state.latest.contains { $0.attemptID == key && $0.revision == revision } }) else { throw LearnerError.unavailable }
        if workspace.artifactReviews.contains(where: { $0.artifactID == artifactID }) { return }
        workspace.artifactReviews.append(.init(artifactID: artifactID, reviewedBy: reviewedBy, reviewedAt: now))
        try await coordinator.save(workspace, context: context)
    }
    /// Explicit local import of a fitting candidate. Reports are declarations until reviewed;
    /// importing never switches a model or grants permission for cloud/research processing.
    public func importLearnerCalibrationCandidate(_ data: Data) async throws -> LearnerCalibrationReport {
        guard data.count <= 20000000 else { throw LearnerError.invalidEvidence }
        let candidate = try JSONDecoder().decode(LearnerCalibrationCandidate.self, from: data)
        _ = try candidate.predictor()
        let coordinator = try learner(), context = try await coordinator.context()
        let state = try await coordinator.store.load(account: context.account, library: context.library)
        guard candidate.account == context.account, candidate.library == context.library.lowercased(),
              candidate.learnerID == context.account.uuidString.lowercased(), candidate.evidenceRevision <= state.revision,
              candidate.sourceRevisions.allSatisfy({ key, revision in state.latest.contains { $0.attemptID == key && $0.revision == revision } }) else { throw LearnerError.conflict }
        var workspace = try await coordinator.store.workspace(account: context.account, library: context.library)
        if workspace.candidates.contains(where: { $0.report.id == candidate.report.id }) { throw LearnerError.conflict }
        workspace.candidates.append(candidate); try await coordinator.save(workspace, context: context)
        return candidate.report
    }
    public func learnerPrediction(model: LearnerModelID, questionID: String, questionVersion: Int,
                                  mapping: ReviewedSkillMapping? = nil, assessmentID: String? = nil, assessmentSessionID: String? = nil,
                                  now: Date = Date()) async throws -> LearnerPrediction? {
        let coordinator = try learner(), context = try await coordinator.context()
        try await coordinator.synchronize(context)
        let state = try await coordinator.store.load(account: context.account, library: context.library)
        let workspace = try await coordinator.store.workspace(account: context.account, library: context.library)
        let mode = state.configuration.modes[model.purpose] ?? .off
        guard workspace.recordingEnabled, mode != .off, let id = state.current[model.purpose],
              let snapshot = state.snapshots.first(where: { $0.id == id && $0.model == model && $0.evidenceRevision == state.revision }),
              let candidate = workspace.candidate(for: model, state: state), candidate.report.id == snapshot.artifactRevision else { return nil }
        let adapter = try candidate.predictor()
        guard adapter.selectHistory(state.latest.filter(adapter.compatible)).allSatisfy({ $0.occurredAt <= now }) else { return nil }
        var probability: Double?, skillProbabilities: [String: Double]?, mean: Double?, lower: Double?, upper: Double?
        let decoder = JSONDecoder()
        switch model {
        case .bkt:
            guard let mapping, mapping.questionID == questionID, mapping.questionVersion == questionVersion else { return nil }
            let predictor = BKTLearnerPredictor(artifact: try decoder.decode(BKTLearnerPredictor.Artifact.self, from: candidate.parameters))
            probability = try predictor.probability(mapping: mapping, history: snapshot.payload)
            skillProbabilities = try predictor.mastery(mapping: mapping, history: snapshot.payload)
        case .das3h:
            guard let mapping, mapping.questionID == questionID, mapping.questionVersion == questionVersion else { return nil }
            probability = try DAS3HLearnerPredictor(artifact: decoder.decode(DAS3HLearnerPredictor.Artifact.self, from: candidate.parameters)).probability(mapping: mapping, at: now, history: snapshot.payload)
        case .dynamicRasch:
            let predictor = DynamicRaschLearnerPredictor(artifact: try decoder.decode(DynamicRaschLearnerPredictor.Artifact.self, from: candidate.parameters))
            probability = try predictor.probability(questionID: questionID, questionVersion: questionVersion, at: now, history: snapshot.payload)
            let ability = try predictor.ability(at: now, history: snapshot.payload); mean = ability.mean; lower = ability.lower; upper = ability.upper
        case .dina:
            guard let mapping, mapping.questionID == questionID, mapping.questionVersion == questionVersion else { return nil }
            let predictor = DINALearnerPredictor(artifact: try decoder.decode(DINALearnerPredictor.Artifact.self, from: candidate.parameters))
            guard let administration = assessmentSessionID, let form = assessmentID,
                  predictor.selectHistory(state.latest.filter(predictor.compatible)).allSatisfy({ $0.assessmentSessionID == administration && $0.assessmentID == form }) else { return nil }
            probability = try predictor.probability(mapping: mapping, history: snapshot.payload)
            skillProbabilities = try predictor.skillProbabilities(history: snapshot.payload)
        }
        try await coordinator.check(context)
        return LearnerPrediction(model: model, artifactRevision: snapshot.artifactRevision, probabilityCorrect: probability,
            skillProbabilities: skillProbabilities, abilityMean: mean, abilityLower: lower, abilityUpper: upper,
            evidenceRevision: state.revision, mode: mode, compatibleAttempts: snapshot.compatibleAttempts)
    }
}
