import SwiftUI
import LearningCore
import DesignSystem

/// Results stay separate from the next answer: no unsolicited speech or focus changes.
struct VoiceAnswerHistoryView: View {
    @Bindable var model: EngramModel
    var body: some View {
        Form {
            let jobs = model.voiceWork.jobs(model)
            if jobs.isEmpty { Text("No voice answers for this connection and library.").foregroundStyle(.secondary) }
            ForEach(jobs) { job in
                EngramListSection {
                    Text(job.attempt.prompt).font(.headline)
                    LabeledContent("Status", value: title(job.state))
                    if !job.attempt.originalAnswer.isEmpty { Text(job.attempt.originalAnswer) }
                    if let assessment = job.attempt.assessment {
                        LabeledContent("Result", value: assessment.outcome.rawValue.capitalized)
                        RichContentView(source: assessment.reason)
                    }
                    if let error = job.error { Text(error).engramErrorText() }
                    if job.state.unresolved {
                        NavigationLink("Correct transcript") { VoiceTranscriptCorrectionView(model: model, job: job) }
                        if job.state == .needsAttention, !job.attempt.originalAnswer.isEmpty {
                            Button("Retry marking") { Task { await model.voiceWork.retry(job, model: model) } }.disabled(model.busy)
                        }
                        Button("Cancel pending answer", role: .destructive) { Task { await model.voiceWork.cancel(job, model: model) } }.disabled(model.busy)
                    }
                    if job.state == .completed { Text("Saved once at the original answer time.").font(.footnote).foregroundStyle(.secondary) }
                }
            }
        }.modifier(UtilityListStyle()).navigationTitle("Voice answers")
    }
    private func title(_ state: VoiceAnswerState) -> String {
        switch state {
        case .captured: "Saved"
        case .transcribing: "Transcribing"
        case .awaitingMarking: "Waiting for marking"
        case .marking: "Marking"
        case .completed: "Completed"
        case .needsAttention: "Needs attention"
        case .cancelled: "Cancelled"
        }
    }
}

private struct VoiceTranscriptCorrectionView: View {
    @Bindable var model: EngramModel
    let job: VoiceAnswerJob
    @State private var text = ""
    var body: some View {
        Form {
            EngramListSection { Text(job.attempt.prompt) }
            EngramListSection("What you actually said") {
                TextEditor(text: $text).frame(minHeight: 160)
                Text("Correct recognition errors, preserving mistakes in your original answer. This replaces pending feedback, not a completed grade.").font(.footnote).foregroundStyle(.secondary)
                Button("Save correction") { Task { await model.voiceWork.revise(job, text: text, model: model) } }
                    .disabled(model.busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.utf8.count > 16_000)
            }
            if let error = model.error { Text(error).engramErrorText() }
        }.modifier(UtilityListStyle()).navigationTitle("Transcript").onAppear { text = job.attempt.originalAnswer }
    }
}
