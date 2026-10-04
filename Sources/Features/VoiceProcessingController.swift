import Foundation
import Observation
import LearningCore
import StudyApplication
import PersistenceAdapters
import AIInfrastructure

@MainActor @Observable final class VoiceProcessingController {
    enum Selection: String, CaseIterable, Identifiable {
        case managedMini, managedFull, managedChirp, personalMini, personalFull, localParakeet, localWhisper
        var id: String { rawValue }
        var title: String {
            switch self {
            case .managedMini: "Mini Transcribe · app credits"
            case .managedFull: "Transcribe · app credits"
            case .managedChirp: "Chirp 3 · app credits"
            case .personalMini: "Mini Transcribe · personal key"
            case .personalFull: "Transcribe · personal key"
            case .localParakeet: "Parakeet · on device"
            case .localWhisper: "Whisper · on device"
            }
        }
    }
    var selection: Selection = .managedMini { didSet { savePreferences() } }
    var mode: VoiceReviewMode = .continueProcessing { didSet { savePreferences() } }
    var summaryPresented = false
    var error: String?
    private(set) var capturing = false
    #if DEBUG
    var developmentLocalPreview = false
    #endif
    @ObservationIgnored private var worker: VoiceWorkProcessor?
    @ObservationIgnored private var storage: VoiceRecordingStore?
    @ObservationIgnored private var scope: String?
    @ObservationIgnored private var foreground = true
    private let deviceID: String
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var preferenceAccount: String?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let key = "engram.voice.deviceID"
        deviceID = defaults.string(forKey: key) ?? UUID().uuidString.lowercased()
        defaults.set(deviceID, forKey: key)
    }
    private func savePreferences() {
        guard let preferenceAccount else { return }
        defaults.set(selection.rawValue, forKey: "engram.voice.provider." + preferenceAccount)
        defaults.set(mode.rawValue, forKey: "engram.voice.mode." + preferenceAccount)
    }
    private func loadPreferences(_ model: EngramModel) {
        let account = model.aiMarker.personal.accountID
        guard preferenceAccount != account else { return }
        preferenceAccount = nil
        selection = defaults.string(forKey: "engram.voice.provider." + account).flatMap(Selection.init(rawValue:)) ?? .managedMini
        mode = defaults.string(forKey: "engram.voice.mode." + account).flatMap(VoiceReviewMode.init(rawValue:)) ?? .continueProcessing
        #if DEBUG
        developmentLocalPreview = false
        #endif
        preferenceAccount = account
    }
    func jobs(_ model: EngramModel) -> [VoiceAnswerJob] {
        let owner = model.aiMarker.gradingIdentity(model.chatGPT)
        return (model.library.voiceJobs ?? []).filter { $0.deviceID == deviceID && $0.ownerID == owner }
            .sorted { $0.attempt.createdAt > $1.attempt.createdAt }
    }
    func advanceCompleted(_ job: VoiceAnswerJob, model: EngramModel) async {
        _ = await model.perform { try await $0.advanceCompletedVoiceAnswer(id: job.id, deviceID: self.deviceID, ownerID: job.ownerID) }
    }
    func revise(_ job: VoiceAnswerJob, text: String, model: EngramModel) async {
        guard jobs(model).contains(where: { $0.id == job.id && $0.state.unresolved }) else { return }
        if await model.perform({ try await $0.correctPendingVoiceTranscript(id: job.id, deviceID: self.deviceID, ownerID: job.ownerID, text: text) }) {
            await worker?.start()
        }
    }
    func retry(_ job: VoiceAnswerJob, model: EngramModel) async {
        guard !job.attempt.originalAnswer.isEmpty, jobs(model).contains(where: { $0.id == job.id }) else { return }
        if await model.perform({ try await $0.retryVoiceAnswer(id: job.id, deviceID: self.deviceID, ownerID: job.ownerID) }) { await worker?.start() }
    }
    func cancel(_ job: VoiceAnswerJob, model: EngramModel) async {
        guard jobs(model).contains(where: { $0.id == job.id }) else { return }
        let recordingStore = storage
        if await model.perform({ try await $0.cancelVoiceAnswer(id: job.id, deviceID: self.deviceID, ownerID: job.ownerID) }) {
            do { try await recordingStore?.remove(job.recordingID) }
            catch { self.error = "Answer cancelled; its recording needs cleanup." }
        }
    }
    private func currentScope(_ model: EngramModel) -> String {
        model.aiMarker.gradingIdentity(model.chatGPT) + ":library:" + model.activeLibraryID
    }
    private func authorizeLocal(_ model: EngramModel) throws {
        guard foreground, selection == .localParakeet else { throw EngramError.invalid("The selected voice provider is not configured. Choose an available provider in Voice settings.") }
        let account = model.aiMarker.personal.accountID
        #if DEBUG
        let policy = VoiceAccessPolicy(environment: .sandbox)
        let entitlement = developmentLocalPreview ? VoiceEntitlement(accountID: account, environment: .sandbox, expiresAt: .distantFuture) : nil
        #else
        let policy = VoiceAccessPolicy(environment: .production)
        let entitlement: VoiceEntitlement? = nil
        #endif
        try policy.authorize(VoiceAccessRequest(accountID: account, operationID: "local-capture", provider: "local",
            model: "parakeet", billingPath: .local), entitlement: entitlement, disclosure: nil,
            keyAvailable: false, reservation: nil)
    }
    func localAvailable(_ model: EngramModel) -> Bool { (try? authorizeLocal(model)) != nil }
    func pause() async {
        foreground = false
        let active = worker; worker = nil; scope = nil; storage = nil
        await active?.stopAndWait()
    }
    func resume(model: EngramModel) async {
        foreground = true
        loadPreferences(model)
        do { try await prepare(model: model); await worker?.start() }
        catch { self.error = error.localizedDescription }
    }
    private func prepare(model: EngramModel) async throws {
        let identity = currentScope(model)
        if scope == identity, worker != nil { return }
        let previous = worker; worker = nil; scope = nil
        await previous?.stopAndWait()
        guard foreground, identity == currentScope(model) else { throw EngramError.conflict }
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        func component(_ value: String) -> String { Data(value.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "=", with: "") }
        let directory = root.appendingPathComponent("Engram/VoiceRecordings", isDirectory: true)
            .appendingPathComponent(component(model.aiMarker.personal.accountID), isDirectory: true)
            .appendingPathComponent(component(model.activeLibraryID), isDirectory: true)
        let recordingStore = try VoiceRecordingStore(directory: directory)
        _ = try await recordingStore.removeExpired()
        guard foreground, identity == currentScope(model) else { throw EngramError.conflict }
        storage = recordingStore; scope = identity
        let owner = model.aiMarker.gradingIdentity(model.chatGPT)
        worker = VoiceWorkProcessor(service: model.service, storage: recordingStore, deviceID: deviceID, ownerID: owner,
            authorize: { [weak self, weak model] job, stage in
                try await MainActor.run {
                    guard let self, let model, self.foreground, self.scope == identity,
                          self.currentScope(model) == identity, job.ownerID == owner else { throw EngramError.conflict }
                    if stage == .transcription { throw EngramError.invalid("Cloud transcription is not connected to recording yet. No audio was uploaded.") }
                }
            }, transcribe: { _, _ in throw EngramError.invalid("This audio provider is not configured.") },
            assess: { [weak self, weak model] job in
                guard let self, let model else { throw EngramError.conflict }
                return try await self.assess(job, model: model, identity: identity)
            }, changed: { [weak self, weak model] in
                guard let self, let model else { return }
                await self.changed(model: model, identity: identity)
            })
    }
    private func changed(model: EngramModel, identity: String) async {
        while model.busy && foreground && scope == identity { try? await Task.sleep(for: .milliseconds(50)); if Task.isCancelled { return } }
        guard foreground, scope == identity, currentScope(model) == identity else { return }
        await model.refresh()
    }
    private func assess(_ job: VoiceAnswerJob, model: EngramModel, identity: String) async throws -> AnswerAssessment {
        guard foreground, scope == identity, currentScope(model) == identity else { throw EngramError.conflict }
        let snapshot = try await model.service.snapshot()
        let result = try await model.aiMarker.assess(answer: job.attempt.originalAnswer, note: job.note,
            prompt: job.attempt.prompt, expected: job.attempt.expectedAnswer, library: snapshot, connection: model.chatGPT,
            modelID: job.attempt.modelID, capturedEvidence: job.attempt.evidence)
        guard foreground, scope == identity, currentScope(model) == identity else { throw EngramError.conflict }
        return result
    }
    func submitLocal(_ text: String, samples: [Float], model: EngramModel, sessionID: String, presentationID: String) async {
        guard !capturing else { return }
        capturing = true; error = nil; defer { capturing = false }
        let identity = currentScope(model), recordingID = UUID()
        var captured = false
        do {
            try authorizeLocal(model); try await prepare(model: model)
            guard let storage, let item = model.library.session?.current, item.presentationID == presentationID,
                  let note = model.library.liveNotes.first(where: { $0.id == item.card.noteID }) else { throw EngramError.conflict }
            try await storage.save(VoiceWAV.encode(samples), id: recordingID)
            do {
                try Task.checkCancellation(); guard foreground, identity == currentScope(model) else { throw EngramError.conflict }
                let prompt = try CardRenderer.render(note: note, card: item.card, revealed: false).prompt
                let evidence = LocalAnswerEvidence.retrieve(note: note, prompt: prompt, library: model.library)
                    .map { AttemptEvidence(id: $0.id, text: $0.text, version: $0.version) }
                _ = try await model.service.captureVoiceAnswer(recordingID: recordingID, deviceID: deviceID,
                    ownerID: model.aiMarker.gradingIdentity(model.chatGPT), provider: "local", transcriptionModel: "parakeet",
                    gradingModel: model.aiMarker.selectedModel, billingPath: .local, mode: mode,
                    sessionID: sessionID, presentationID: presentationID, evidence: evidence, localTranscript: text)
                captured = true
                // Recognition is already local and durably saved. Cleanup does
                // not repeat capture or erase the accepted transcript on failure.
                do { try await storage.remove(recordingID) }
                catch { self.error = "Answer saved, but its recording needs cleanup." }
                await worker?.start(); await model.refresh()
            } catch {
                if !captured { try? await storage.remove(recordingID) }
                throw error
            }
        } catch { if identity == currentScope(model) { self.error = error.localizedDescription } }
    }
}
