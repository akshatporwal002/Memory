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
        var personalModel: String? {
            switch self { case .personalMini: "gpt-4o-mini-transcribe"; case .personalFull: "gpt-4o-transcribe"; default: nil }
        }
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
    var developmentPersonalPreview = false
    #endif
    @ObservationIgnored private var worker: VoiceWorkProcessor?
    @ObservationIgnored private var storage: VoiceRecordingStore?
    @ObservationIgnored private var scope: String?
    @ObservationIgnored private var foreground = true
    @ObservationIgnored private var preparationEpoch = UUID()
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
        developmentPersonalPreview = false
        #endif
        preferenceAccount = account
    }
    func jobs(_ model: EngramModel) -> [VoiceAnswerJob] {
        let owner = model.aiMarker.gradingIdentity(model.chatGPT)
        return (model.library.voiceJobs ?? []).filter { $0.deviceID == deviceID && $0.ownerID == owner }
            .sorted { $0.attempt.createdAt > $1.attempt.createdAt }
    }
    func historyJobs(_ model: EngramModel) -> [VoiceAnswerJob] {
        let account = model.aiMarker.personal.accountID, current = model.aiMarker.gradingIdentity(model.chatGPT)
        return (model.library.voiceJobs ?? []).filter { job in
            job.belongsToAppAccount(account, deviceID: deviceID, currentGradingIdentity: current)
        }.sorted { $0.attempt.createdAt > $1.attempt.createdAt }
    }
    func canProcess(_ job: VoiceAnswerJob, model: EngramModel) -> Bool { job.ownerID == model.aiMarker.gradingIdentity(model.chatGPT) }
    func advanceCompleted(_ job: VoiceAnswerJob, model: EngramModel) async {
        _ = await model.perform { try await $0.advanceCompletedVoiceAnswer(id: job.id, deviceID: self.deviceID, ownerID: job.ownerID) }
    }
    func revise(_ job: VoiceAnswerJob, text: String, model: EngramModel) async {
        guard let current = jobs(model).first(where: { $0.id == job.id }), current.state != .cancelled else { return }
        if await model.perform({ service in
            if current.state == .completed { try await service.correctCompletedVoiceTranscript(id: job.id, deviceID: self.deviceID, ownerID: job.ownerID, text: text) }
            else { try await service.correctPendingVoiceTranscript(id: job.id, deviceID: self.deviceID, ownerID: job.ownerID, text: text) }
        }) {
            await worker?.start()
        }
    }
    func retry(_ job: VoiceAnswerJob, model: EngramModel) async {
        guard jobs(model).contains(where: { $0.id == job.id }) else { return }
        do {
            try await prepare(model: model)
            if job.attempt.originalAnswer.isEmpty {
                guard job.provider == "openai", job.billingPath == .personalKey else { throw EngramError.invalid("This audio provider is not configured.") }
                try authorizePersonal(model, operationID: job.id, transcriptionModel: job.transcriptionModel)
            }
            if await model.perform({ try await $0.retryVoiceAnswer(id: job.id, deviceID: self.deviceID, ownerID: job.ownerID) }) { await worker?.start() }
        } catch { self.error = error.localizedDescription }
    }
    func cancel(_ job: VoiceAnswerJob, model: EngramModel) async {
        guard historyJobs(model).contains(where: { $0.id == job.id && $0.state.unresolved }) else { return }
        if await model.perform({ try await $0.cancelVoiceAnswer(id: job.id, deviceID: self.deviceID, ownerID: job.ownerID) }) {
            await cleanup(job, model: model)
        }
    }
    func cleanup(_ job: VoiceAnswerJob, model: EngramModel) async {
        let identity = currentScope(model)
        do {
            try await prepare(model: model)
            guard identity == currentScope(model), let storage,
                  let current = historyJobs(model).first(where: { $0.id == job.id }),
                  current.state == .cancelled || !current.attempt.originalAnswer.isEmpty else { throw EngramError.conflict }
            _ = await model.perform { service in
                try await storage.remove(current.recordingID)
                guard self.currentScope(model) == identity else { throw EngramError.conflict }
                try await service.acknowledgeVoiceRecordingDeletion(id: current.id, deviceID: self.deviceID, ownerID: current.ownerID)
            }
        } catch { if identity == currentScope(model) { self.error = error.localizedDescription } }
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
    var usesPersonalTranscription: Bool { selection.personalModel != nil }
    func captureAvailable(_ model: EngramModel) -> Bool {
        if let transcriptionModel = selection.personalModel { return (try? authorizePersonal(model, operationID: "personal-capture", transcriptionModel: transcriptionModel)) != nil }
        return localAvailable(model)
    }
    private func authorizePersonal(_ model: EngramModel, operationID: String, transcriptionModel: String) throws {
        guard foreground, ["gpt-4o-mini-transcribe", "gpt-4o-transcribe"].contains(transcriptionModel) else { throw EngramError.conflict }
        let account = model.aiMarker.personal.accountID
        #if DEBUG
        let policy = VoiceAccessPolicy(environment: .sandbox)
        let entitlement = developmentPersonalPreview ? VoiceEntitlement(accountID: account, environment: .sandbox, expiresAt: .distantFuture) : nil
        let disclosure = developmentPersonalPreview ? VoiceAudioDisclosure(accountID: account, provider: "openai", purpose: .transcription, revision: 1) : nil
        #else
        let policy = VoiceAccessPolicy(environment: .production)
        let entitlement: VoiceEntitlement? = nil
        let disclosure: VoiceAudioDisclosure? = nil
        #endif
        try policy.authorize(VoiceAccessRequest(accountID: account, operationID: operationID, provider: "openai",
            model: transcriptionModel, billingPath: .personalKey), entitlement: entitlement, disclosure: disclosure,
            keyAvailable: model.aiMarker.personal.configured.contains(.openai), reservation: nil)
    }
    func pause() async {
        foreground = false
        preparationEpoch = UUID()
        let active = worker; worker = nil; scope = nil; storage = nil
        await active?.stopAndWait()
    }
    func resume(model: EngramModel) async {
        foreground = true
        loadPreferences(model)
        do { try await prepare(model: model); await worker?.start() }
        catch EngramError.conflict { } // A newer lifecycle transition owns preparation.
        catch { self.error = error.localizedDescription }
    }
    private func prepare(model: EngramModel) async throws {
        let identity = currentScope(model)
        if scope == identity, worker != nil { return }
        let epoch = UUID(); preparationEpoch = epoch
        let previous = worker; worker = nil; scope = nil
        await previous?.stopAndWait()
        guard foreground, preparationEpoch == epoch, identity == currentScope(model) else { throw EngramError.conflict }
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        func component(_ value: String) -> String { Data(value.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "=", with: "") }
        let directory = root.appendingPathComponent("Engram/VoiceRecordings", isDirectory: true)
            .appendingPathComponent(component(model.aiMarker.personal.accountID), isDirectory: true)
            .appendingPathComponent(component(model.activeLibraryID), isDirectory: true)
        let recordingStore = try VoiceRecordingStore(directory: directory)
        _ = try await recordingStore.removeExpired()
        guard foreground, preparationEpoch == epoch, identity == currentScope(model) else { throw EngramError.conflict }
        storage = recordingStore; scope = identity
        let owner = model.aiMarker.gradingIdentity(model.chatGPT)
        worker = VoiceWorkProcessor(service: model.service, storage: recordingStore, deviceID: deviceID, ownerID: owner,
            authorize: { [weak self, weak model] job, stage in
                guard let self, let model else { throw EngramError.conflict }
                try await MainActor.run {
                    guard self.foreground, self.scope == identity,
                          self.currentScope(model) == identity, job.ownerID == owner else { throw EngramError.conflict }
                    if stage == .transcription {
                        guard job.provider == "openai", job.billingPath == .personalKey else { throw EngramError.invalid("This audio provider is not configured.") }
                        try self.authorizePersonal(model, operationID: job.id, transcriptionModel: job.transcriptionModel)
                    }
                }
            }, transcribe: { [weak self, weak model] job, audio in
                guard let self, let model else { throw EngramError.conflict }
                return try await self.transcribe(job, audio: audio, model: model, identity: identity)
            },
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
    private func transcribe(_ job: VoiceAnswerJob, audio: Data, model: EngramModel, identity: String) async throws -> VoiceTranscriptResult {
        guard foreground, scope == identity, currentScope(model) == identity,
              job.provider == "openai", job.billingPath == .personalKey else { throw EngramError.conflict }
        try authorizePersonal(model, operationID: job.id, transcriptionModel: job.transcriptionModel)
        let token = try model.aiMarker.personal.token(for: "openai")
        let result = try await OpenAISpeechProvider().transcribe(audio: audio, format: .wav,
            model: job.transcriptionModel, token: token, requestID: UUID())
        guard foreground, scope == identity, currentScope(model) == identity else { throw EngramError.conflict }
        return VoiceTranscriptResult(text: result.text, usageJSON: result.usageJSON)
    }
    func submitLocal(_ text: String, samples: [Float], model: EngramModel, sessionID: String, presentationID: String) async {
        await submit(text, samples: samples, model: model, sessionID: sessionID, presentationID: presentationID)
    }
    func submitRecording(samples: [Float], model: EngramModel, sessionID: String, presentationID: String) async {
        await submit(nil, samples: samples, model: model, sessionID: sessionID, presentationID: presentationID)
    }
    private func submit(_ text: String?, samples: [Float], model: EngramModel, sessionID: String, presentationID: String) async {
        guard !capturing else { return }
        capturing = true; error = nil; defer { capturing = false }
        let identity = currentScope(model), recordingID = UUID()
        var captured = false
        do {
            let personal = text == nil
            let transcriptionModel: String
            if personal {
                guard let selectedModel = selection.personalModel else { throw EngramError.conflict }
                transcriptionModel = selectedModel
                try authorizePersonal(model, operationID: recordingID.uuidString, transcriptionModel: selectedModel)
            } else { transcriptionModel = "parakeet"; try authorizeLocal(model) }
            try await prepare(model: model)
            guard let storage, let item = model.library.session?.current, item.presentationID == presentationID,
                  let note = model.library.liveNotes.first(where: { $0.id == item.card.noteID }) else { throw EngramError.conflict }
            try await storage.save(VoiceWAV.encode(samples), id: recordingID)
            do {
                try Task.checkCancellation(); guard foreground, identity == currentScope(model) else { throw EngramError.conflict }
                let prompt = try CardRenderer.render(note: note, card: item.card, revealed: false).prompt
                let evidence = LocalAnswerEvidence.retrieve(note: note, prompt: prompt, library: model.library)
                    .map { AttemptEvidence(id: $0.id, text: $0.text, version: $0.version) }
                let saved = try await model.service.captureVoiceAnswer(recordingID: recordingID, deviceID: deviceID,
                    ownerID: model.aiMarker.gradingIdentity(model.chatGPT), provider: personal ? "openai" : "local", transcriptionModel: transcriptionModel,
                    gradingModel: model.aiMarker.selectedModel, billingPath: personal ? .personalKey : .local, mode: mode,
                    sessionID: sessionID, presentationID: presentationID, evidence: evidence,
                    appAccountID: model.aiMarker.personal.accountID, localTranscript: text)
                captured = true
                // Recognition is already local and durably saved. Cleanup does
                // not repeat capture or erase the accepted transcript on failure.
                if !personal { do {
                    try await storage.remove(recordingID)
                    try await model.service.acknowledgeVoiceRecordingDeletion(id: saved.id, deviceID: deviceID, ownerID: saved.ownerID)
                }
                catch { self.error = "Answer saved, but its recording needs cleanup." } }
                await worker?.start(); await model.refresh()
            } catch {
                if !captured { try? await storage.remove(recordingID) }
                throw error
            }
        } catch { if identity == currentScope(model) { self.error = error.localizedDescription } }
    }
}
