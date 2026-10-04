import SwiftUI
import LearningCore
import DesignSystem

struct VoiceTranscriptConfirmationView: View {
    @Bindable var model: EngramModel
    let job: VoiceAnswerJob
    let confirmed: (AnswerAttempt) -> Void
    @State private var transcript = ""
    @State private var saving = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                RichContentView(source: job.attempt.prompt)
                Text("Check what you said").font(.headline)
                TextField("Your transcript", text: $transcript, axis: .vertical).textFieldStyle(.plain).lineLimit(3...10)
                Divider()
                Text("Correct recognition errors while preserving your original answer. Nothing is marked until you confirm.").font(.caption).engramSecondaryText()
                EngramActionButton("Confirm answer", busy: saving) {
                    Task {
                        saving = true
                        if let attempt = await model.voiceWork.confirm(job, text: transcript, model: model) { confirmed(attempt) }
                        saving = false
                    }
                }.disabled(saving || transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || transcript.utf8.count > 16_000)
                Button("Discard recording", role: .destructive) { Task { await model.voiceWork.cancel(job, model: model) } }.buttonStyle(.plain)
                if let error = model.voiceWork.error { Text(error).font(.caption).engramErrorText() }
            }.padding(24).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.onAppear { transcript = job.attempt.originalAnswer; model.voice.stop() }
    }
}
