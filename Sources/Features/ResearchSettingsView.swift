import SwiftUI
import DesignSystem

struct ResearchSettingsView: View {
    @Bindable var model: EngramModel
    @State private var deleting = false
    var body: some View {
        List {
            EngramListSection {
                Toggle("Share metrics and outcomes", isOn: Binding(get: { model.research.consent.metrics }, set: { value in Task { await model.research.update(metrics: value) } }))
                Text("Includes question types, grades, timing and AI usage. Answers and transcripts are excluded unless you separately enable them.").engramSecondaryText()
                Toggle("Share answer text and transcripts", isOn: Binding(get: { model.research.consent.answerContent }, set: { value in Task { await model.research.update(content: value) } }))
                    .disabled(!model.research.consent.metrics)
            } header: { Text("Learning research") } footer: { Text("Optional. Individual research records retain for up to 12 months. Tutor sharing is separate. Audio, credentials and full source documents are never collected here.") }
            EngramListSection {
                LabeledContent("Pending records", value: String(model.research.pendingCount))
                Text("Hosted collection is disabled until Engram's research schema is deployed and verified.").font(.caption).engramSecondaryText()
                Button("Delete research data on this device", role: .destructive) { deleting = true }
            }
            if let error = model.research.error { EngramListSection { Text(error).engramErrorText() } }
        }.modifier(UtilityListStyle()).navigationTitle("Research privacy")
        .task { await model.research.configure(model) }
        .confirmationDialog("Delete local research data?", isPresented: $deleting) {
            Button("Delete and turn off collection", role: .destructive) { Task { await model.research.deleteLocal() } }
        } message: { Text("Your notebooks and study history remain. This deletes only this device's research outbox. Hosted deletion is handled separately when collection is enabled.") }
    }
}
