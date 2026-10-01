import SwiftUI
import DesignSystem
import Observation
import AVFoundation
#if os(iOS)
import UIKit
#endif

/// Diagnostic audio exists only in a temporary file and is discarded on exit.
@MainActor @Observable private final class MicrophoneCheck {
    private(set) var recording = false
    private(set) var level: Float = 0
    private(set) var hasRecording = false
    var error: String?
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var token = UUID()
    @ObservationIgnored private let url = FileManager.default.temporaryDirectory.appendingPathComponent("mic-check-\(UUID()).m4a")

    func start() async {
        stop(); hasRecording = false; error = nil
        let current = token
        #if os(iOS)
        let allowed = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        #else
        let allowed = await AVCaptureDevice.requestAccess(for: .audio)
        #endif
        guard current == token else { return }
        guard allowed else { error = "Allow microphone access in your device settings, then try again."; return }
        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1])
            recorder?.isMeteringEnabled = true
            guard recorder?.record(forDuration: 15) == true else { throw CocoaError(.fileWriteUnknown) }
            recording = true
            while current == token, recorder?.isRecording == true {
                recorder?.updateMeters(); level = pow(10, (recorder?.averagePower(forChannel: 0) ?? -160) / 20)
                try await Task.sleep(for: .milliseconds(100))
            }
            if current == token { stop() }
        } catch { if current == token { stop(); self.error = error.localizedDescription } }
    }
    func stop() { token = UUID(); recorder?.stop(); recording = false; level = 0; hasRecording = FileManager.default.fileExists(atPath: url.path) }
    func play() {
        do { player = try AVAudioPlayer(contentsOf: url); player?.play() }
        catch { self.error = error.localizedDescription }
    }
    func close() { stop(); player?.stop(); recorder = nil; player = nil; try? FileManager.default.removeItem(at: url); hasRecording = false }
}

struct MicrophoneTestPage: View {
    @State private var check = MicrophoneCheck()
    var body: some View {
        Form {
            EngramListSection {
                ProgressView(value: Double(check.level)).accessibilityLabel("Microphone level")
                Text(check.recording ? "Listening…" : "Record a short answer, then listen back.").engramSecondaryText()
                Button(check.recording ? "Stop recording" : "Record sample") {
                    if check.recording { check.stop() } else { Task { await check.start() } }
                }
                if check.hasRecording && !check.recording { Button("Play recording") { check.play() } }
            } footer: { Text("Up to 15 seconds. This checks your microphone and audio route; it does not transcribe or grade the recording. The sample is deleted when you leave.") }
            if let error = check.error { EngramListSection { Text(error).engramErrorText() } }
            #if os(iOS)
            EngramListSection { Link("Open device settings", destination: URL(string: UIApplication.openSettingsURLString)!) }
            #endif
        }.modifier(UtilityListStyle()).navigationTitle("Test Microphone").onDisappear { check.close() }
    }
}

/// Only vendor-owned cache directories are counted; the study library is excluded.
enum VoiceModelStorage {
    static func directories() -> [URL] {
        let manager = FileManager.default
        var roots: [URL] = []
        if let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            roots.append(support.appendingPathComponent("FluidAudio"))
            #if !os(macOS)
            roots.append(support.appendingPathComponent("fluidaudio"))
            #endif
        }
        if let cache = manager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            roots.append(cache.appendingPathComponent("fluidaudio"))
        }
        #if os(macOS)
        roots.append(manager.homeDirectoryForCurrentUser.appendingPathComponent(".cache/fluidaudio"))
        #endif
        return roots
    }
    static func size() async -> Int64 {
        await Task.detached(priority: .utility) {
            directories().reduce(Int64(0)) { total, root in
                guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return total }
                return total + files.compactMap { $0 as? URL }.reduce(Int64(0)) { bytes, file in
                    let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                    return bytes + (values?.isRegularFile == true ? Int64(values?.fileSize ?? 0) : 0)
                }
            }
        }.value
    }
    static func remove() async throws {
        try await Task.detached(priority: .utility) {
            for root in directories() where FileManager.default.fileExists(atPath: root.path) {
                try FileManager.default.removeItem(at: root)
            }
        }.value
    }
}
