import Foundation
import LearningCore

/// Foreground-only dispatch. Credentials/billing approvals are supplied by the
/// composition root, never embedded in durable jobs or inferred by this actor.
public actor VoiceWorkProcessor {
    public typealias Transcribe = @Sendable (VoiceAnswerJob, Data) async throws -> VoiceTranscriptResult
    public typealias Assess = @Sendable (VoiceAnswerJob) async throws -> AnswerAssessment
    public typealias Changed = @Sendable () async -> Void
    private let service: StudyService
    private let storage: any VoiceAudioStorage
    private let deviceID: String
    private let ownerID: String
    private let transcribe: Transcribe
    private let assess: Assess
    private let changed: Changed
    private var loop: Task<Void, Never>?
    private var workers: [String: Task<Void, Never>] = [:]
    private var epoch = UUID()
    public private(set) var error: String?
    public init(service: StudyService, storage: any VoiceAudioStorage, deviceID: String, ownerID: String,
                transcribe: @escaping Transcribe, assess: @escaping Assess, changed: @escaping Changed = {}) {
        self.service = service; self.storage = storage; self.deviceID = deviceID; self.ownerID = ownerID
        self.transcribe = transcribe; self.assess = assess; self.changed = changed
    }
    public func start() {
        guard loop == nil, workers.isEmpty else { return }
        let token = UUID(); epoch = token; error = nil
        loop = Task { await run(token) }
    }
    public func stopAndWait() async {
        epoch = UUID()
        let task = loop, pending = Array(workers.values)
        task?.cancel(); for worker in pending { worker.cancel() }
        await task?.value; for worker in pending { await worker.value }
        workers = [:]; loop = nil
    }
    public func waitUntilIdle() async { await loop?.value }
    private func run(_ token: UUID) async {
        defer { if epoch == token { loop = nil } }
        do {
            try await service.recoverVoiceAnswers(deviceID: deviceID, ownerID: ownerID)
            await changed()
            while epoch == token, !Task.isCancelled {
                var claimed = false
                for stage in [VoiceWorkerStage.transcription, .transcription, .marking] {
                    try Task.checkCancellation(); guard epoch == token else { return }
                    do {
                        if let job = try await service.claimVoiceAnswer(stage: stage, deviceID: deviceID, ownerID: ownerID) {
                            claimed = true
                            let key = job.id + ":" + String(job.generation)
                            workers[key] = Task { await self.perform(job, stage: stage, token: token, key: key) }
                        }
                    } catch EngramError.conflict {
                        // Another result or ordinary UI edit committed during the
                        // repository await. Re-read next cycle; do not resend audio.
                        claimed = true
                    }
                }
                if !claimed && workers.isEmpty { return }
                try await Task.sleep(for: .milliseconds(150))
            }
        } catch is CancellationError { }
        catch { if epoch == token { self.error = error.localizedDescription; await changed() } }
    }
    private func perform(_ job: VoiceAnswerJob, stage: VoiceWorkerStage, token: UUID, key: String) async {
        defer { workers[key] = nil }
        do {
            guard epoch == token else { return }
            if stage == .transcription {
                let recording = try await storage.read(job.recordingID)
                try Task.checkCancellation(); guard epoch == token else { return }
                let transcript = try await transcribe(job, recording)
                try Task.checkCancellation(); guard epoch == token else { return }
                try await persist(job, stage: stage) {
                    try await self.service.storeVoiceTranscript(id: job.id, generation: job.generation, deviceID: self.deviceID,
                        ownerID: self.ownerID, text: transcript.text, usageJSON: transcript.usageJSON)
                }
                // Persisting the transcript precedes deletion. Cleanup failure is
                // reported independently; it must not retranscribe or erase text.
                do { try await storage.remove(job.recordingID) }
                catch { self.error = "Transcript saved, but its device recording could not be deleted. Retry recording cleanup." }
            } else {
                if let question = job.note.mcq {
                    guard let choice = question.ordered(for: job.attempt.presentationID).resolvePresented(job.attempt.originalAnswer) else {
                        throw EngramError.invalid("Check which option was spoken. No grade was saved.")
                    }
                    try Task.checkCancellation(); guard epoch == token else { return }
                    try await persist(job, stage: stage) {
                        try await self.service.commitVoiceAnswer(id: job.id, generation: job.generation, deviceID: self.deviceID, ownerID: self.ownerID, choiceID: choice)
                    }
                } else {
                    let assessment = try await assess(job)
                    try Task.checkCancellation(); guard epoch == token else { return }
                    try await persist(job, stage: stage) {
                        try await self.service.commitVoiceAnswer(id: job.id, generation: job.generation, deviceID: self.deviceID, ownerID: self.ownerID, assessment: assessment)
                    }
                }
            }
            guard epoch == token, !Task.isCancelled else { return }; await changed()
        } catch is CancellationError { }
        catch {
            guard epoch == token, !Task.isCancelled else { return }
            do {
                try await service.failVoiceAnswer(id: job.id, generation: job.generation, deviceID: deviceID, ownerID: ownerID, reason: error.localizedDescription)
            } catch { self.error = "This voice result was superseded or could not be saved. Your pending answer remains available." }
            await changed()
        }
    }
    /// Retry only a repository revision race, never an API operation or a stale
    /// lease. The exact same returned transcript/assessment is reused.
    private func persist(_ job: VoiceAnswerJob, stage: VoiceWorkerStage,
                         operation: () async throws -> Void) async throws {
        for retry in 0..<5 {
            do { try Task.checkCancellation(); try await operation(); return }
            catch EngramError.conflict {
                let snapshot = try await service.snapshot()
                let state: VoiceAnswerState = stage == .transcription ? .transcribing : .marking
                guard retry < 4, snapshot.voiceJobs?.contains(where: {
                    $0.id == job.id && $0.generation == job.generation && $0.state == state &&
                    $0.deviceID == deviceID && $0.ownerID == ownerID
                }) == true else { throw EngramError.conflict }
                try await Task.sleep(for: .milliseconds(20 * (retry + 1)))
            }
        }
    }
}
