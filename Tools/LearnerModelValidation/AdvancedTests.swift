import Foundation

enum LearnerAdvancedValidation {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "AdvancedLearnerValidation", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func rejects(_ operation: () throws -> Void) throws {
        do { try operation() } catch is LearnerError { return }
        throw NSError(domain: "AdvancedLearnerValidation", code: 2)
    }
    static func rejectsAsync(_ operation: () async throws -> Void) async throws {
        do { try await operation() } catch is LearnerError { return }
        throw NSError(domain: "AdvancedLearnerValidation", code: 3)
    }
    static let date = Date(timeIntervalSince1970: 1800000000)
    static func mapping(_ question: String, skills: [String] = ["s"]) throws -> ReviewedSkillMapping {
        try ReviewedSkillMapping(questionID: question, questionVersion: 1, revision: "reviewed-test", skillIDs: skills, reviewedBy: "synthetic fixture")
    }
    static func row(_ id: String, question: String = "q", correct: Bool, time: Date, mapping: ReviewedSkillMapping? = nil,
                    assessment: String? = nil, session: String? = nil) -> LearnerEvidence {
        .init(attemptID: id, revision: 1, questionID: question, questionVersion: 1, occurredAt: time,
            kind: .fixedApplication, mapping: mapping, assisted: false, acceptance: .accepted, correct: correct,
            gradingMethod: "synthetic fixture", assessmentID: assessment, assessmentSessionID: session)
    }
    static func run() async throws {
        try await questionFamilies()
        try await understandingPractice()
        try inference()
        let account = UUID()
        let candidate = try fitting(account: account)
        try await integration(account: account, candidate: candidate)
        try await recovery()
    }
    static func inference() throws {
        let grid = [-2.0, -1, 0, 1, 2], prior = [0.05, 0.2, 0.5, 0.2, 0.05]
        let artifact = DynamicRaschLearnerPredictor.Artifact(revision: "synthetic-rasch", trainingReport: "synthetic only",
            heldOutValidationReport: "synthetic only", scaleAnchor: "test anchor", grid: grid, prior: prior, variancePerDay: 0.2,
            items: [.init(questionID: "q", questionVersion: 1, difficulty: 0)])
        let rasch = DynamicRaschLearnerPredictor(artifact: artifact)
        let empty = try JSONEncoder().encode(rasch.startingPosterior(at: date))
        try require(abs(try rasch.probability(questionID: "q", questionVersion: 1, at: date, history: empty) - 0.5) < 1e-10, "Rasch symmetric prior")
        let payload = try rasch.replay([row("r", correct: true, time: date)])
        let ability = try rasch.ability(at: date, history: payload)
        try require(ability.mean > 0 && ability.lower <= ability.mean && ability.upper >= ability.mean, "Rasch ability/uncertainty")
        try require(try rasch.probability(questionID: "q", questionVersion: 1, at: date, history: payload) > 0.5, "Rasch response update")
        try rejects { _ = try rasch.posterior(at: date.addingTimeInterval(-1), history: payload) }
        try rejects { _ = try rasch.probability(questionID: "unknown", questionVersion: 1, at: date, history: payload) }
        let future = try rasch.posterior(at: date.addingTimeInterval(86400), history: payload)
        try require(abs(future.probabilities.reduce(0, +) - 1) < 1e-10, "Rasch diffusion normalization")
        let mappings = try (0..<6).map { try mapping("d\($0)", skills: [$0 < 3 ? "a" : "b"]) }
        let dina = DINALearnerPredictor(artifact: .init(revision: "synthetic-dina", assessmentID: "form", trainingReport: "synthetic only",
            heldOutValidationReport: "synthetic only", skillIDs: ["a", "b"], profilePrior: [0.25, 0.25, 0.25, 0.25],
            items: mappings.map { .init(mapping: $0, slip: 0.1, guess: 0.1) }))
        try require(dina.readiness == nil, "Identifiable DINA form")
        let first = row("d1", question: "d0", correct: true, time: date, mapping: mappings[0], assessment: "form", session: "one")
        let posterior = try dina.replay([first]), probabilities = try dina.skillProbabilities(history: posterior)
        try require(abs(probabilities["a"]! - 0.9) < 1e-10 && abs(probabilities["b"]! - 0.5) < 1e-10, "DINA profile posterior")
        let second = row("d2", question: "d0", correct: false, time: date.addingTimeInterval(1), mapping: mappings[0], assessment: "form", session: "two")
        try rejects { _ = try dina.replay([first, second]) }
        var state = LearnerState(); try state.append(first); try state.append(second)
        let snapshot = try state.prepare(using: dina)
        try require(snapshot.compatibleAttempts == 1 && dina.selectHistory(state.latest) == [second], "DINA never pools administrations")
        try require(!DINALearnerPredictor.identifiable(skillIDs: ["a", "b"], mappings: [try mapping("bad", skills: ["a", "b"])]), "Unidentifiable Q rejected")
        print("PASS: dynamic Rasch filtering/uncertainty and DINA assessment-scoped diagnosis")
    }
    static func fitting(account: UUID) throws -> LearnerCalibrationCandidate {
        var options = LearnerFitOptions(); options.minimumTraining = 10; options.minimumValidation = 4
        options.iterations = 250; options.tolerance = 0.005; options.maximumCalibrationError = 1
        let q = try mapping("q"), target = account.uuidString.lowercased()
        var training: [LearnerTrainingRow] = [], validation: [LearnerTrainingRow] = []
        for learner in 0..<3 {
            let identity = learner == 0 ? target : "test-learner-\(learner)"
            for attempt in 0..<20 {
                let correct = attempt >= 5 ? attempt % 5 != 0 : attempt % 3 == 0
                let event = row("bkt-\(learner)-\(attempt)", correct: correct, time: date.addingTimeInterval(Double(attempt) * 86400), mapping: q)
                let record = LearnerTrainingRow(learnerID: identity, evidence: event)
                if attempt < 14 { training.append(record) } else { validation.append(record) }
            }
        }
        let bkt = try LearnerCalibration.fit(model: .bkt, training: training, validation: validation,
            targetLearner: target, account: account, library: "default", evidenceRevision: 20, options: options)
        try require(bkt.report.trainingAttempts == 42 && bkt.report.validationAttempts == 18 && bkt.report.brier.isFinite, "BKT fitted/evaluated report")
        _ = try bkt.predictor()
        try rejects {
            _ = try LearnerCalibration.fit(model: .bkt, training: Array(training.prefix(3)), validation: validation,
                targetLearner: target, account: account, library: "default", evidenceRevision: 1, options: options)
        }
        try rejects {
            _ = try LearnerCalibration.fit(model: .bkt, training: training, validation: training,
                targetLearner: target, account: account, library: "default", evidenceRevision: 1, options: options)
        }
        let original = training[0]
        let duplicatedRevision = LearnerEvidence(attemptID: original.evidence.attemptID, revision: 2, questionID: "q", questionVersion: 1,
            occurredAt: date.addingTimeInterval(30 * 86400), kind: .fixedApplication, mapping: q, assisted: false,
            acceptance: .accepted, correct: false, gradingMethod: "corrected synthetic fixture")
        try rejects {
            _ = try LearnerCalibration.fit(model: .bkt, training: training, validation: validation + [.init(learnerID: original.learnerID, evidence: duplicatedRevision)],
                targetLearner: target, account: account, library: "default", evidenceRevision: 20, options: options)
        }
        let das = try LearnerCalibration.fit(model: .das3h, training: training.filter { $0.learnerID == target }, validation: validation.filter { $0.learnerID == target },
            targetLearner: target, account: account, library: "default", evidenceRevision: 20, options: options)
        _ = try das.predictor(); try require(das.report.validationAttempts == 6, "DAS3H local ridge fit and chronological evaluation")
        var raschTraining: [LearnerTrainingRow] = [], raschValidation: [LearnerTrainingRow] = []
        for learner in 0..<2 {
            for attempt in 0..<12 {
                let question = "r\(attempt % 2)", event = row("rasch-\(learner)-\(attempt)", question: question,
                    correct: (attempt + learner) % 3 != 0, time: date.addingTimeInterval(Double(attempt) * 86400), mapping: try mapping(question))
                let record = LearnerTrainingRow(learnerID: learner == 0 ? target : "rasch-other", evidence: event)
                if attempt < 8 { raschTraining.append(record) } else { raschValidation.append(record) }
            }
        }
        var raschOptions = options; raschOptions.abilityGrid = [-2, -1, 0, 1, 2]; raschOptions.iterations = 70; raschOptions.tolerance = 0.02
        let rasch = try LearnerCalibration.fit(model: .dynamicRasch, training: raschTraining, validation: raschValidation,
            targetLearner: target, account: account, library: "default", evidenceRevision: 20, options: raschOptions)
        let raschArtifact = try JSONDecoder().decode(DynamicRaschLearnerPredictor.Artifact.self, from: rasch.parameters)
        try require(raschArtifact.items[0].difficulty == 0 && raschArtifact.variancePerDay >= 0, "Identified Rasch fit with estimated process variance/static alternative")
        var dinaTraining: [LearnerTrainingRow] = [], dinaValidation: [LearnerTrainingRow] = []
        for learner in 0..<16 {
            for item in 0..<6 {
                let skill = item < 3 ? "a" : "b", question = "d\(item)"
                var correct = learner % 4 & (skill == "a" ? 1 : 2) != 0
                if (learner * 7 + item) % 17 == 0 { correct.toggle() }
                let event = row("dina-\(learner)-\(item)", question: question, correct: correct, time: date.addingTimeInterval(Double(item)),
                    mapping: try mapping(question, skills: [skill]), assessment: "form", session: "administration-\(learner)")
                let record = LearnerTrainingRow(learnerID: "dina-person-\(learner)", evidence: event)
                if learner < 12 { dinaTraining.append(record) } else { dinaValidation.append(record) }
            }
        }
        let dina = try LearnerCalibration.fit(model: .dina, training: dinaTraining, validation: dinaValidation,
            targetLearner: target, account: account, library: "default", evidenceRevision: 20, options: options)
        _ = try dina.predictor()
        try require(dina.report.trainingLearners == 12 && dina.report.validationLearners == 4, "DINA EM and held-out learner validation")
        print("PASS: BKT, DAS3H, Rasch and DINA fitting; held-out reports; leakage/insufficient-data rejection")
        print("Synthetic BKT eligibility: \(bkt.report.eligibleForReview), converged: \(bkt.report.converged), log loss: \(bkt.report.logLoss), baseline: \(bkt.report.baselineLogLoss)")
        return bkt
    }
    static func integration(account: UUID, candidate: LearnerCalibrationCandidate) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("learner-advanced-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LearnerModelRepository(directory: directory)
        let scheduler = FSRSScheduler(), settings = StudySettings(timeZoneID: "UTC")
        var library = LibrarySnapshot(); library.settings = settings
        library.decks = [Deck(id: "deck", name: "Offline")]
        let note = Note(id: "note", deckID: "deck", kind: .basic, front: "2 + 2?", back: "4")
        library.notes = [note]
        let initial = try scheduler.initialState(now: date, settings: settings)
        library.cards = [StudyCard(id: "card", noteID: "note", deckID: "deck", schedule: initial)]
        let base = MemoryRepository(initial: library)
        let service = StudyService(repository: base, scheduler: scheduler, learnerStore: store, learnerAccount: { account })
        let initialStatus = try await service.learnerStatus()
        try require(!initialStatus.recordingEnabled && initialStatus.state.evidence.isEmpty, "No implicit opt-in")
        try await service.setLearnerRecordingEnabled(true)
        try await service.setLearnerPractice(fixed: true, provisionalFeedback: true)
        let reviewed = ReviewedLearnerQuestion(mapping: try mapping("card"), prompt: note.front, expectedAnswer: note.back, kind: .recall)
        try await service.reviewLearnerQuestion(reviewed)
        let session = try await service.startSession(deckID: "deck", now: date), item = session.current!
        let id = try await service.beginLearnerRecall(presentationID: item.presentationID, assisted: false, now: date)
        try await rejectsAsync { try await service.switchLearnerModel(to: .bkt, mode: .observe) }
        try await service.recordProvisionalLearnerFeedback(attemptID: id)
        try await service.recordLearnerMeasurements(attemptID: id, activeSeconds: 12)
        let expected = try scheduler.outcomes(state: initial, history: [], now: date, settings: settings)[.good]!
        try await service.submitAnswer(sessionID: session.id, presentationID: item.presentationID,
            assessment: AnswerAssessment(outcome: .correct, reason: "Exact match", method: "local-exact"), now: date)
        let committed = try await base.read(), status = try await service.learnerStatus()
        try require(committed.cards[0].schedule == expected && committed.reviews.count == 1, "Actual FSRS unchanged by learner collection")
        try require(status.state.latest.count == 1 && status.state.latest[0].correct == true && status.state.latest[0].studySeconds == 12,
            "Automatic committed evidence; provisional/final stay one timed attempt")
        try await service.undo(sessionID: session.id, now: date.addingTimeInterval(1))
        let undone = try await service.learnerStatus()
        try require(undone.state.latest[0].acceptance == .retracted, "Study undo automatically retracts learner outcome")
        let reopened = StudyService(repository: base, scheduler: scheduler, learnerStore: LearnerModelRepository(directory: directory), learnerAccount: { account })
        let recovered = try await reopened.learnerStatus()
        try require(recovered.state.latest == undone.state.latest, "Restart replay is idempotent")
        try await reopened.endSession()
        let newLibrary = try await reopened.createLibrary(name: "Isolated", deviceOnly: true)
        try await reopened.selectLibrary(newLibrary.id)
        let isolated = try await reopened.learnerStatus()
        try require(isolated.state.evidence.isEmpty && !isolated.recordingEnabled, "Study-service library isolation")
        try await reopened.selectLibrary("default")
        let source = try await reopened.snapshot()
        let passages = LocalAnswerEvidence.retrieve(note: note, prompt: note.front, library: source).map { AttemptEvidence(id: $0.id, text: $0.text, version: $0.version) }
        try require(!passages.isEmpty, "Real source-evidence retrieval")
        let application = ReviewedLearnerQuestion(mapping: try mapping("generated"), prompt: "Apply addition", expectedAnswer: "4", kind: .generatedApplication)
        try await reopened.reviewLearnerQuestion(application)
        try await reopened.setLearnerPractice(fixed: false, provisionalFeedback: true)
        let applicationID = try await reopened.beginLearnerApplication(question: application, sessionID: "application-session", sourceEvidence: passages, assisted: false, unfamiliar: true, now: date)
        try await reopened.recordProvisionalLearnerFeedback(attemptID: applicationID)
        try await reopened.recordLearnerMeasurements(attemptID: applicationID, activeSeconds: 9)
        let beforeApplication = try await base.read()
        func json(correct: Bool, attempt: String = applicationID) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: ["attempt_id": attempt, "outcome": correct ? "correct" : "incorrect",
                "reason": "Supported", "evidence_ids": [passages[0].id]]), as: UTF8.self)
        }
        try await rejectsAsync { try await reopened.acceptLearnerApplicationAssessment(attemptID: applicationID, assessmentJSON: json(correct: true, attempt: "wrong")) }
        try await reopened.acceptLearnerApplicationAssessment(attemptID: applicationID, assessmentJSON: json(correct: true))
        try await reopened.acceptLearnerApplicationAssessment(attemptID: applicationID, assessmentJSON: json(correct: true))
        try await reopened.acceptLearnerApplicationAssessment(attemptID: applicationID, assessmentJSON: json(correct: false))
        try await reopened.confirmLearnerSkillErrors(attemptID: applicationID, skillIDs: ["s"])
        let labelled = try await reopened.learnerStatus()
        try require(labelled.dashboard.skillErrors["s"] == 1, "Explicit skill-error evidence")
        let correctedMapping = try ReviewedSkillMapping(questionID: "generated", questionVersion: 1, revision: "corrected-matrix",
            skillIDs: ["s2"], reviewedBy: "synthetic mapping reviewer")
        let correctedQuestion = ReviewedLearnerQuestion(mapping: correctedMapping, prompt: application.prompt, expectedAnswer: application.expectedAnswer, kind: .generatedApplication)
        try await reopened.reviewLearnerQuestion(correctedQuestion)
        try await reopened.correctLearnerMapping(attemptID: applicationID, reviewedQuestion: correctedQuestion)
        let graph = try await reopened.learnerQMatrix(revision: "corrected-matrix")
        let remapped = try await reopened.learnerStatus()
        try require(graph.edges.count == 1 && graph.skillIDs == ["s2"] && remapped.state.latest.first(where: { $0.attemptID == applicationID })?.mapping == correctedMapping,
            "Reviewed Q graph and correction independent of content version")
        let afterApplication = try await base.read(), applicationStatus = try await reopened.learnerStatus()
        try require(beforeApplication.cards == afterApplication.cards && beforeApplication.reviews == afterApplication.reviews, "Generated application never resets FSRS")
        try require(applicationStatus.dashboard.unfamiliarQuestions.attempts == 1 && applicationStatus.dashboard.unfamiliarQuestions.correct == 0,
            "Corrected generated assessment updates one observed outcome")
        // Replay/activation of actual synthetically fitted parameters, confined to this temporary account.
        let target = account.uuidString.lowercased(), q = try mapping("q")
        for attempt in 0..<20 {
            let event = row("bkt-0-\(attempt)", correct: attempt >= 5 ? attempt % 5 != 0 : attempt % 3 == 0,
                time: date.addingTimeInterval(Double(attempt) * 86400), mapping: q)
            try await store.append(event, account: account, library: "default")
        }
        var workspace = try await store.workspace(account: account, library: "default")
        workspace.candidates.append(candidate)
        try await store.saveWorkspace(workspace, expectedRevision: workspace.revision, account: account, library: "default")
        try require(candidate.learnerID == target, "Fitted artifact personal scope")
        if candidate.report.eligibleForReview {
            try await reopened.reviewLearnerCalibration(artifactID: candidate.report.id, reviewedBy: "synthetic test reviewer")
            try await reopened.switchLearnerModel(to: .bkt, mode: .observe)
            let prediction = try await reopened.learnerPrediction(model: .bkt, questionID: "q", questionVersion: 1, mapping: q, now: date.addingTimeInterval(21 * 86400))
            try require(prediction?.mode == .observe && prediction?.probabilityCorrect != nil, "Observation predictions labelled and accessible")
            try await reopened.switchLearnerModel(to: .bkt, mode: .active)
            let live = try await reopened.learnerStatus()
            try require(live.state.configuration.modes[.skill] == .active, "Between-session activation")
            let old = live.state.latest.first { $0.attemptID == "bkt-0-0" }!
            let correction = LearnerEvidence(attemptID: old.attemptID, revision: 2, questionID: old.questionID, questionVersion: old.questionVersion,
                occurredAt: old.occurredAt, kind: old.kind, mapping: old.mapping, assisted: false, acceptance: .accepted, correct: !old.correct!, gradingMethod: "corrected synthetic fixture")
            try await store.append(correction, account: account, library: "default")
            try await rejectsAsync { try await reopened.switchLearnerModel(to: .bkt, mode: .active) }
            let invalid = try await reopened.learnerPrediction(model: .bkt, questionID: "q", questionVersion: 1, mapping: q)
            try require(invalid == nil, "Correction of fitting data invalidates calibrated artifact")
        } else { throw NSError(domain: "AdvancedLearnerValidation", code: 4, userInfo: [NSLocalizedDescriptionKey: "Synthetic BKT fit should support review for activation test"]) }
        try await reopened.setLearnerRecordingEnabled(false)
        let disabled = try await reopened.learnerStatus()
        try require(!disabled.recordingEnabled && disabled.state.configuration.modes.values.allSatisfy { $0 == .off }, "Disabling collection stops all optional predictions")
        print("PASS: real FSRS preservation, opt-in study integration, provisional/final correction, restart, isolation, generated grading, fitted-artifact switching")
    }
    static func recovery() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("learner-recovery-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let account = UUID(), scheduler = FSRSScheduler(), stateURL = directory.appendingPathComponent("library.json")
        var source = LibrarySnapshot(); source.settings = StudySettings(timeZoneID: "UTC")
        source.decks = [Deck(id: "deck", name: "Recovery")]
        source.notes = [Note(id: "note", deckID: "deck", kind: .basic, front: "Question", back: "Answer")]
        source.cards = [StudyCard(id: "card", noteID: "note", deckID: "deck", schedule: try scheduler.initialState(now: date, settings: source.settings))]
        let base = try AtomicFileRepository(url: stateURL); try await base.commit(source, expectedRevision: 0)
        let realStore = LearnerModelRepository(directory: directory.appendingPathComponent("learner")), failingStore = FailingLearnerStore(base: realStore)
        let service = StudyService(repository: base, scheduler: scheduler, learnerStore: failingStore, learnerAccount: { account })
        try await service.setLearnerRecordingEnabled(true)
        let session = try await service.startSession(deckID: "deck", now: date)
        let id = try await service.beginLearnerRecall(presentationID: session.current!.presentationID, assisted: nil, now: date)
        await failingStore.failReconciliationOnce()
        try await service.submitAnswer(sessionID: session.id, presentationID: session.current!.presentationID,
            assessment: .init(outcome: .correct, reason: "Validated existing boundary", method: "local-exact"), now: date)
        let committed = try await base.read(), missing = try await realStore.load(account: account, library: "default")
        try require(committed.reviews.count == 1 && missing.evidence.isEmpty, "Successful FSRS commit survives learner-store failure")
        let restarted = StudyService(repository: try AtomicFileRepository(url: stateURL), scheduler: scheduler,
            learnerStore: LearnerModelRepository(directory: directory.appendingPathComponent("learner")), learnerAccount: { account })
        let recovered = try await restarted.learnerStatus()
        try require(recovered.state.latest.count == 1 && recovered.state.latest[0].attemptID == id && recovered.state.latest[0].assisted == nil,
            "Cold restart reconciles durable capture; unknown assistance preserved")
        print("PASS: durable recovery after learner-write failure; no FSRS rollback or invented assistance")
    }
}

private actor FailingLearnerStore: LearnerModelStore {
    let base: LearnerModelRepository
    var failNext = false
    init(base: LearnerModelRepository) { self.base = base }
    func failReconciliationOnce() { failNext = true }
    func load(account: UUID, library: String) async throws -> LearnerState { try await base.load(account: account, library: library) }
    func workspace(account: UUID, library: String) async throws -> LearnerWorkspace { try await base.workspace(account: account, library: library) }
    func saveWorkspace(_ workspace: LearnerWorkspace, expectedRevision: Int, account: UUID, library: String) async throws {
        try await base.saveWorkspace(workspace, expectedRevision: expectedRevision, account: account, library: library)
    }
    func reconcile(_ events: [LearnerEvidence], refreshAtBoundary: Bool, account: UUID, library: String) async throws {
        if failNext && !events.isEmpty { failNext = false; throw EngramError.storage("Injected learner-write failure") }
        try await base.reconcile(events, refreshAtBoundary: refreshAtBoundary, account: account, library: library)
    }
    func prepare(using predictor: any LearnerPredictor, account: UUID, library: String) async throws -> LearnerSnapshot { try await base.prepare(using: predictor, account: account, library: library) }
    func switchModel(to model: LearnerModelID, mode: LearnerMode, expectedEvidenceRevision: Int, betweenAttempts: Bool, account: UUID, library: String) async throws {
        try await base.switchModel(to: model, mode: mode, expectedEvidenceRevision: expectedEvidenceRevision, betweenAttempts: betweenAttempts, account: account, library: library)
    }
    func setPracticePreferences(fixed: Bool, provisionalFeedback: Bool, account: UUID, library: String) async throws {
        try await base.setPracticePreferences(fixed: fixed, provisionalFeedback: provisionalFeedback, account: account, library: library)
    }
}
