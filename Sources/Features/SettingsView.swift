import SwiftUI
import LearningCore
import DesignSystem

struct ThemeMenu: View {
    @Bindable var model: EngramModel
    var body: some View {
        Menu {
            Picker("Theme", selection: $model.theme) { ForEach(EngramTheme.allCases) { Text($0.title).tag($0) } }
            Picker("Appearance", selection: $model.appearance) { ForEach(EngramAppearance.allCases) { Text($0.title).tag($0) } }
        } label: { Label("Appearance", systemImage: "circle.lefthalf.filled") }
    }
}

/// Shared native list presentation for utility screens, including dark mode and Dynamic Type.
struct UtilityListStyle: ViewModifier {
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let palette = theme.palette(for: scheme)
        #if os(iOS)
        content.listStyle(.insetGrouped).scrollContentBackground(.hidden)
            .foregroundStyle(palette.primaryText).font(theme.font(.body))
            .frame(maxWidth: EngramShape.readingWidth + EngramSpacing.section * 2).frame(maxWidth: .infinity)
            .tint(palette.accentInk).background(palette.canvas.ignoresSafeArea())
            .toolbar(.visible, for: .navigationBar)
        #else
        content.listStyle(.inset).formStyle(.grouped).scrollContentBackground(.hidden)
            .foregroundStyle(palette.primaryText).font(theme.font(.body))
            .frame(maxWidth: EngramShape.readingWidth + EngramSpacing.section * 2).frame(maxWidth: .infinity)
            .tint(palette.accentInk).background(palette.canvas.ignoresSafeArea())
        #endif
    }
}

private enum SettingsPage: String, CaseIterable, Identifiable {
    case appearance = "Appearance", study = "Study", scheduling = "Scheduling", voice = "Voice",
         ai = "AI & Connections", storage = "Storage & Downloads", backup = "Backup & Restore", about = "About & Help"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .appearance: "paintpalette.fill"
        case .study: "book.fill"
        case .scheduling: "calendar"
        case .voice: "waveform"
        case .ai: "sparkles"
        case .storage: "internaldrive.fill"
        case .backup: "arrow.triangle.2.circlepath"
        case .about: "info.circle.fill"
        }
    }
    var keywords: String {
        switch self {
        case .appearance: "theme dark light system text accessibility"
        case .study: "daily limits new cards reviews time zone day begins"
        case .scheduling: "fsrs retention memory"
        case .voice: "microphone listening speech speaking kokoro parakeet offline"
        case .ai: "chatgpt account sign in models marking consent"
        case .storage: "download size models media local"
        case .backup: "import export anki recovery sync"
        case .about: "help commands version acknowledgements license privacy"
        }
    }
}

struct SettingsView: View {
    @Bindable var model: EngramModel
    var embedded = false
    var portabilityAction: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var palette: EngramPalette { model.theme.palette(for: scheme) }
    @Environment(\.engramScreenshotAcknowledgements) private var captureAcknowledgements
    @State private var search = ""
    private var groups: [[SettingsPage]] {
        search.isEmpty ? [[.appearance], [.study, .scheduling], [.voice, .ai], [.storage, .backup], [.about]] : [SettingsPage.allCases]
    }

    var body: some View {
        EngramTaskContainer(embedded: embedded) {
            List {
                if search.isEmpty {
                    EngramListSection {
                        NavigationLink { AISettingsPage(model: model).engramInlineTitle() } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.chatGPT.activeAccount?.label ?? "Connect ChatGPT").font(.headline)
                                    Text(model.chatGPT.activeAccount == nil ? "Optional AI answer marking" : "Manage account and answer marking")
                                        .font(.subheadline).engramSecondaryText()
                                }.padding(.vertical, 6)
                            } icon: { Image(systemName: "person.crop.circle.fill").font(.largeTitle).foregroundStyle(palette.accentInk) }
                        }
                    }
                }
                ForEach(groups.indices, id: \.self) { index in
                  EngramListSection {
                    ForEach(groups[index].filter { page in
                        search.isEmpty || (page.rawValue + " " + page.keywords).localizedCaseInsensitiveContains(search)
                    }) { page in
                        NavigationLink { destination(page).engramInlineTitle() } label: {
                            HStack(spacing: 12) {
                                Image(systemName: page.symbol).font(.body.weight(.medium))
                                    .dynamicTypeSize(.large)
                                    .foregroundStyle(palette.primaryText).frame(width: 32, height: 32)
                                    .background(palette.selection, in: RoundedRectangle(cornerRadius: 8)).accessibilityHidden(true)
                                if typeSize.isAccessibilitySize {
                                    VStack(alignment: .leading, spacing: EngramSpacing.micro) {
                                        Text(page.rawValue)
                                        Text(summary(page)).engramSecondaryText().font(model.theme.font(.metadata))
                                    }
                                } else {
                                    Text(page.rawValue)
                                    Spacer()
                                    Text(summary(page)).engramSecondaryText().font(model.theme.font(.metadata))
                                }
                            }.padding(.vertical, 2)
                        }
                    }
                  } footer: { if search.isEmpty && index == groups.count - 1 { Text("Your library is stored on this device. Changes save automatically.") } }
                }
                if !search.isEmpty && !SettingsPage.allCases.contains(where: { ($0.rawValue + " " + $0.keywords).localizedCaseInsensitiveContains(search) }) {
                    ContentUnavailableView.search(text: search)
                }
            }
            .modifier(UtilityListStyle())
            .searchable(text: $search, prompt: "Search Settings")
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .navigationDestination(isPresented: Binding(get: { captureAcknowledgements }, set: { _ in })) { AcknowledgementsPage() }
            .toolbar { if !embedded { ToolbarItem(placement: .confirmationAction) { Button("Done") { model.settingsPresented = false; dismiss() } } } }
        }.modifier(EngramTaskSizing(embedded: embedded, width: 680, height: 700))
    }

    private func summary(_ page: SettingsPage) -> String {
        switch page {
        case .appearance: model.appearance.title
        case .study: "\(model.library.settings.newCardsPerDay) new/day"
        case .scheduling: model.library.settings.desiredRetention.formatted(.percent.precision(.fractionLength(0)))
        case .voice: model.voice.enabled ? "On" : "Off"
        case .ai: model.aiMarker.enabled ? "Marking on" : "Off"
        case .storage: model.voice.ready ? "Voice ready" : "On device"
        case .backup: model.lastBackupExport == nil ? "Not exported" : "Exported"
        case .about: "Engram"
        }
    }
    @ViewBuilder private func destination(_ page: SettingsPage) -> some View {
        switch page {
        case .appearance:
            Form {
                EngramListSection {
                    Picker("Appearance", selection: $model.appearance) { ForEach(EngramAppearance.allCases) { Text($0.title).tag($0) } }
                    Picker("Theme", selection: $model.theme) { ForEach(EngramTheme.allCases) { Text($0.title).tag($0) } }
                }
                EngramListSection { Text("Text size, Reduce Motion and contrast follow your system accessibility settings.").engramSecondaryText() }
            }.modifier(UtilityListStyle()).navigationTitle(page.rawValue)
        case .study: StudyPreferencesPage(model: model, scheduling: false)
        case .scheduling: StudyPreferencesPage(model: model, scheduling: true)
        case .voice: VoiceSettingsPage(model: model)
        case .ai: AISettingsPage(model: model)
        case .storage: StorageSettingsPage(model: model)
        case .backup:
            Form {
                EngramListSection {
                    if let date = model.lastBackupExport { LabeledContent("Last backup export", value: date.formatted(date: .abbreviated, time: .shortened)) }
                    else { Text("No complete backup has been exported from this installation.").engramSecondaryText() }
                    if let portabilityAction { Button("Import, export & recovery backups", action: portabilityAction) }
                } footer: { Text("Complete backups include cards, media and review history. Save a copy outside the app before changing devices or removing Engram.") }
                EngramListSection { LabeledContent("Cloud sync", value: "Unavailable") } footer: { Text("This library stays on this device. A ChatGPT connection does not sync it.") }
            }.modifier(UtilityListStyle()).navigationTitle(page.rawValue)
        case .about:
            Form {
                EngramListSection {
                    LabeledContent("App", value: "Engram")
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")
                    NavigationLink("Open-source acknowledgements") { AcknowledgementsPage() }
                    Link("Source code", destination: URL(string: "https://github.com/akshatporwal002/Memory")!)
                }
                EngramListSection("Voice commands") {
                    Text("For multiple choice, say the letter or answer. Say “next”, “repeat”, “skip”, “explain” or “stop”.")
                    Text("Short answers can use optional AI marking. Core study and multiple-choice marking work offline.")
                }
                EngramListSection("Privacy") { Text("Offline voice audio stays on this device. Enabling AI marking sends the answer text and relevant deck passages to OpenAI.") }
            }.modifier(UtilityListStyle()).navigationTitle(page.rawValue)
        }
    }
}

private struct AcknowledgementsPage: View {
    var body: some View {
        ScrollView { Text(text).textSelection(.enabled).frame(maxWidth: 720, alignment: .leading).padding() }
            .navigationTitle("Acknowledgements")
    }
    private var text: String {
        Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "See the source distribution for dependency licenses."
    }
}
