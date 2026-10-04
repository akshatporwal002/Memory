import SwiftUI
import LearningCore
import DesignSystem

/// Results stay separate from the next answer: no unsolicited speech or focus changes.
struct VoiceAnswerHistoryView: View {
    @Bindable var model: EngramModel
    var body: some View {
        Form {
            let jobs = model.voiceWork.historyJobs(model)
            if jobs.isEmpty { Text("No voice answers for this account, device and library.").foregroundStyle(.secondary) }
            ForEach(jobs) { job in
                let gradeRemoved = job.state == .completed && model.library.corrections.contains { $0.reviewID == job.reviewID }
                EngramListSection {
                    Text(job.attempt.prompt).font(.headline)
                    LabeledContent("Status", value: gradeRemoved ? "Grade removed" : title(job.state))
                    if !job.attempt.originalAnswer.isEmpty { Text(job.attempt.originalAnswer) }
                    if let assessment = job.attempt.assessment {
                        LabeledContent(gradeRemoved ? "Previous result" : "Result", value: assessment.outcome.rawValue.capitalized)
                        RichContentView(source: assessment.reason)
                    }
                    if let error = job.error { Text(error).engramErrorText() }
                    if !model.voiceWork.canProcess(job, model: model), job.state.unresolved {
                        Text("The grading connection changed. Cancel this pending answer to release the card; it will not be sent through another connection.").font(.footnote).foregroundStyle(.secondary)
                    }
                    if (job.state.unresolved || job.state == .completed) && !gradeRemoved && model.voiceWork.canProcess(job, model: model) {
                        NavigationLink("Correct transcript") { VoiceTranscriptCorrectionView(model: model, job: job) }
                    }
                    if job.state.unresolved {
                        if job.state == .needsAttention, !job.attempt.originalAnswer.isEmpty, model.voiceWork.canProcess(job, model: model) {
                            Button("Retry marking") { Task { await model.voiceWork.retry(job, model: model) } }.disabled(model.busy)
                        }
                        Button("Cancel pending answer", role: .destructive) { Task { await model.voiceWork.cancel(job, model: model) } }.disabled(model.busy)
                    }
                    if job.state == .completed && !gradeRemoved { Text("Saved once at the original answer time.").font(.footnote).foregroundStyle(.secondary) }
                    if job.recordingCleanupPending == true {
                        Button("Remove saved recording") { Task { await model.voiceWork.cleanup(job, model: model) } }.disabled(model.busy)
                    }
                    if let revisions = job.transcriptRevisions, !revisions.isEmpty {
                        DisclosureGroup("Recognition history") {
                            ForEach(Array(revisions.enumerated()), id: \.offset) { index, text in
                                Text("\(index + 1). \(text)").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
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
                Text(job.state == .completed ? "Correct recognition errors, preserving your original mistakes. Saving removes the prior grade and recalculates due dates, then marks the corrected transcript at the original answer time. Later reviews remain in history." : "Correct recognition errors, preserving mistakes in your original answer. This replaces pending feedback.").font(.footnote).foregroundStyle(.secondary)
                Button("Save correction") { Task { await model.voiceWork.revise(job, text: text, model: model) } }
                    .disabled(model.busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.utf8.count > 16_000)
            }
            if let error = model.error { Text(error).engramErrorText() }
        }.modifier(UtilityListStyle()).navigationTitle("Transcript").onAppear { text = job.attempt.originalAnswer }
    }
}
