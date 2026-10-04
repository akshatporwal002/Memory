import Foundation
import Observation
import AVFoundation
import FluidAudio
import LearningCore

@MainActor @Observable final class VoiceStudyController {
    var enabled = false { didSet { if !enabled { stop() } } }
    private(set) var ready = false
    private(set) var preparing = false
    private(set) var status = "Download models for offline voice review."
    private(set) var transcript = ""
    var error: String?
    private(set) var previewing = false
    @ObservationIgnored private var previewPlayer: AVAudioPlayer?
    @ObservationIgnored private var previewToken = UUID()
    func stopPreview() {
        previewToken = UUID(); previewPlayer?.stop(); previewPlayer = nil; previewing = false
    }
    func preview(model: EngramModel) async {
        if previewing { stopPreview(); return }
        guard ready, !preparing else { return }
        stop(); stopPreview()
        let token = previewToken; previewing = true; error = nil
        defer { if token == previewToken { previewing = false } }
        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            if model.voiceWork.output == .personalOpenAI {
                let data = try await model.voiceWork.speechAudio("Welcome to Engram. Let's review what you have learned today.", model: model)
                guard token == previewToken else { return }
                previewPlayer = try AVAudioPlayer(data: data); previewPlayer?.play()
                while previewPlayer?.isPlaying == true, token == previewToken {
                    try await Task.sleep(for: .milliseconds(100))
                }
                return
            }
            let result = try await tts.synthesizeDetailed(text: "Welcome to Engram. Let's review what you have learned today.")
            guard token == previewToken else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("engram-voice-preview-\(token).wav")
            defer { try? FileManager.default.removeItem(at: url) }
            let buffer = Self.pcm(result.samples, sampleRate: Double(result.sampleRate))
            do {
                let file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
                try file.write(from: buffer)
            }
            previewPlayer = try AVAudioPlayer(contentsOf: url); previewPlayer?.play()
            while previewPlayer?.isPlaying == true, token == previewToken {
                try await Task.sleep(for: .milliseconds(100))
            }
        } catch { if token == previewToken { self.error = error.localizedDescription } }
    }
    @ObservationIgnored private let asr = StreamingEouAsrManager(chunkSize: .ms320)
    @ObservationIgnored private let tts = KokoroAneManager()
    @ObservationIgnored private var vad: VadManager?
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var speechTask: Task<Void, Never>?
    @ObservationIgnored private var markingTask: Task<Void, Never>?
    @ObservationIgnored private var sink: AsyncStream<AVAudioPCMBuffer>.Continuation?
    @ObservationIgnored private var tapped = false
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var playbackID = UUID()
    @ObservationIgnored private var utteranceID = UUID()
    @ObservationIgnored private var prefix = ""
    @ObservationIgnored private var requestedEndpoint = false

    init() { engine.attach(player) }
    func prepare() async {
        guard !preparing else { return }; preparing = true; error = nil
        defer { preparing = false }
        do {
            status = "Loading Parakeet…"; saveDiagnostic("preparing-parakeet")
            try await asr.loadModels()
            status = "Loading speech detection…"; vad = try await VadManager()
            status = "Loading Kokoro…"; saveDiagnostic("preparing-kokoro")
            try await tts.initialize()
            _ = try await tts.synthesize(text: "Your offline study voice is ready.")
            ready = true; status = "Offline voice ready."; saveDiagnostic("ready")
        } catch { self.error = error.localizedDescription; status = "Voice setup interrupted. Retry to continue."; saveDiagnostic("error: " + error.localizedDescription) }
    }
    func removeModels() async {
        guard !preparing, !previewing else { return }
        enabled = false; stop(); stopPreview(); preparing = true; ready = false; error = nil
        defer { preparing = false }
        await asr.cleanup(); await tts.cleanup(); vad = nil
        do {
            try await VoiceModelStorage.remove()
            status = "Offline voice models removed."
        } catch { self.error = error.localizedDescription; status = "Some model files could not be removed." }
    }
    private func saveDiagnostic(_ value: String) {
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? value.write(to: directory.appendingPathComponent("voice-model-status.txt"), atomically: true, encoding: .utf8)
    }
    func stop() {
        generation = UUID(); utteranceID = UUID(); interrupt()
        task?.cancel(); task = nil; markingTask?.cancel(); markingTask = nil
        engine.stop(); if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        sink?.finish(); sink = nil; prefix = ""; requestedEndpoint = false
        status = ready ? "Voice paused." : "Download models for offline voice review."
    }
    private func interrupt() {
        playbackID = UUID(); speechTask?.cancel(); speechTask = nil; player.stop()
        markingTask?.cancel(); markingTask = nil
        status = "Listening…"
    }
    func present(model: EngramModel) {
        guard enabled, ready, !preparing else { return }
        guard model.voiceWork.captureAvailable(model), model.voiceWork.outputAvailable(model) else { stop(); error = "Configure voice access in Settings before starting voice review."; return }
        stop(); let token = generation
        task = Task { [weak self, weak model] in
            guard let self, let model else { return }
            do {
                try await self.listen(token: token, model: model)
            } catch {
                guard !Task.isCancelled, self.generation == token else { return }
                self.stop(); self.error = error.localizedDescription
            }
        }
    }
    private func speak(_ text: String, model: EngramModel) {
        let token = generation; let playback = UUID(); playbackID = playback
        speechTask?.cancel(); player.stop(); status = "Preparing speech…"
        speechTask = Task { [weak self, weak model] in
            guard let self, let model else { return }
            do {
                let buffer: AVAudioPCMBuffer
                if model.voiceWork.output == .personalOpenAI {
                    let audio = try await model.voiceWork.speechAudio(Self.plain(text), model: model)
                    buffer = try Self.decodeCloudAudio(audio)
                } else {
                    let result = try await self.tts.synthesizeDetailed(text: Self.plain(text))
                    buffer = Self.pcm(result.samples, sampleRate: Double(result.sampleRate))
                }
                try Task.checkCancellation()
                guard self.generation == token, self.playbackID == playback, self.engine.isRunning else { return }
                self.player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    Task { @MainActor in if self?.playbackID == playback { self?.status = "Listening…" } }
                }
                self.player.play(); self.status = "Speaking — you can interrupt."
            } catch {
                if !Task.isCancelled, self.generation == token, self.playbackID == playback { self.error = error.localizedDescription; self.status = "Listening…" }
            }
        }
    }
    private func questionText(_ model: EngramModel) throws -> String {
        guard let item = model.library.session?.current, let note = model.library.liveNotes.first(where: { $0.id == item.card.noteID }) else { return model.voiceWork.usesPersonalTranscription ? "Review complete." : "Review complete. Say stop to finish." }
        if model.voiceWork.usesPersonalTranscription {
            if let assessment = item.assessment { return assessment.outcome.rawValue + ". " + assessment.reason }
            if let mcq = note.mcq?.ordered(for: item.presentationID) { return mcq.prompt + ". " + mcq.choices.map { "Option \(mcq.displayLetter(for: $0.id)). \($0.text)" }.joined(separator: ". ") }
            let rendered = try CardRenderer.render(note: note, card: item.card, revealed: item.revealedAt != nil)
            return item.revealedAt == nil ? rendered.prompt : rendered.answer ?? ""
        }
        if let assessment = item.assessment { return assessment.outcome.rawValue + ". " + (note.mcq?.ordered(for: item.presentationID).displayedExplanation ?? assessment.reason) + ". Say next, repeat, or stop." }
        if let mcq = note.mcq?.ordered(for: item.presentationID) { return mcq.prompt + ". " + mcq.choices.map { "Option \(mcq.displayLetter(for: $0.id)). \($0.text)" }.joined(separator: ". ") + ". Say the option letter or answer." }
        let rendered = try CardRenderer.render(note: note, card: item.card, revealed: item.revealedAt != nil)
        return item.revealedAt == nil ? rendered.prompt + ". Please answer." : (rendered.answer ?? "") + ". Say got it or try again to rate your recall."
    }
    private func listen(token: UUID, model: EngramModel) async throws {
        #if os(iOS)
        let permitted = await withCheckedContinuation { continuation in AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) } }
        guard permitted else { throw EngramError.invalid("Enable microphone access in Settings.") }
        try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try AVAudioSession.sharedInstance().setActive(true)
        #else
        let permitted = await AVCaptureDevice.requestAccess(for: .audio)
        guard permitted else { throw EngramError.invalid("Enable microphone access in System Settings.") }
        #endif
        guard generation == token, !Task.isCancelled, let vad else { return }
        try engine.inputNode.setVoiceProcessingEnabled(true)
        let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
        engine.connect(player, to: engine.mainMixerNode, format: outputFormat)
        await asr.reset()
        let stream = AsyncStream<AVAudioPCMBuffer>(bufferingPolicy: .bufferingOldest(64)) { self.sink = $0 }
        let continuation = sink!, input = engine.inputNode, format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw EngramError.invalid("No microphone is available.") }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength), let src = buffer.floatChannelData, let dst = copy.floatChannelData else { return }
            copy.frameLength = buffer.frameLength
            for channel in 0..<Int(buffer.format.channelCount) { dst[channel].update(from: src[channel], count: Int(buffer.frameLength)) }
            if case .dropped = continuation.yield(copy) { continuation.finish() }
        }
        tapped = true; engine.prepare(); try engine.start()
        let converter = AudioConverter(sampleRate: 16000)
        var state = VadStreamState.initial(), pending: [Float] = [], preRoll: [Float] = []
        var answering = false
        let personalTranscription = model.voiceWork.usesPersonalTranscription
        var utteranceAudio: [Float] = []
        speak(try questionText(model), model: model)
        for await incoming in stream {
            try Task.checkCancellation(); guard generation == token else { return }
            pending += try converter.resampleBuffer(incoming)
            while pending.count >= VadManager.chunkSize {
                let samples = Array(pending.prefix(VadManager.chunkSize)); pending.removeFirst(VadManager.chunkSize)
                let detection = try await vad.processStreamingChunk(samples, state: state, config: VadSegmentationConfig(minSilenceDuration: 1.0))
                state = detection.state
                if detection.event?.isStart == true {
                    interrupt(); utteranceID = UUID(); model.answerFeedback = nil
                    utteranceAudio = preRoll
                    requestedEndpoint = false; await asr.reset(); answering = true
                    let currentUtterance = utteranceID
                    if !personalTranscription { await asr.setPartialCallback { [weak self] text in
                        Task { @MainActor in
                            guard let self, self.generation == token, self.utteranceID == currentUtterance else { return }
                            self.transcript = text
                            let words = text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                            if words.last == "done" { self.requestedEndpoint = true }
                        }
                    }
                    if !preRoll.isEmpty { _ = try await asr.process(audioBuffer: Self.pcm(preRoll)) } }
                }
                if answering {
                    guard utteranceAudio.count + samples.count <= 16000 * 120 else { throw EngramError.invalid("This voice answer is too long. Keep recordings under two minutes.") }
                    utteranceAudio += samples
                    if !personalTranscription { _ = try await asr.process(audioBuffer: Self.pcm(samples)) }
                }
                preRoll = samples
                if answering, detection.event?.isEnd == true || requestedEndpoint {
                    answering = false
                    requestedEndpoint = false
                    let recognized: String
                    if personalTranscription { recognized = "" }
                    else { recognized = try await asr.finish() }
                    let text = (prefix + " " + recognized).trimmingCharacters(in: .whitespacesAndNewlines); prefix = ""; transcript = text
                    guard personalTranscription || !text.isEmpty else { continue }
                    let turn = utteranceID
                    let recording = utteranceAudio; utteranceAudio = []
                    markingTask = Task { [weak self, weak model] in
                        guard let self, let model else { return }
                        await self.respond(text, samples: recording, model: model, token: token, turn: turn)
                    }
                }
            }
        }
        if generation == token { throw EngramError.invalid("Audio processing could not keep up. Please restart voice mode.") }
    }
    private func respond(_ text: String, samples: [Float], model: EngramModel, token: UUID, turn: UUID) async {
        guard generation == token, utteranceID == turn else { return }
        if model.voiceWork.usesPersonalTranscription {
            guard let session = model.library.session, let item = session.current,
                  item.assessment == nil, item.revealedAt == nil else { return }
            // Local recognition must not rewrite or classify a cloud answer.
            // Use onscreen pause/repeat/Next controls in this development path.
            status = "Saving recording…"
            await model.voiceWork.submitRecording(samples: samples, model: model, sessionID: session.id, presentationID: item.presentationID)
            guard !Task.isCancelled, generation == token, utteranceID == turn else { return }
            if let error = model.voiceWork.error { self.error = error; status = "Check pending answers." }
            else { status = model.voiceWork.mode == .continueProcessing ? "Answer saved." : "Waiting for feedback…" }
            return
        }
        let command = text.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        if ["stop", "pause"].contains(command) { enabled = false; return }
        if ["repeat", "repeat question", "repeat answer"].contains(command) { if let text = try? questionText(model) { speak(text, model: model) }; return }
        guard let session = model.library.session, let item = session.current else { return }
        if command == "explain" {
            guard item.assessment != nil || item.revealedAt != nil else { speak("Answer first, or say reveal answer for help.", model: model); return }
            if let note = model.library.liveNotes.first(where: { $0.id == item.card.noteID }) {
                let detail = note.mcq?.ordered(for: item.presentationID).displayedExplanation ?? (try? CardRenderer.render(note: note, card: item.card, revealed: true).answer) ?? ""
                speak(detail + ". Say next, repeat, or stop.", model: model)
            }
            return
        }
        if command == "next", item.assessment != nil { await model.nextAnswer(); return }
        if command == "skip" { if item.assessment != nil { await model.nextAnswer() } else { await model.skipAnswer() }; return }
        if item.assessment != nil { speak("Say next to continue, repeat for feedback, or stop.", model: model); return }
        if item.revealedAt != nil {
            if ["got it", "good", "great good", "grade good"].contains(command) { await model.grade(.good, sessionID: session.id, presentationID: item.presentationID) }
            else if ["try again", "again"].contains(command) { await model.grade(.again, sessionID: session.id, presentationID: item.presentationID) }
            else { speak("Say got it, try again, or stop.", model: model) }
            return
        }
        if ["reveal", "reveal answer"].contains(command) { await model.reveal(sessionID: session.id, presentationID: item.presentationID); return }
        status = "Checking your answer…"
        let answer = text.replacingOccurrences(of: "(?i)(?:^|\\s)done[.!?]*\\s*$", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { speak("Please say your answer, then done.", model: model); return }
        await model.voiceWork.submitLocal(answer, samples: samples, model: model, sessionID: session.id, presentationID: item.presentationID)
        guard !Task.isCancelled, generation == token, utteranceID == turn else { return }
        if let error = model.voiceWork.error { self.error = error; status = "Check pending answers." }
        else { status = model.voiceWork.mode == .continueProcessing ? "Answer saved." : "Waiting for feedback…" }
    }
    private static func decodeCloudAudio(_ audio: Data) throws -> AVAudioPCMBuffer {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("engram-speech-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        #if os(iOS)
        try audio.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try audio.write(to: url, options: .atomic)
        #endif
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard file.processingFormat.channelCount == 1, file.length > 0,
              file.length <= AVAudioFramePosition(file.processingFormat.sampleRate * 300),
              let decoded = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { throw EngramError.invalid("Unsupported speech audio.") }
        try file.read(into: decoded)
        let samples = try AudioConverter(sampleRate: 24000).resampleBuffer(decoded)
        guard !samples.isEmpty, samples.allSatisfy({ $0.isFinite }) else { throw EngramError.invalid("Unreadable speech audio.") }
        return pcm(samples, sampleRate: 24000)
    }
    private static func pcm(_ samples: [Float], sampleRate: Double = 16000) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!; buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { source in if let start = source.baseAddress { buffer.floatChannelData![0].update(from: start, count: source.count) } }
        return buffer
    }
    private static func plain(_ text: String) -> String { NotebookDocument.plainText(text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)) }
}
