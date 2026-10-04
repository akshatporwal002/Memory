import SwiftUI
import DesignSystem
import AIInfrastructure

struct PersonalAPIKeySettings: View {
    @Bindable var model: EngramModel
    let provider: PersonalAIProvider
    @State private var draft = ""
    @State private var error: String?
    @State private var notice: String?
    @State private var confirmRemoval = false
    private var connections: PersonalAIConnections { model.aiMarker.personal }
    private var busy: Bool {
        connections.busy || model.assistant.busy || model.typedAnswer.busy || model.markingAnswer || model.pdfLearning.busy
    }
    var body: some View {
        List {
            EngramListSection {
                Text(connections.configured.contains(provider) ? "Key saved on this device" : "Not connected")
                    .font(.subheadline).accessibilityIdentifier("personal-key-status")
                SecureField("Paste API key", text: $draft)
                    .textContentType(.password).autocorrectionDisabled()
                    .accessibilityIdentifier("personal-key-input")
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                Button(connections.configured.contains(provider) ? "Validate and replace key" : "Validate and save key") {
                    Task {
                        error = nil; notice = nil
                        do {
                            try await connections.save(draft, provider: provider); draft = ""
                            model.aiMarker.invalidateCatalog()
                            await model.aiMarker.loadModels(connection: model.chatGPT)
                            notice = "Connected. Choose this provider's model in chat or AI settings."
                        } catch { self.error = error.localizedDescription }
                    }
                }.buttonStyle(EngramButtonStyle(.secondary)).disabled(draft.isEmpty || busy)
                    .accessibilityIdentifier("personal-key-save")
                if connections.configured.contains(provider) {
                    Button("Remove key", role: .destructive) { confirmRemoval = true }
                        .disabled(busy).accessibilityIdentifier("personal-key-remove")
                }
                if connections.busy { ProgressView("Checking provider access…") }
            } header: { Text(provider.title) } footer: {
                Text("Stored securely for this Engram profile on this device. Keys are excluded from backups and sync. Personal API requests are billed directly by your provider, separately from ChatGPT plan usage.")
            }
            if let notice { Text(notice).font(.caption).engramSecondaryText() }
            if let error { EngramInlineError(message: error) }
            EngramListSection {
                Text("Only requests using this provider's selected model send it your question and relevant evidence. Adding a key does not enable managed voice or app charges.")
                    .font(.caption).engramSecondaryText()
            }
        }.modifier(UtilityListStyle()).navigationTitle(provider.title)
            .onDisappear { draft = "" }
            .confirmationDialog("Remove this device's \(provider.title) key?", isPresented: $confirmRemoval) {
                Button("Remove key", role: .destructive) {
                    guard !busy else { error = "Wait for the current AI request to finish before removing its key."; return }
                    do {
                        try connections.remove(provider); draft = ""; notice = "Key removed."
                        model.aiMarker.invalidateCatalog()
                    } catch { self.error = error.localizedDescription }
                }
            } message: { Text("This removes Engram's saved key. Revoke it with your provider to invalidate it elsewhere. Your decks and answers remain saved.") }
    }
}
