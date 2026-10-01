import SwiftUI
struct VoiceModeSettings: View {
    @Bindable var voice: VoiceStudyController
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Voice mode", isOn: $voice.enabled).disabled(!voice.ready || voice.preparing)
                .accessibilityIdentifier("voice-mode-toggle")
            Text(voice.status).font(.subheadline)
            if !voice.ready {
                Button(voice.preparing ? "Preparing models…" : "Download / load offline voice models") { Task { await voice.prepare() } }
                    .disabled(voice.preparing).buttonStyle(.bordered)
                if voice.preparing { ProgressView() }
            }
            if !voice.transcript.isEmpty { Text(voice.transcript).font(.subheadline) }
            Text("Interrupt by speaking. For MCQs, say an option letter or answer. Short answers use optional AI marking; enable it in ChatGPT settings. Say ‘next’, ‘repeat’, ‘skip’, ‘explain’, or ‘stop’. Audio stays on this device.").font(.caption).foregroundStyle(.secondary)
            Text("Keep the app open for this preview. Screen-locked and driving use have not been validated.").font(.caption).foregroundStyle(.secondary)
            if let error = voice.error { Text(error).foregroundStyle(.red).font(.subheadline) }
        }
    }
}
