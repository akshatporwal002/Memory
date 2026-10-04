import SwiftUI
import AIInfrastructure
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
            if !scheduling {
                EngramListSection {
                    Toggle("Daily review reminder", isOn: Binding(get: { model.reminders.enabled }, set: { model.reminders.enabled = $0 }))
                        .accessibilityIdentifier("daily-review-reminder")
                    if model.reminders.enabled {
                        DatePicker("Reminder time", selection: Binding(get: { model.reminders.time }, set: { model.reminders.time = $0 }), displayedComponents: .hourAndMinute)
                        if let status = model.reminders.status { Text(status).font(.caption).engramSecondaryText() }
                    }
                } header: { Text("Reminders") } footer: { Text("At most one notification per day, at this device’s local time. This is a daily invitation to study, even if no cards are due. Turning it off cancels future reminders.") }
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
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @State private var search = ""
    var body: some View {
        List {
            EngramListSection {
                Button("Use current time zone (\(TimeZone.current.identifier))") { save(TimeZone.current.identifier) }
            }
            EngramListSection {
                ForEach(TimeZone.knownTimeZoneIdentifiers.filter { search.isEmpty || $0.replacingOccurrences(of: "_", with: " ").localizedCaseInsensitiveContains(search) }, id: \.self) { identifier in
                    Button { save(identifier) } label: {
                        HStack { Text(identifier.replacingOccurrences(of: "_", with: " ")).foregroundStyle(theme.palette(for: scheme).primaryText); Spacer(); if model.library.settings.timeZoneID == identifier { Image(systemName: "checkmark").foregroundStyle(theme.palette(for: scheme).answerSelectionInk).accessibilityLabel("Selected") } }
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
        List {
            AccountSettingsRows(model: model)
            EngramListSection {
                ForEach(PersonalAIProvider.allCases, id: \.rawValue) { provider in
                    NavigationLink { PersonalAPIKeySettings(model: model, provider: provider) } label: {
                        HStack { Text(provider.title); Spacer(); Text(model.aiMarker.personal.configured.contains(provider) ? "Connected" : "Add key").font(.caption).engramSecondaryText() }
                    }.accessibilityIdentifier("personal-provider-" + provider.rawValue)
                }
            } header: { Text("Personal API keys") }
            EngramListSection { NavigationLink("Learning memory") { LearningMemoryView(model:model) } }
            EngramListSection {
                Toggle("AI answer marking", isOn: Binding(get: { model.aiMarker.enabled }, set: { model.aiMarker.enabled = $0 }))
            } footer: { Text("Answer text and relevant evidence are sent to your selected grading provider. Multiple choice is marked on this device. Audio stays local until a cloud voice service is explicitly configured.") }
            EngramListSection {
                LabeledContent("Marking model", value: model.aiMarker.selectedModel.isEmpty ? "Default" : model.aiMarker.selectedModel)
                NavigationLink("Advanced model selection") {
                    Form {
                        EngramListSection {
                            Button("Refresh available models") { Task { await model.aiMarker.loadModels(connection: model.chatGPT) } }.disabled(model.aiMarker.loading)
                            if model.aiMarker.loading { ProgressView("Loading models…") }
                            if !model.aiMarker.models.isEmpty {
                                Picker("Grading model", selection: Binding(get: { model.aiMarker.selectedModel }, set: { model.aiMarker.selectedModel = $0 })) {
                                    ForEach(model.aiMarker.models, id: \.self) { Text(model.aiMarker.title(for:$0)).tag($0) }
                                }
                                Picker("PDF generation", selection: Binding(get: { model.aiMarker.pdfModel }, set: { model.aiMarker.pdfModel = $0 })) {
                                    ForEach(model.aiMarker.models, id: \.self) { Text(model.aiMarker.title(for:$0)).tag($0) }
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
    #if DEBUG
    @State private var confirmPersonalPreview = false
    @State private var confirmSpeechPreview = false
    #endif
    var body: some View {
        Form {
            EngramListSection { Toggle("Voice mode", isOn: Binding(get: { model.voice.enabled }, set: { model.voice.enabled = $0 })).disabled(!model.voice.ready || model.voice.preparing || !model.voiceWork.captureAvailable(model) || !model.voiceWork.outputAvailable(model)) }
            EngramListSection("Listening") {
                Picker("Speech recognition", selection: Binding(get: { model.voiceWork.selection }, set: { model.voiceWork.selection = $0 })) {
                    ForEach(VoiceProcessingController.Selection.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("Access", value: model.voiceWork.captureAvailable(model) ? "Development preview" : "Not configured")
                Picker("After answering", selection: Binding(get: { model.voiceWork.mode }, set: { model.voiceWork.mode = $0 })) {
                    Text("Continue while processing").tag(VoiceReviewMode.continueProcessing)
                    Text("Wait for feedback").tag(VoiceReviewMode.waitForFeedback)
                }
                #if DEBUG
                Toggle("Enable local development preview", isOn: Binding(get: { model.voiceWork.developmentLocalPreview }, set: { model.voiceWork.developmentLocalPreview = $0 }))
                Text("Preview uses on-device recognition. AI marking uses your selected AI connection; provider charges may apply. Production voice access is not configured.").font(.footnote).foregroundStyle(.secondary)
                if model.voiceWork.usesPersonalTranscription {
                    Toggle("Personal-key development preview", isOn: Binding(get: { model.voiceWork.developmentPersonalPreview }, set: { value in
                        if value { confirmPersonalPreview = true } else { model.voiceWork.developmentPersonalPreview = false }
                    })).disabled(!model.aiMarker.personal.configured.contains(.openai))
                    Text("Recordings are sent to OpenAI using your device's key. OpenAI bills your account; no app credits are used. Pause, repeat and Next use onscreen controls in this preview.").font(.footnote).foregroundStyle(.secondary)
                }
                #endif
                NavigationLink("Pending answers & results") { VoiceAnswerHistoryView(model: model) }
                NavigationLink("Test microphone") { MicrophoneTestPage().onAppear { model.voice.enabled = false; model.voice.stopPreview() } }
            }
            EngramListSection("Speaking") {
                Picker("Speech output", selection: Binding(get: { model.voiceWork.output }, set: { model.voiceWork.output = $0 })) {
                    ForEach(VoiceProcessingController.Output.allCases) { Text($0.title).tag($0) }
                }
                if model.voiceWork.output == .personalOpenAI {
                    Picker("Speech model", selection: Binding(get: { model.voiceWork.outputModel }, set: { model.voiceWork.outputModel = $0 })) {
                        ForEach(OpenAISpeechProvider.outputModels, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Voice", selection: Binding(get: { model.voiceWork.outputVoice }, set: { model.voiceWork.outputVoice = $0 })) {
                        ForEach(OpenAISpeechProvider.voices, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    if model.voiceWork.outputModel != "gpt-4o-mini-tts" {
                        Text("Older speech models support Alloy, Echo, Fable, Onyx, Nova and Shimmer.").font(.footnote).foregroundStyle(.secondary)
                    }
                    LabeledContent("Access", value: model.voiceWork.outputAvailable(model) ? "Development preview" : "Not configured")
                    #if DEBUG
                    Toggle("Cloud speech development preview", isOn: Binding(get: { model.voiceWork.developmentSpeechPreview }, set: { value in
                        if value { confirmSpeechPreview = true } else { model.voiceWork.developmentSpeechPreview = false }
                    })).disabled(!model.aiMarker.personal.configured.contains(.openai))
                    #endif
                    Text("AI-generated voice. Question and feedback text is sent to OpenAI; your personal key pays for speech generation, separately from transcription. No app credits are used.").font(.footnote).foregroundStyle(.secondary)
                }
                Button(model.voice.previewing ? "Stop preview" : "Preview voice") { Task { await model.voice.preview(model: model) } }.disabled(!model.voice.ready || model.voice.preparing || !model.voiceWork.outputAvailable(model))
            }
            EngramListSection("Offline models") { VoiceDownloadRows(voice: model.voice) }
            EngramListSection {
                Text("Speak to interrupt. Answer multiple choice with a letter or the option text.")
                NavigationLink("AI answer marking") { AISettingsPage(model: model) }
            } footer: { Text("Keep Engram open during voice review. Screen-locked use has not been validated.") }
            if let error = model.voiceWork.error { EngramListSection { Text(error).engramErrorText() } }
        }.modifier(UtilityListStyle()).navigationTitle("Voice").onDisappear { model.voice.stopPreview() }
            .onChange(of: model.voiceWork.selection) { _, _ in model.voice.enabled = false }
            .onChange(of: model.voiceWork.output) { _, _ in model.voice.enabled = false; model.voice.stopPreview() }
            .onChange(of: model.voiceWork.outputModel) { _, _ in model.voice.enabled = false; model.voice.stopPreview() }
            .onChange(of: model.voiceWork.outputVoice) { _, _ in model.voice.enabled = false; model.voice.stopPreview() }
            #if DEBUG
            .onChange(of: model.voiceWork.developmentLocalPreview) { _, _ in model.voice.enabled = false }
            .onChange(of: model.voiceWork.developmentPersonalPreview) { _, _ in model.voice.enabled = false }
            .onChange(of: model.voiceWork.developmentSpeechPreview) { _, _ in model.voice.enabled = false; model.voice.stopPreview() }
            .confirmationDialog("Send voice answers to OpenAI?", isPresented: $confirmPersonalPreview, titleVisibility: .visible) {
                Button("Enable personal-key preview") { model.voiceWork.developmentPersonalPreview = true }
                Button("Cancel", role: .cancel) { }
            } message: { Text("Your personal OpenAI account pays for transcription. Recordings leave this device; grading uses your separately selected model. Production subscriptions and managed credits are not enabled.") }
            .confirmationDialog("Generate speech with OpenAI?", isPresented: $confirmSpeechPreview, titleVisibility: .visible) {
                Button("Enable cloud speech preview") { model.voiceWork.developmentSpeechPreview = true }
                Button("Cancel", role: .cancel) { }
            } message: { Text("Question and feedback text leaves this device. Your personal OpenAI account pays for every speech request, including previews and repeats. Stopping a request may not avoid its provider charge. This is an AI-generated voice; no app credits are used.") }
            #endif
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
