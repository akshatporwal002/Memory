import XCTest
import LearningCore
import StudyApplication
import PersistenceAdapters
import SchedulingAdapters

final class VoiceWorkProcessorTests: XCTestCase {
    private actor Calls {
        var uploads = 0
        var grades = 0
        func upload() { uploads += 1 }
        func grade() { grades += 1 }
        func counts() -> [Int] { [uploads, grades] }
    }
    private actor RacingRepository: LibraryRepository {
        private var value = LibrarySnapshot()
        private var transcriptRace = true
        private var gradeRace = true
        func read() -> LibrarySnapshot { value }
        func commit(_ snapshot: LibrarySnapshot, expectedRevision: Int) throws {
            guard value.revision == expectedRevision else { throw EngramError.conflict }
            let state = snapshot.voiceJobs?.first?.state
            if (state == .awaitingMarking && transcriptRace) || (state == .completed && gradeRace) {
                if state == .awaitingMarking { transcriptRace = false } else { gradeRace = false }
                // An unrelated transaction advances the repository while retaining
                // this job's claim; the result must be persisted without an API retry.
                value.revision += 1
                throw EngramError.conflict
            }
            try LibraryValidation.validate(snapshot)
            value = snapshot; value.revision = expectedRevision + 1
        }
    }
    private func fixture(repository: any LibraryRepository = MemoryRepository()) async throws -> (StudyService, VoiceRecordingStore, VoiceAnswerJob, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = try VoiceRecordingStore(directory: directory)
        let service = StudyService(repository: repository, scheduler: FSRSScheduler())
        let deck = try await service.createDeck(name: "Worker fixtures")
        _ = try await service.saveNote(NoteDraft(deckID: deck.id, front: "Energy carrier?", back: "ATP"), now: Date())
        _ = try await service.startSession(deckID: deck.id, now: Date())
        let snapshot = try await service.snapshot()
        let session = try XCTUnwrap(snapshot.session), item = try XCTUnwrap(session.current)
        let recordingID = UUID()
        try await storage.save(Data([1, 2, 3]), id: recordingID)
        let job = try await service.captureVoiceAnswer(recordingID: recordingID, deviceID: "device", ownerID: "owner",
            provider: "openai", transcriptionModel: "gpt-4o-mini-transcribe", gradingModel: "chatgpt:fixture",
            billingPath: .personalKey, mode: .continueProcessing, sessionID: session.id,
            presentationID: item.presentationID, evidence: [])
        return (service, storage, job, directory)
    }
    func testWorkerPersistsTranscriptDeletesRecordingAndCommitsOnce() async throws {
        let (service, storage, job, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let calls = Calls()
        let processor = VoiceWorkProcessor(service: service, storage: storage, deviceID: "device", ownerID: "owner",
            transcribe: { _, bytes in
                XCTAssertEqual(bytes, Data([1, 2, 3])); await calls.upload()
                return VoiceTranscriptResult(text: "ATP")
            }, assess: { claimed in
                XCTAssertEqual(claimed.attempt.originalAnswer, "ATP")
                do { _ = try await storage.read(job.recordingID); XCTFail("Audio must be deleted before marking") } catch {}
                await calls.grade()
                return AnswerAssessment(outcome: .correct, reason: "Exact match", method: "local-exact")
            })
        try await service.endSession()
        await processor.start(); await processor.waitUntilIdle()
        await processor.start(); await processor.waitUntilIdle()
        let saved = try await service.snapshot(), counts = await calls.counts()
        XCTAssertEqual(saved.voiceJobs?.first?.state, .completed)
        XCTAssertEqual(saved.reviews.count, 1)
        XCTAssertEqual(counts, [1, 1]); XCTAssertNil(saved.session)
    }
    func testRevisionRacesReuseReturnedTranscriptAndAssessmentWithoutProviderRetries() async throws {
        let (service, storage, _, directory) = try await fixture(repository: RacingRepository())
        defer { try? FileManager.default.removeItem(at: directory) }
        let calls = Calls()
        let processor = VoiceWorkProcessor(service: service, storage: storage, deviceID: "device", ownerID: "owner",
            transcribe: { _, _ in await calls.upload(); return VoiceTranscriptResult(text: "ATP") },
            assess: { _ in await calls.grade(); return AnswerAssessment(outcome: .correct, reason: "Exact", method: "local-exact") })
        await processor.start(); await processor.waitUntilIdle()
        let saved = try await service.snapshot(), counts = await calls.counts()
        XCTAssertEqual(saved.voiceJobs?.first?.state, .completed)
        XCTAssertEqual(saved.reviews.count, 1); XCTAssertEqual(counts, [1, 1])
    }
    func testMarkingFailureRetriesSavedTranscriptWithoutAnotherUpload() async throws {
        let (service, storage, job, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let calls = Calls()
        let processor = VoiceWorkProcessor(service: service, storage: storage, deviceID: "device", ownerID: "owner",
            transcribe: { _, _ in await calls.upload(); return VoiceTranscriptResult(text: "ATP") },
            assess: { _ in
                await calls.grade()
                let counts = await calls.counts()
                if counts[1] == 1 { throw EngramError.invalid("Temporary marking failure") }
                return AnswerAssessment(outcome: .correct, reason: "Exact match", method: "local-exact")
            })
        await processor.start(); await processor.waitUntilIdle()
        let failed = try await service.snapshot()
        XCTAssertEqual(failed.voiceJobs?.first?.state, .needsAttention)
        XCTAssertTrue(failed.reviews.isEmpty)
        try await service.retryVoiceAnswer(id: job.id, deviceID: "device", ownerID: "owner")
        await processor.start(); await processor.waitUntilIdle()
        let saved = try await service.snapshot(), counts = await calls.counts()
        XCTAssertEqual(saved.reviews.count, 1); XCTAssertEqual(counts, [1, 2])
    }
    func testForeignOwnerCannotDispatchAudioOrGrade() async throws {
        let (service, storage, _, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let processor = VoiceWorkProcessor(service: service, storage: storage, deviceID: "device", ownerID: "other",
            transcribe: { _, _ in XCTFail("Foreign upload"); return VoiceTranscriptResult(text: "ATP") },
            assess: { _ in XCTFail("Foreign grade"); return AnswerAssessment(outcome: .correct, reason: "Exact", method: "local-exact") })
        await processor.start(); await processor.waitUntilIdle()
        let saved = try await service.snapshot()
        XCTAssertEqual(saved.voiceJobs?.first?.state, .captured); XCTAssertTrue(saved.reviews.isEmpty)
    }
    func testStopRejectsLateTranscriptAndRestartRequiresExplicitUploadRetry() async throws {
        let (service, storage, _, directory) = try await fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let calls = Calls()
        let processor = VoiceWorkProcessor(service: service, storage: storage, deviceID: "device", ownerID: "owner",
            transcribe: { _, _ in
                await calls.upload()
                // Simulate a transport returning buffered data after cancellation.
                try? await Task.sleep(for: .seconds(30))
                return VoiceTranscriptResult(text: "ATP")
            }, assess: { _ in XCTFail("Cancelled result must never grade"); return AnswerAssessment(outcome: .correct, reason: "Exact", method: "local-exact") })
        await processor.start()
        for _ in 0..<100 {
            if await calls.counts()[0] == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let beforeStop = await calls.counts()
        XCTAssertEqual(beforeStop[0], 1)
        await processor.stopAndWait()
        await processor.start(); await processor.waitUntilIdle()
        let saved = try await service.snapshot(), counts = await calls.counts()
        XCTAssertEqual(saved.voiceJobs?.first?.state, .needsAttention)
        XCTAssertEqual(saved.voiceJobs?.first?.attempt.originalAnswer, "")
        XCTAssertTrue(saved.reviews.isEmpty); XCTAssertEqual(counts, [1, 0])
    }
}
