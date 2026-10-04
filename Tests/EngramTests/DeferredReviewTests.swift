import XCTest
import LearningCore
import StudyApplication
import PersistenceAdapters
import SchedulingAdapters

final class DeferredReviewTests: XCTestCase {
    func testEditingPreservesExplicitQuestionType() async throws {
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let deck = try await service.createDeck(name: "Maths")
        var draft = NoteDraft(deckID: deck.id, front: "Solve x", back: "2", tags: ["subject:maths", "subtype:algebra"])
        draft.questionType = "equation"
        let original = try await service.saveNote(draft, now: now)
        var edit = NoteDraft(note: original)
        edit.front = "Solve for x"
        let saved = try await service.saveNote(edit, now: now)
        XCTAssertEqual(saved.questionType, "equation")
        XCTAssertTrue(saved.acceptsMathInput)
        _ = try await service.startSession(deckID: deck.id, now: now)
        let studying = try await service.snapshot()
        let item = try XCTUnwrap(studying.session?.current)
        let sessionID = try XCTUnwrap(studying.session?.id)
        let attempt = AnswerAttempt(sessionID: sessionID, item: item, noteID: saved.id, answer: "2", prompt: saved.front, expected: saved.back, modelID: "fixture", evidence: [], now: now)
        try await service.enqueueAnswer(attempt)
        var changed = NoteDraft(note: saved); changed.tags = ["subject:physics"]
        _ = try await service.saveNote(changed, now: now.addingTimeInterval(1))
        let stored = try await service.snapshot().answerAttempts?.first
        XCTAssertEqual(stored?.subject, "maths")
        XCTAssertEqual(stored?.questionSubtype, "algebra")
    }
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private func fixture() async throws -> (StudyService, AnswerAttempt) {
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let deck = try await service.createDeck(name: "Recall")
        for i in 0..<3 { _ = try await service.saveNote(NoteDraft(deckID: deck.id, front: "Energy \(i)?", back: "ATP"), now: now) }
        _ = try await service.startSession(deckID: deck.id, now: now)
        let library = try await service.snapshot(), session = try XCTUnwrap(library.session), item = try XCTUnwrap(session.current)
        var attempt = AnswerAttempt(sessionID: session.id, item: item, noteID: item.card.noteID, answer: "ATP", prompt: "Energy?", expected: "ATP", modelID: "fixture", evidence: [], now: now)
        attempt.providerAccountID = "owner"
        return (service, attempt)
    }
    func testSubmissionPersistsAndAdvancesBeforeMarkingAndSurvivesDuplicate() async throws {
        let (service, attempt) = try await fixture()
        try await service.enqueueAnswer(attempt)
        let saved = try await service.snapshot()
        XCTAssertNotEqual(saved.session?.current?.presentationID, attempt.presentationID)
        XCTAssertEqual(saved.answerAttempts?.first?.processingState, "queued")
        XCTAssertEqual(saved.answerAttempts?.first?.questionType, "short-answer")
        XCTAssertTrue(saved.reviews.isEmpty)
        try await service.enqueueAnswer(attempt)
        let repeated = try await service.snapshot()
        XCTAssertEqual(repeated.revision, saved.revision)
        XCTAssertEqual(repeated.answerAttempts?.count, 1)
        XCTAssertFalse(QueuePolicy.dueCards(in: repeated, deckID: nil, now: now).contains { $0.id == attempt.cardID })
    }
    func testMarkingCommitsAtSubmissionTimeExactlyOnceWithoutTouchingNextQuestion() async throws {
        let (service, attempt) = try await fixture()
        try await service.enqueueAnswer(attempt)
        let before = try await service.snapshot()
        let result = AnswerAssessment(outcome: .correct, reason: "Exact", method: "local-exact")
        try await service.finishDeferredAnswer(id: attempt.id, assessment: result, providerAccountID: "owner", now: now.addingTimeInterval(60))
        try await service.finishDeferredAnswer(id: attempt.id, assessment: result, providerAccountID: "owner", now: now.addingTimeInterval(120))
        let saved = try await service.snapshot()
        XCTAssertEqual(saved.reviews.count, 1)
        XCTAssertEqual(saved.reviews.first?.reviewedAt, now)
        XCTAssertEqual(saved.reviews.first?.committedAt, now.addingTimeInterval(60))
        XCTAssertEqual(saved.session?.current, before.session?.current)
        XCTAssertEqual(saved.answerAttempts?.first?.processingState, "finished")
    }
    func testChangedIdentityCannotGradeAndUnclearStaysAvailableAfterSummary() async throws {
        let (service, attempt) = try await fixture()
        try await service.enqueueAnswer(attempt)
        do { try await service.finishDeferredAnswer(id: attempt.id, assessment: AnswerAssessment(outcome: .correct, reason: "Exact", method: "local-exact"), providerAccountID: "other"); XCTFail("Wrong account accepted") } catch {}
        try await service.finishDeferredAnswer(id: attempt.id, assessment: AnswerAssessment(outcome: .unclear, reason: "Ambiguous", method: "ai"), providerAccountID: "owner")
        try await service.markFeedbackViewed(ids: [attempt.id])
        let saved = try await service.snapshot()
        XCTAssertNil(saved.answerAttempts?.first?.summaryViewedAt)
        XCTAssertTrue(saved.reviews.isEmpty)
        try await service.finishDeferredAnswer(id: attempt.id, assessment: nil, providerAccountID: nil, manualGrade: .hard)
        let manual = try await service.snapshot()
        XCTAssertEqual(manual.reviews.first?.rating, .hard)
    }
    func testDisputeRemovesPriorGradeAndManualResolutionReplaysOriginalTime() async throws {
        let (service, attempt) = try await fixture()
        try await service.enqueueAnswer(attempt)
        try await service.finishDeferredAnswer(id: attempt.id, assessment: AnswerAssessment(outcome: .correct, reason: "Exact", method: "local-exact"), providerAccountID: "owner")
        try await service.reviseDeferredAssessment(id: attempt.id, assessment: AnswerAssessment(outcome: .unclear, reason: "Needs review", method: "ai"), providerAccountID: "owner")
        let disputed = try await service.snapshot()
        XCTAssertTrue(disputed.activeReviews.isEmpty)
        XCTAssertNil(disputed.answerAttempts?.first?.committedAt)
        try await service.finishDeferredAnswer(id: attempt.id, assessment: nil, providerAccountID: nil, manualGrade: .again)
        let resolved = try await service.snapshot()
        XCTAssertEqual(resolved.activeReviews.count, 1)
        XCTAssertEqual(resolved.activeReviews.first?.rating, .again)
        XCTAssertEqual(resolved.activeReviews.first?.reviewedAt, now)
    }
    func testVoiceConfirmationRequiredBeforeAnyMarkingAndPreservesRecognitionEdits() async throws {
        let (service, attempt) = try await fixture()
        let job = try await service.captureVoiceAnswer(recordingID: UUID(), deviceID: "device", ownerID: "owner", provider: "local", transcriptionModel: "local", gradingModel: "fixture", billingPath: .local, mode: .continueProcessing, sessionID: attempt.sessionID, presentationID: attempt.presentationID, evidence: [], localTranscript: "A tee pee", requireConfirmation: true, now: now)
        let unconfirmed = try await service.snapshot()
        XCTAssertEqual(unconfirmed.session?.current?.presentationID, attempt.presentationID)
        XCTAssertEqual(job.state, .awaitingConfirmation)
        let claim = try await service.claimVoiceAnswer(stage: .marking, deviceID: "device", ownerID: "owner")
        XCTAssertNil(claim)
        _ = try await service.confirmVoiceTranscript(id: job.id, deviceID: "device", ownerID: "owner", text: "ATP")
        let confirmed = try await service.snapshot()
        XCTAssertEqual(confirmed.answerAttempts?.first?.processingState, "queued")
        XCTAssertEqual(confirmed.answerAttempts?.first?.inputModality, "voice")
        XCTAssertEqual(confirmed.voiceJobs?.first?.transcriptRevisions, ["A tee pee"])
        XCTAssertNotEqual(confirmed.session?.current?.presentationID, attempt.presentationID)
    }
    func testManualDisputeOfUngradedAnswerActuallyCommitsReview() async throws {
        let (service, attempt) = try await fixture()
        try await service.enqueueAnswer(attempt)
        let unclear = AnswerAssessment(outcome: .unclear, reason: "Ambiguous", method: "ai")
        try await service.finishDeferredAnswer(id: attempt.id, assessment: unclear, providerAccountID: "owner")
        try await service.reviseDeferredAssessment(id: attempt.id, assessment: unclear, providerAccountID: "owner", manualGrade: .hard)
        let saved = try await service.snapshot()
        XCTAssertEqual(saved.activeReviews.count, 1)
        XCTAssertEqual(saved.activeReviews.first?.rating, .hard)
        XCTAssertEqual(saved.activeReviews.first?.gradingMethod, "manual")
        XCTAssertEqual(saved.activeReviews.first?.reviewedAt, now)
    }
    func testUnknownOrDuplicateBatchIDsAreRejected() async throws {
        let (_, attempt) = try await fixture()
        for id in ["other", attempt.id] {
            let result = "{\"attempt_id\":\"\(id)\",\"outcome\":\"unclear\",\"reason\":\"Ambiguous\",\"evidence_ids\":[]}"
            let json = id == "other" ? "{\"results\":[\(result)]}" : "{\"results\":[\(result),\(result)]}"
            XCTAssertThrowsError(try BatchAssessmentValidator.decode(json, attempts: [attempt]))
        }
    }
}
