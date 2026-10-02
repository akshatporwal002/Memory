import SwiftUI
import DesignSystem
import LearningCore
import StudyApplication

struct StudyPreferencesPage: View {
    @Bindable var model: EngramModel
    let scheduling: Bool
    @State private var retention = 0.9
    private var settings: StudySettings { model.library.settings }
    var body: some View {
        Form {
            if scheduling {
                EngramListSection {
                    LabeledContent("Engine", value: "FSRS 6")
                    HStack { Text("Desired retention"); Spacer(); Text(retention, format: .percent.precision(.fractionLength(0))).engramSecondaryText().monospacedDigit() }
                    Slider(value: $retention, in: 0.7...0.99, step: 0.01) { editing in
                        if !editing { save(.retention(retention)) }
                    }.accessibilityLabel("Desired retention").accessibilityValue(retention.formatted(.percent))
                } footer: { Text("Higher retention means more frequent reviews. Existing due dates change after the next rating.") }
            } else {
                EngramListSection {
                    NavigationLink { DailyLimitPage(model: model, newCards: true) } label: { LabeledContent("New cards per day", value: String(settings.newCardsPerDay)) }
                    NavigationLink { DailyLimitPage(model: model, newCards: false) } label: { LabeledContent("Reviews per day", value: String(settings.reviewsPerDay)) }
                } header: { Text("Daily limits") } footer: { Text("Limits are shared across decks. Set a limit to zero to pause that type of study.") }
                EngramListSection {
                    Picker("Day begins", selection: Binding(get: { settings.dayStartsAtHour }, set: { save(.dayStarts($0)) })) {
                        ForEach(0..<24) { hour in Text(hourLabel(hour)).tag(hour) }
                    }
                    NavigationLink { TimeZonePage(model: model) } label: { LabeledContent("Time zone", value: settings.timeZoneID.replacingOccurrences(of: "_", with: " ")) }
                } header: { Text("Study day") } footer: { Text("Your saved time zone stays fixed while travelling. The day boundary controls when daily limits reset.") }
            }
            if let error = model.error { EngramListSection { Text(error).engramErrorText() } }
            if model.busy { EngramListSection { ProgressView("Saving…") } }
        }.modifier(UtilityListStyle()).navigationTitle(scheduling ? "Scheduling" : "Study")
            .disabled(model.busy).onAppear { retention = settings.desiredRetention }
    }
    private func save(_ preference: StudyPreference) {
        Task { if !(await model.perform({ try await $0.updatePreference(preference) })) { retention = settings.desiredRetention } }
    }
    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents(); components.year = 2026; components.month = 1; components.day = 1; components.hour = hour
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        let formatter = DateFormatter(); formatter.timeZone = .gmt; formatter.setLocalizedDateFormatFromTemplate("j")
        return calendar.date(from: components).map(formatter.string) ?? "\(hour):00"
    }
}

private struct DailyLimitPage: View {
    @Bindable var model: EngramModel
    let newCards: Bool
    @State private var text = ""
    @State private var validation: String?
    @FocusState private var focused: Bool
    private var current: Int { newCards ? model.library.settings.newCardsPerDay : model.library.settings.reviewsPerDay }
    private var maximum: Int { newCards ? 10_000 : 100_000 }
    var body: some View {
        Form {
            EngramListSection {
                TextField("Daily limit", text: $text).focused($focused)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .onSubmit { save() }.disabled(model.busy)
                Stepper("Adjust limit", value: Binding(get: { Int(text) ?? current }, set: { text = String($0); save() }), in: 0...maximum).disabled(model.busy)
            } footer: { Text("0–\(maximum.formatted()) per day. Changes save when you finish editing.") }
            if let validation { EngramListSection { Text(validation).engramErrorText() } }
            if let error = model.error { EngramListSection { Text(error).engramErrorText() } }
        }.modifier(UtilityListStyle()).navigationTitle(newCards ? "New Cards" : "Reviews")
            .onAppear { text = String(current) }
            .onChange(of: focused) { _, value in if !value { save() } }
            .onDisappear { save() }
            #if os(iOS)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } } }
            #endif
    }
    private func save() {
        guard let number = Int(text), (0...maximum).contains(number) else { validation = "Enter a whole number from 0 to \(maximum.formatted())."; return }
        validation = nil
        guard number != current, !model.busy else { return }
        Task { _ = await model.perform { try await $0.updatePreference(newCards ? .newCards(number) : .reviews(number)) } }
    }
}

private struct TimeZonePage: View {
    @Bindable var model: EngramModel
    @State private var search = ""
    var body: some View {
        List {
            EngramListSection {
                Button("Use current time zone (\(TimeZone.current.identifier))") { save(TimeZone.current.identifier) }
            }
            EngramListSection {
                ForEach(TimeZone.knownTimeZoneIdentifiers.filter { search.isEmpty || $0.replacingOccurrences(of: "_", with: " ").localizedCaseInsensitiveContains(search) }, id: \.self) { identifier in
                    Button { save(identifier) } label: {
                        HStack { Text(identifier.replacingOccurrences(of: "_", with: " ")).foregroundStyle(.primary); Spacer(); if model.library.settings.timeZoneID == identifier { Image(systemName: "checkmark").accessibilityLabel("Selected") } }
                    }
                }
            }
        }.modifier(UtilityListStyle()).navigationTitle("Time Zone").searchable(text: $search, prompt: "City or region").disabled(model.busy)
    }
    private func save(_ zone: String) { Task { _ = await model.perform { try await $0.updatePreference(.timeZone(zone)) } } }
}

struct AISettingsPage: View {
    @Bindable var model: EngramModel
    var body: some View {
        Form {
            EngramListSection { NavigationLink("Engram account") { CloudAccountView(model:model) } }
            EngramListSection("ChatGPT account") { ChatGPTConnectionView(connection: model.chatGPT) }
            EngramListSection {
                Toggle("AI answer marking", isOn: Binding(get: { model.aiMarker.enabled }, set: { model.aiMarker.enabled = $0 }))
            } footer: { Text("When enabled, spoken answer text and relevant deck passages are sent to OpenAI. Audio stays local. Multiple choice is marked on this device.") }
            EngramListSection {
                LabeledContent("Marking model", value: model.aiMarker.selectedModel.isEmpty ? "Default" : model.aiMarker.selectedModel)
                NavigationLink("Advanced model selection") {
                    Form {
                        EngramListSection {
                            Button("Refresh available models") { Task { await model.aiMarker.loadModels(connection: model.chatGPT) } }.disabled(model.aiMarker.loading)
                            if model.aiMarker.loading { ProgressView("Loading models…") }
                            if !model.aiMarker.models.isEmpty {
                                Picker("Grading model", selection: Binding(get: { model.aiMarker.selectedModel }, set: { model.aiMarker.selectedModel = $0 })) {
                                    ForEach(model.aiMarker.models, id: \.self) { Text($0).tag($0) }
                                }
                                Picker("PDF generation", selection: Binding(get: { model.aiMarker.pdfModel }, set: { model.aiMarker.pdfModel = $0 })) {
                                    ForEach(model.aiMarker.models, id: \.self) { Text($0).tag($0) }
                                }
                            }
                            if let error = model.aiMarker.error { Text(error).engramErrorText() }
                        } footer: { Text("Availability and usage limits depend on your connected ChatGPT plan.") }
                    }.modifier(UtilityListStyle()).navigationTitle("Marking Model")
                }
            }
        }.modifier(UtilityListStyle()).navigationTitle("AI & Connections")
    }
}

struct VoiceSettingsPage: View {
    @Bindable var model: EngramModel
    var body: some View {
        Form {
            EngramListSection { Toggle("Voice mode", isOn: Binding(get: { model.voice.enabled }, set: { model.voice.enabled = $0 })).disabled(!model.voice.ready || model.voice.preparing) }
            EngramListSection("Listening") {
                LabeledContent("Speech recognition", value: "Parakeet · on device")
                NavigationLink("Test microphone") { MicrophoneTestPage().onAppear { model.voice.enabled = false; model.voice.stopPreview() } }
            }
            EngramListSection("Speaking") {
                LabeledContent("Voice", value: "Kokoro · on device")
                Button(model.voice.previewing ? "Stop preview" : "Preview voice") { Task { await model.voice.preview() } }.disabled(!model.voice.ready || model.voice.preparing)
            }
            EngramListSection("Offline models") { VoiceDownloadRows(voice: model.voice) }
            EngramListSection {
                Text("Speak to interrupt. Answer multiple choice with a letter or the option text.")
                NavigationLink("AI answer marking") { AISettingsPage(model: model) }
            } footer: { Text("Keep Engram open during voice review. Screen-locked use has not been validated.") }
        }.modifier(UtilityListStyle()).navigationTitle("Voice").onDisappear { model.voice.stopPreview() }
    }
}

struct VoiceDownloadRows: View {
    @Bindable var voice: VoiceStudyController
    var body: some View {
        LabeledContent("Status", value: voice.ready ? "Ready" : voice.preparing ? "Preparing" : "Not loaded")
        if !voice.ready {
            Button(voice.preparing ? "Preparing models…" : "Download & prepare models") { Task { await voice.prepare() } }.disabled(voice.preparing)
        }
        if voice.preparing { ProgressView(voice.status) }
        if let error = voice.error { Text(error).engramErrorText().font(.subheadline) }
    }
}

struct StorageSettingsPage: View {
    @Bindable var model: EngramModel
    @State private var voiceBytes: Int64 = 0
    @State private var confirmRemoval = false
    var body: some View {
        Form {
            EngramListSection("Library") {
                LabeledContent("Cards", value: model.library.liveCards.count.formatted())
                LabeledContent("Media files", value: model.library.media.count.formatted())
                LabeledContent("Media size", value: ByteCountFormatter.string(fromByteCount: Int64(model.library.media.reduce(0) { $0 + $1.data.count }), countStyle: .file))
            }
            EngramListSection {
                LabeledContent("Downloaded files", value: ByteCountFormatter.string(fromByteCount: voiceBytes, countStyle: .file))
                VoiceDownloadRows(voice: model.voice)
                if voiceBytes > 0 {
                    Button("Remove offline voice models", role: .destructive) { confirmRemoval = true }
                        .disabled(model.voice.preparing || model.voice.previewing)
                }
            } header: { Text("Offline voice") } footer: { Text("Model downloads are stored on this device and shared by listening and speaking. File sizes exclude in-memory model data.") }
        }.modifier(UtilityListStyle()).navigationTitle("Storage & Downloads")
            .task(id: model.voice.preparing) {
                let bytes = await VoiceModelStorage.size()
                guard !Task.isCancelled else { return }
                voiceBytes = bytes
            }
            .confirmationDialog("Remove offline voice models?", isPresented: $confirmRemoval, titleVisibility: .visible) {
                Button("Remove models", role: .destructive) { Task { await model.voice.removeModels(); voiceBytes = await VoiceModelStorage.size() } }
            } message: { Text("Voice review will pause. Download the models again to use offline voice. Your cards and reviews stay saved.") }
    }
}
