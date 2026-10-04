import XCTest
import LearningCore
import StudyApplication
import PersistenceAdapters
import SchedulingAdapters

final class VoiceAnswerJobTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_393_600)
    private func fixture(count: Int = 2, repository: any LibraryRepository = MemoryRepository()) async throws -> StudyService {
        let service = StudyService(repository: repository, scheduler: FSRSScheduler())
        let deck = try await service.createDeck(name: "Voice fixtures")
        for index in 0..<count {
            _ = try await service.saveNote(NoteDraft(deckID: deck.id, front: "Energy carrier \(index)?", back: "ATP"), now: now)
        }
        _ = try await service.startSession(deckID: deck.id, now: now)
        return service
    }
    private func capture(_ service: StudyService, mode: VoiceReviewMode = .continueProcessing) async throws -> VoiceAnswerJob {
        let snapshot = try await service.snapshot()
        let session = try XCTUnwrap(snapshot.session), item = try XCTUnwrap(session.current)
        return try await service.captureVoiceAnswer(recordingID: UUID(), deviceID: "device", ownerID: "account-revision",
            provider: "openai", transcriptionModel: "gpt-4o-mini-transcribe", gradingModel: "chatgpt:fixture",
            billingPath: .personalKey, mode: mode, sessionID: session.id, presentationID: item.presentationID, evidence: [], now: now)
    }
    private func readyForMarking(_ service: StudyService) async throws -> VoiceAnswerJob {
        let claimed = try await service.claimVoiceAnswer(stage: .transcription, deviceID: "device", ownerID: "account-revision")
        let worker = try XCTUnwrap(claimed)
        try await service.storeVoiceTranscript(id: worker.id, generation: worker.generation, deviceID: "device", ownerID: "account-revision", text: "ATP")
        let marking = try await service.claimVoiceAnswer(stage: .marking, deviceID: "device", ownerID: "account-revision")
        return try XCTUnwrap(marking)
    }
    func testLocalTranscriptIsDurableBeforeContinueAdvancesAndSkipsUpload() async throws {
        let service = try await fixture()
        let before = try await service.snapshot()
        let session = try XCTUnwrap(before.session), item = try XCTUnwrap(session.current)
        let recordingID = UUID()
        let job = try await service.captureVoiceAnswer(recordingID: recordingID, deviceID: "device", ownerID: "account-revision",
            provider: "local", transcriptionModel: "parakeet", gradingModel: "chatgpt:fixture", billingPath: .local,
            mode: .continueProcessing, sessionID: session.id, presentationID: item.presentationID,
            evidence: [], localTranscript: "not ATP", now: now)
        let saved = try await service.snapshot()
        XCTAssertEqual(saved.voiceJobs?.first?.attempt.originalAnswer, "not ATP")
        XCTAssertEqual(job.state, .awaitingMarking)
        XCTAssertNotEqual(saved.session?.current?.presentationID, item.presentationID)
        let upload = try await service.claimVoiceAnswer(stage: .transcription, deviceID: "device", ownerID: "account-revision")
        XCTAssertNil(upload)
        let marking = try await service.claimVoiceAnswer(stage: .marking, deviceID: "device", ownerID: "account-revision")
        XCTAssertEqual(marking?.attempt.originalAnswer, "not ATP")
        // Retrying uncertain capture returns the accepted original, never rewrites it.
        let repeated = try await service.captureVoiceAnswer(recordingID: recordingID, deviceID: "device", ownerID: "account-revision",
            provider: "local", transcriptionModel: "parakeet", gradingModel: "chatgpt:fixture", billingPath: .local,
            mode: .continueProcessing, sessionID: session.id, presentationID: item.presentationID,
            evidence: [], localTranscript: "ATP", now: now)
        XCTAssertEqual(repeated.attempt.originalAnswer, "not ATP")
    }
    func testLocalTranscriptCannotImpersonateCloudCaptureOrSaveEmptyAnswer() async throws {
        let service = try await fixture()
        let snapshot = try await service.snapshot()
        let session = try XCTUnwrap(snapshot.session), item = try XCTUnwrap(session.current)
        for (provider, path, text) in [("openai", VoiceBillingPath.personalKey, "ATP"), ("local", .local, " ")] {
            do {
                _ = try await service.captureVoiceAnswer(recordingID: UUID(), deviceID: "device", ownerID: "account-revision",
                    provider: provider, transcriptionModel: "test", gradingModel: "test", billingPath: path,
                    mode: .continueProcessing, sessionID: session.id, presentationID: item.presentationID,
                    evidence: [], localTranscript: text, now: now)
                XCTFail("Invalid local capture accepted")
            } catch { }
        }
        let saved = try await service.snapshot()
        XCTAssertTrue((saved.voiceJobs ?? []).isEmpty)
        XCTAssertEqual(saved.session?.current?.presentationID, item.presentationID)
    }
    func testContinueCommitsOriginalTimeOnceAfterLeavingSessionWithoutStealingFocus() async throws {
        let service = try await fixture()
        let captured = try await capture(service)
        let advanced = try await service.snapshot()
        XCTAssertNotEqual(advanced.session?.current?.card.id, captured.card.id)
        XCTAssertFalse(QueuePolicy.dueCards(in: advanced, deckID: nil, now: now).contains { $0.id == captured.card.id })
        let worker = try await readyForMarking(service)
        try await service.endSession()
        let assessment = AnswerAssessment(outcome: .correct, reason: "Exact match", method: "local-exact")
        try await service.commitVoiceAnswer(id: worker.id, generation: worker.generation, deviceID: "device", ownerID: "account-revision", assessment: assessment, now: now.addingTimeInterval(90))
        try await service.commitVoiceAnswer(id: worker.id, generation: worker.generation, deviceID: "device", ownerID: "account-revision", assessment: assessment, now: now.addingTimeInterval(100))
        let saved = try await service.snapshot()
        XCTAssertNil(saved.session)
        XCTAssertEqual(saved.reviews.count, 1)
        XCTAssertEqual(saved.reviews.first?.reviewedAt, now)
        XCTAssertEqual(saved.answerAttempts?.first?.originalAnswer, "ATP")
        XCTAssertEqual(saved.voiceJobs?.first?.state, .completed)
    }
    func testWorkerLimitsAndUnresolvedLimit() async throws {
        let service = try await fixture(count: 11)
        for _ in 0..<10 { _ = try await capture(service) }
        do { _ = try await capture(service); XCTFail("Expected pending limit") } catch {}
        let first = try await service.claimVoiceAnswer(stage: .transcription, deviceID: "device", ownerID: "account-revision")
        let second = try await service.claimVoiceAnswer(stage: .transcription, deviceID: "device", ownerID: "account-revision")
        let blocked = try await service.claimVoiceAnswer(stage: .transcription, deviceID: "device", ownerID: "account-revision")
        XCTAssertNotNil(first); XCTAssertNotNil(second); XCTAssertNil(blocked)
        for worker in [try XCTUnwrap(first), try XCTUnwrap(second)] {
            try await service.storeVoiceTranscript(id: worker.id, generation: worker.generation, deviceID: "device", ownerID: "account-revision", text: "ATP")
        }
        let marking = try await service.claimVoiceAnswer(stage: .marking, deviceID: "device", ownerID: "account-revision")
        let markingBlocked = try await service.claimVoiceAnswer(stage: .marking, deviceID: "device", ownerID: "account-revision")
        XCTAssertNotNil(marking); XCTAssertNil(markingBlocked)
    }
    func testCancelledAndForeignWorkersCannotWriteLateResults() async throws {
        let service = try await fixture()
        _ = try await capture(service)
        let claim = try await service.claimVoiceAnswer(stage: .transcription, deviceID: "device", ownerID: "account-revision")
        let worker = try XCTUnwrap(claim)
        do { try await service.storeVoiceTranscript(id: worker.id, generation: worker.generation, deviceID: "other", ownerID: "account-revision", text: "ATP"); XCTFail("Expected device rejection") } catch {}
        try await service.cancelVoiceAnswer(id: worker.id, deviceID: "device", ownerID: "account-revision")
        do { try await service.storeVoiceTranscript(id: worker.id, generation: worker.generation, deviceID: "device", ownerID: "account-revision", text: "ATP"); XCTFail("Expected stale lease rejection") } catch {}
        let snapshot = try await service.snapshot()
        XCTAssertEqual(snapshot.voiceJobs?.first?.state, .cancelled)
        XCTAssertTrue(snapshot.reviews.isEmpty)
    }
    func testTranscriptCorrectionSupersedesMarkingAndWaitAdvancesWithoutAnotherGrade() async throws {
        let service = try await fixture()
        let captured = try await capture(service, mode: .waitForFeedback)
        let prior = try await readyForMarking(service)
        try await service.correctPendingVoiceTranscript(id: prior.id, deviceID: "device", ownerID: "account-revision", text: "atp")
        let assessment = AnswerAssessment(outcome: .correct, reason: "Exact match", method: "local-exact")
        do {
            try await service.commitVoiceAnswer(id: prior.id, generation: prior.generation, deviceID: "device", ownerID: "account-revision", assessment: assessment, now: now.addingTimeInterval(10))
            XCTFail("Expected superseded marking rejection")
        } catch {}
        let claim = try await service.claimVoiceAnswer(stage: .marking, deviceID: "device", ownerID: "account-revision")
        let current = try XCTUnwrap(claim)
        try await service.commitVoiceAnswer(id: current.id, generation: current.generation, deviceID: "device", ownerID: "account-revision", assessment: assessment, now: now.addingTimeInterval(20))
        let waiting = try await service.snapshot()
        XCTAssertEqual(waiting.session?.current?.presentationID, captured.attempt.presentationID)
        XCTAssertEqual(waiting.session?.current?.assessment?.outcome, .correct)
        XCTAssertEqual(waiting.voiceJobs?.first?.transcriptRevisions, ["ATP"])
        try await service.advanceCompletedVoiceAnswer(id: current.id, deviceID: "device", ownerID: "account-revision", now: now.addingTimeInterval(20))
        let advanced = try await service.snapshot()
        XCTAssertNotEqual(advanced.session?.current?.presentationID, captured.attempt.presentationID)
        XCTAssertEqual(advanced.reviews.count, 1)
    }
    func testCompletedCorrectionReplaysLaterReviewsAndRegradesAtOriginalTimeOnce() async throws {
        let service = try await fixture(count: 1)
        let initial = try await service.snapshot()
        let session = try XCTUnwrap(initial.session), item = try XCTUnwrap(session.current)
        let note = try XCTUnwrap(initial.liveNotes.first)
        let evidence = LocalAnswerEvidence.retrieve(note: note, prompt: note.front, library: initial)
            .map { AttemptEvidence(id: $0.id, text: $0.text, version: $0.version) }
        let job = try await service.captureVoiceAnswer(recordingID: UUID(), deviceID: "device", ownerID: "account-revision",
            provider: "local", transcriptionModel: "parakeet", gradingModel: "fixture", billingPath: .local,
            mode: .continueProcessing, sessionID: session.id, presentationID: item.presentationID,
            evidence: evidence, localTranscript: "ATP", now: now)
        let claim = try await service.claimVoiceAnswer(stage: .marking, deviceID: "device", ownerID: "account-revision")
        let firstWorker = try XCTUnwrap(claim)
        let correct = AnswerAssessment(outcome: .correct, reason: "Exact", method: "local-exact")
        try await service.commitVoiceAnswer(id: job.id, generation: firstWorker.generation, deviceID: "device", ownerID: "account-revision", assessment: correct, now: now.addingTimeInterval(1))
        let laterTime = now.addingTimeInterval(2 * 86_400)
        let laterSession = try await service.startSession(deckID: note.deckID, now: laterTime)
        let laterItem = try XCTUnwrap(laterSession.current)
        _ = try await service.reveal(sessionID: laterSession.id, presentationID: laterItem.presentationID, now: laterTime)
        try await service.grade(sessionID: laterSession.id, presentationID: laterItem.presentationID, rating: .good, mutationID: "later-review", now: laterTime)
        let beforeCorrection = try await service.snapshot()
        let laterEvent = try XCTUnwrap(beforeCorrection.reviews.first { $0.id == "later-review" })
        try await service.correctCompletedVoiceTranscript(id: job.id, deviceID: "device", ownerID: "account-revision", text: "ADP", now: laterTime.addingTimeInterval(1))
        let removed = try await service.snapshot()
        XCTAssertEqual(removed.activeReviews.map(\.id), ["later-review"])
        XCTAssertEqual(removed.reviews.first { $0.id == "later-review" }, laterEvent)
        XCTAssertEqual(removed.voiceJobs?.first?.transcriptRevisions, ["ATP"])
        XCTAssertNil(removed.answerAttempts?.first?.committedAt)
        let scheduler = FSRSScheduler()
        let withoutFirst = try XCTUnwrap(scheduler.outcomes(state: job.card.schedule, history: [], now: laterTime, settings: initial.settings)[.good])
        XCTAssertEqual(removed.cards.first?.schedule, withoutFirst)
        do {
            try await service.commitVoiceAnswer(id: job.id, generation: firstWorker.generation, deviceID: "device", ownerID: "account-revision", assessment: correct, now: laterTime.addingTimeInterval(2))
            XCTFail("Old assessment restored")
        } catch { }
        let replacementClaim = try await service.claimVoiceAnswer(stage: .marking, deviceID: "device", ownerID: "account-revision")
        let replacement = try XCTUnwrap(replacementClaim)
        var incorrect = AnswerAssessment(outcome: .incorrect, reason: "The reference names ATP, not ADP.", method: "ai")
        incorrect.evidenceIDs = evidence.map(\.id)
        try await service.commitVoiceAnswer(id: job.id, generation: replacement.generation, deviceID: "device", ownerID: "account-revision", assessment: incorrect, now: laterTime.addingTimeInterval(3))
        try await service.commitVoiceAnswer(id: job.id, generation: replacement.generation, deviceID: "device", ownerID: "account-revision", assessment: incorrect, now: laterTime.addingTimeInterval(4))
        let saved = try await service.snapshot()
        XCTAssertEqual(saved.reviews.count, 3)
        XCTAssertEqual(saved.activeReviews.count, 2)
        let revised = try XCTUnwrap(saved.activeReviews.first { $0.id == replacement.reviewID })
        XCTAssertEqual(revised.reviewedAt, now)
        XCTAssertEqual(revised.rating, .again)
        let expected = try XCTUnwrap(scheduler.outcomes(state: revised.after, history: [revised], now: laterTime, settings: initial.settings)[.good])
        XCTAssertEqual(saved.cards.first?.schedule, expected)
        XCTAssertEqual(saved.reviews.first { $0.id == "later-review" }, laterEvent)
        XCTAssertEqual(saved.answerAttempts?.first?.originalAnswer, "ADP")
    }
    func testCompletedCorrectionRejectsOtherOwnerAndEditedQuestionWithoutRemovingGrade() async throws {
        let service = try await fixture(count: 1)
        let job = try await capture(service)
        let worker = try await readyForMarking(service)
        try await service.commitVoiceAnswer(id: job.id, generation: worker.generation, deviceID: "device", ownerID: "account-revision", assessment: AnswerAssessment(outcome: .correct, reason: "Exact", method: "local-exact"), now: now.addingTimeInterval(1))
        do {
            try await service.correctCompletedVoiceTranscript(id: job.id, deviceID: "device", ownerID: "other", text: "ADP", now: now.addingTimeInterval(2))
            XCTFail("Other owner accepted")
        } catch { }
        var draft = NoteDraft(note: job.note); draft.back = "new reference"
        _ = try await service.saveNote(draft, now: now.addingTimeInterval(3))
        do {
            try await service.correctCompletedVoiceTranscript(id: job.id, deviceID: "device", ownerID: "account-revision", text: "ADP", now: now.addingTimeInterval(4))
            XCTFail("Stale reference accepted")
        } catch { }
        let saved = try await service.snapshot()
        XCTAssertEqual(saved.activeReviews.count, 1)
        XCTAssertTrue(saved.corrections.isEmpty)
        XCTAssertEqual(saved.voiceJobs?.first?.state, .completed)
    }
    func testUnclearFeedbackSavesNoGradeAndRetryDoesNotRetranscribe() async throws {
        let service = try await fixture()
        _ = try await capture(service)
        let worker = try await readyForMarking(service)
        try await service.commitVoiceAnswer(id: worker.id, generation: worker.generation, deviceID: "device", ownerID: "account-revision", assessment: AnswerAssessment(outcome: .unclear, reason: "Insufficient evidence", method: "ai"), now: now.addingTimeInterval(10))
        let unclear = try await service.snapshot()
        XCTAssertTrue(unclear.reviews.isEmpty)
        XCTAssertEqual(unclear.voiceJobs?.first?.state, .needsAttention)
        try await service.retryVoiceAnswer(id: worker.id, deviceID: "device", ownerID: "account-revision")
        let retried = try await service.snapshot()
        XCTAssertEqual(retried.voiceJobs?.first?.state, .awaitingMarking)
        XCTAssertEqual(retried.voiceJobs?.first?.attempt.originalAnswer, "ATP")
    }
    func testQuestionEditRejectsGradeWithoutChangingScheduling() async throws {
        let service = try await fixture()
        let captured = try await capture(service)
        let worker = try await readyForMarking(service)
        var draft = NoteDraft(note: captured.note); draft.back = "ADP"
        _ = try await service.saveNote(draft, now: now.addingTimeInterval(10))
        do {
            try await service.commitVoiceAnswer(id: worker.id, generation: worker.generation, deviceID: "device", ownerID: "account-revision", assessment: AnswerAssessment(outcome: .correct, reason: "old", method: "local-exact"), now: now.addingTimeInterval(20))
            XCTFail("Expected stale question rejection")
        } catch {}
        let snapshot = try await service.snapshot()
        XCTAssertTrue(snapshot.reviews.isEmpty)
        XCTAssertEqual(snapshot.liveCards.first { $0.id == captured.card.id }?.schedule, captured.card.schedule)
    }
    func testRestartRecoversMarkingButNeverSilentlyRetriesBilledUploads() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library.json")
        let service = try await fixture(count: 2, repository: AtomicFileRepository(url: url))
        _ = try await capture(service); _ = try await capture(service)
        let marking = try await readyForMarking(service)
        let transcription = try await service.claimVoiceAnswer(stage: .transcription, deviceID: "device", ownerID: "account-revision")
        let reopened = StudyService(repository: try AtomicFileRepository(url: url), scheduler: FSRSScheduler())
        try await reopened.recoverVoiceAnswers(deviceID: "device", ownerID: "account-revision")
        let saved = try await reopened.snapshot()
        XCTAssertEqual(saved.voiceJobs?.first { $0.id == marking.id }?.state, .awaitingMarking)
        XCTAssertEqual(saved.voiceJobs?.first { $0.id == transcription?.id }?.state, .needsAttention)
        XCTAssertEqual(saved.voiceJobs?.first { $0.id == marking.id }?.attempt.originalAnswer, "ATP")
    }
    func testRecordingStoreIsIdempotentAndExpiresOnlyOwnedRecordings() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try VoiceRecordingStore(directory: directory)
        let expired = UUID(), current = UUID(), audio = Data([1, 2, 3])
        try await store.save(audio, id: expired, now: now.addingTimeInterval(-8 * 86400))
        try await store.save(audio, id: current, now: now)
        try await store.save(audio, id: current, now: now)
        do { try await store.save(Data([4]), id: current, now: now); XCTFail("Expected immutable capture") } catch {}
        try Data([9]).write(to: directory.appendingPathComponent("other.wav"))
        let removed = try await store.removeExpired(now: now)
        XCTAssertEqual(removed, [expired])
        let saved = try await store.read(current)
        XCTAssertEqual(saved, audio)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("other.wav").path))
    }
}
