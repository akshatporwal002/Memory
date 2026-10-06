import Foundation

// Standalone backend checks compile production sources directly without Apple UI or dependency downloads.
private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw NSError(domain: "LearnerValidation", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
private func rejects(_ operation: () throws -> Void) throws {
    do { try operation() } catch is LearnerError { return }
    throw NSError(domain: "LearnerValidation", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected rejection"])
}
private struct ReplayFixture: LearnerPredictor {
    let model: LearnerModelID
    let artifactRevision = "test-only"
    let readiness: String? = nil
    func compatible(_ row: LearnerEvidence) -> Bool { row.mapping != nil && row.assisted == false }
    func replay(_ rows: [LearnerEvidence]) throws -> Data { try JSONEncoder().encode(rows.map(\.attemptID)) }
}
@main struct LearnerModelValidation {
    static func main() async throws {
        let mapping = try ReviewedSkillMapping(questionID: "q", questionVersion: 1, revision: "reviewed-v1", skillIDs: ["s"], reviewedBy: "fixture-reviewer")
        let date = Date(timeIntervalSince1970: 1_000_000)
        func row(_ revision: Int = 1, acceptance: LearnerEvidence.Acceptance = .accepted, correct: Bool? = true,
                 assisted: Bool? = false, mapping supplied: ReviewedSkillMapping? = mapping) -> LearnerEvidence {
            LearnerEvidence(attemptID: "attempt", revision: revision, questionID: "q", questionVersion: 1,
                occurredAt: date, kind: .generatedApplication, mapping: supplied, assisted: assisted,
                acceptance: acceptance, correct: correct, gradingMethod: "validated-test-fixture", unfamiliar: true,
                studySeconds: 12, errorSkillIDs: correct == false && supplied != nil ? ["s"] : [])
        }
        var state = LearnerState()
        try check(state.configuration.recallScheduler == "fsrs", "FSRS default")
        try check(state.configuration.skill == .das3h && state.configuration.modes[.skill] == .off, "Preferred model stays gated")
        let bkt = ReplayFixture(model: .bkt), das = ReplayFixture(model: .das3h)
        try rejects { _ = try state.prepare(using: bkt) }
        try state.append(row(acceptance: .provisional, correct: nil))
        try rejects { _ = try state.prepare(using: bkt) }
        try state.append(row(2))
        try state.append(row(2))
        try check(state.latest.count == 1 && state.evidence.count == 2 && state.revision == 2, "Final grading and retries never duplicate attempt")
        let first = try state.prepare(using: bkt)
        try rejects { try state.switchModel(to: .bkt, mode: .active, betweenAttempts: false) }
        try state.switchModel(to: .bkt, mode: .observe, betweenAttempts: true)
        try check(state.configuration.modes[.skill] == .observe, "Observe mode")
        _ = try state.prepare(using: das)
        try state.switchModel(to: .das3h, mode: .active, betweenAttempts: true)
        try check(state.snapshots.contains(first), "Previous state preserved")
        try state.append(row(3, correct: false))
        try check(state.current.isEmpty && state.configuration.modes[.skill] == .observe, "Correction invalidates active state")
        try rejects { try state.switchModel(to: .das3h, mode: .active, betweenAttempts: true) }
        let corrected = try state.prepare(using: bkt)
        try check(corrected.compatibleAttempts == 1, "Replay uses corrected latest attempt once")
        try state.switchModel(to: .bkt, mode: .off, betweenAttempts: true)
        try check(state.current.isEmpty && state.snapshots.contains(corrected), "Off stops influence and preserves states")
        let dashboard = LearnerDashboard(state: state)
        try check(dashboard.unfamiliarQuestions.attempts == 1 && dashboard.unfamiliarQuestions.correct == 0, "Observed unfamiliar performance")
        try check(dashboard.skillErrors["s"] == 1 && dashboard.measuredStudySeconds == 12, "No double counted errors or duration")
        try check(dashboard.delayedRecall.attempts == 0, "Application never becomes recall")
        try state.append(row(4, acceptance: .retracted, correct: nil))
        try check(LearnerDashboard(state: state).acceptedAttempts == 0, "Retraction removes outcome")
        try rejects { try state.append(row(6)) }
        try rejects { try state.append(row(4)) }
        try state.validate()
        let roundTrip = try JSONDecoder().decode(LearnerState.self, from: JSONEncoder().encode(state))
        try roundTrip.validate(); try check(roundTrip == state, "State persistence round trip")
        var future = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        future["schemaVersion"] = 2
        let futureState = try JSONDecoder().decode(LearnerState.self, from: JSONSerialization.data(withJSONObject: future))
        try rejects { try futureState.validate() }
        var unknown = LearnerState(); try unknown.append(row(assisted: nil, mapping: nil))
        try rejects { _ = try unknown.prepare(using: bkt) }
        try check(LearnerDashboard(state: unknown).unfamiliarQuestions.attempts == 0, "Unknown assistance excluded")
        let parameters = BKTLearnerPredictor.Parameters(prior: 0.2, learn: 0.1, guess: 0.2, slip: 0.1)
        let predictor = BKTLearnerPredictor(artifact: .init(revision: "synthetic-only", mappingRevision: mapping.revision,
            trainingReport: "synthetic test fixture, not fitted", heldOutValidationReport: "synthetic test fixture, not calibrated", parameters: ["s": parameters]))
        let payload = try predictor.replay([row()])
        let mastery = try JSONDecoder().decode([String: Double].self, from: payload)
        try check(abs((mastery["s"] ?? 0) - 0.5764705882352941) < 0.000001, "BKT posterior and learning update")
        let displayedMastery = try predictor.mastery(mapping: mapping, history: payload)
        let responseProbability = try predictor.probability(mapping: mapping, history: payload)
        try check(displayedMastery == mastery && abs(responseProbability - displayedMastery["s"]!) > 0.01, "Analytics distinguish BKT mastery from response probability")
        try check(!predictor.compatible(row(assisted: nil)), "BKT unknown assistance")
        let dasPredictor = DAS3HLearnerPredictor(artifact: .init(revision: "synthetic-only", mappingRevision: mapping.revision,
            trainingReport: "synthetic test, not fitted", heldOutValidationReport: "synthetic test, not calibrated",
            ability: 0, windows: [60, nil], skills: ["s": .init(easiness: 0, wins: [1, 1], attempts: [0, 0])],
            items: [.init(questionID: "q", questionVersion: 1, difficulty: 0)]))
        let dasHistory = try dasPredictor.replay([row()])
        let beforeWin = try dasPredictor.probability(mapping: mapping, at: date, history: dasHistory)
        try check(beforeWin == 0.5, "No target outcome leakage")
        let afterWin = try dasPredictor.probability(mapping: mapping, at: date.addingTimeInterval(1), history: dasHistory)
        let afterWindow = try dasPredictor.probability(mapping: mapping, at: date.addingTimeInterval(61), history: dasHistory)
        try check(abs(afterWin - 0.8) < 0.000001 && abs(afterWindow - 2.0 / 3.0) < 0.000001, "DAS3H expanding windows and natural log counts")
        let uncalibrated = BKTLearnerPredictor(artifact: .init(revision: "x", mappingRevision: "v", trainingReport: "", heldOutValidationReport: "", parameters: ["s": parameters]))
        try rejects { _ = try uncalibrated.replay([row()]) }
        try check(LearnerModelDescription.catalog(predictors: []).allSatisfy { !$0.selectable }, "Unavailable models informational")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("learner-validation-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LearnerModelRepository(directory: directory), account = UUID(), library = UUID().uuidString
        do {
            _ = try await repository.load(account: account, library: "../escape")
            throw NSError(domain: "LearnerValidation", code: 4)
        } catch is LearnerError {}
        try await repository.append(row(), account: account, library: "default")
        let defaultLibrary = try await repository.load(account: account, library: "default")
        try check(defaultLibrary.latest.count == 1, "Legacy default library supported")
        try await repository.append(row(), account: account, library: library)
        let reloaded = try await LearnerModelRepository(directory: directory).load(account: account, library: library)
        try check(reloaded.latest.count == 1, "Durable reload")
        let otherAccount = try await repository.load(account: UUID(), library: library)
        let otherLibrary = try await repository.load(account: account, library: UUID().uuidString)
        try check(otherAccount.evidence.isEmpty && otherLibrary.evidence.isEmpty, "Account/library isolation")
        _ = try await repository.prepare(using: bkt, account: account, library: library)
        try await repository.switchModel(to: .bkt, mode: .active, expectedEvidenceRevision: 1, betweenAttempts: true, account: account, library: library)
        try await repository.append(row(2, correct: false), account: account, library: library)
        do {
            try await repository.switchModel(to: .bkt, mode: .active, expectedEvidenceRevision: 1, betweenAttempts: true, account: account, library: library)
            throw NSError(domain: "LearnerValidation", code: 3)
        } catch is LearnerError {}
        try await repository.delete(account: account, library: library)
        let deleted = try await repository.load(account: account, library: library)
        try check(deleted.evidence.isEmpty, "Scoped deletion")
        let retained = try await repository.load(account: account, library: "default")
        try check(retained.latest.count == 1, "Deletion preserves another library")
        let storedURL = directory.appendingPathComponent(account.uuidString.lowercased()).appendingPathComponent("default.json")
        try Data("corrupt".utf8).write(to: storedURL)
        var corruptRejected = false
        do { _ = try await repository.load(account: account, library: "default") } catch { corruptRejected = true }
        try check(corruptRejected && (try? Data(contentsOf: storedURL)) == Data("corrupt".utf8), "Corrupt storage is surfaced, never silently erased")
        // Reuse the existing accepted assessment boundary, excluding undone reviews and unknown assistance.
        var source = LibrarySnapshot()
        let schedule = ScheduleState(schedulerID: "fsrs", due: date, phase: .review)
        let card = StudyCard(id: "card", noteID: "note", deckID: "deck", schedule: schedule)
        let presentation = ReviewPresentation(card: card)
        var attempt = AnswerAttempt(sessionID: "session", item: presentation, noteID: "note", answer: "answer", prompt: "prompt", expected: "answer", modelID: "fixture", evidence: [], now: date)
        attempt.assessment = AnswerAssessment(outcome: .correct, reason: "Exact match", method: "local-exact")
        attempt.committedAt = date
        var review = ReviewEvent(id: "answer-" + presentation.presentationID, cardID: "card", deckID: "deck", sessionID: "session", rating: .good, reviewedAt: date, committedAt: date, before: schedule, after: schedule)
        review.assessment = attempt.assessment; review.gradingMethod = attempt.assessment?.method
        source.answerAttempts = [attempt]; source.reviews = [review]
        let accepted = try AcceptedLearnerEvidence.recall(attemptID: attempt.id, revision: 1, in: source)
        try check(accepted.correct == true && accepted.assisted == nil && accepted.mapping == nil, "Bridge preserves unknown historical metadata")
        try check(source.cards.isEmpty && source.reviews == [review], "Bridge does not mutate schedules or reviews")
        source.corrections = [ReviewCorrection(reviewID: review.id, createdAt: date)]
        try rejects { _ = try AcceptedLearnerEvidence.recall(attemptID: attempt.id, revision: 1, in: source) }
        try await LearnerAdvancedValidation.run()
        print("PASS: evidence, persistence, isolation, replay, switching, correction, fallbacks, dashboard and synthetic BKT math")
    }
}
