import SwiftUI
import LearningCore
import DesignSystem

/// Kept available inside draft/review sheets to change presentation without leaving the workflow.
struct ThemeMenu: View {
    @Bindable var model: EngramModel
    var body: some View {
        Menu {
            Picker("Theme", selection: $model.theme) { ForEach(EngramTheme.allCases) { Text($0.title).tag($0) } }
            Picker("Appearance", selection: $model.appearance) { ForEach(EngramAppearance.allCases) { Text($0.title).tag($0) } }
        } label: { Label("Appearance", systemImage: "circle.lefthalf.filled") }
    }
}

struct SettingsView: View {
    @Bindable var model: EngramModel
    @Environment(\.dismiss) private var dismiss
    @State private var settings = StudySettings()
    @State private var changed = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $model.theme) { ForEach(EngramTheme.allCases) { Text($0.title).tag($0) } }
                    Picker("Appearance", selection: $model.appearance) { ForEach(EngramAppearance.allCases) { Text($0.title).tag($0) } }
                    Text("Theme and appearance are saved on this device. Text size, Reduce Motion, Reduce Transparency and Increase Contrast follow system accessibility settings.")
                }
                Section("Study day") {
                    Stepper("New cards per day: \(settings.newCardsPerDay)", value: $settings.newCardsPerDay, in: 0...10000)
                    Stepper("Reviews per day: \(settings.reviewsPerDay)", value: $settings.reviewsPerDay, in: 0...100000)
                    Stepper("Day begins at: \(settings.dayStartsAtHour):00", value: $settings.dayStartsAtHour, in: 0...23)
                    TextField("Time zone", text: $settings.timeZoneID)
                    Text("Daily limits are shared across decks. Short learning and relearning steps are not capped. Your saved time zone stays the same when travelling; change it deliberately here.")
                }
                Section("Scheduling") {
                    LabeledContent("Engine", value: "FSRS 6")
                    Slider(value: $settings.desiredRetention, in: 0.7...0.99, step: 0.01) {
                        Text("Desired retention")
                    }
                    LabeledContent("Desired retention", value: settings.desiredRetention.formatted(.percent.precision(.fractionLength(0))))
                    Text("Higher retention generally means more frequent reviews. Changes affect future ratings; existing due dates remain until the next review. Saving settings hides any currently revealed answer and refreshes interval previews.")
                }
                if let error = model.error { Section { EngramInlineError(message: error) } }
                Section {
                    Button(model.busy ? "Saving…" : "Save study settings") {
                        Task { if await model.perform({ try await $0.updateSettings(settings) }) { changed = false } }
                    }.disabled(model.busy || !changed)
                }
                Section("Your library") {
                    Text("Engram works offline with its local cards, media and saved reviews. This installation does not sync with your other devices. Create a complete backup before moving devices or removing the app.")
                    Text("Anki import/export and core study do not depend on paid AI. AI generation, voice tutoring and cloud sync are not included in this build.")
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(model.busy) } }
            .engramCanvas()
            .task { settings = model.library.settings; changed = false }
            .onChange(of: settings) { _, value in changed = value != model.library.settings }
        }
        .engramSheetSizing(idealWidth: 600, minimumHeight: 600)
        .interactiveDismissDisabled(model.busy)
    }
}
