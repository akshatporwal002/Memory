import SwiftUI
import LearningCore
import DesignSystem

struct ThemeMenu: View {
    @Bindable var model: EngramModel

    var body: some View {
        Menu {
            Picker("Theme", selection: $model.theme) {
                ForEach(EngramTheme.allCases) { Text($0.title).tag($0) }
            }
            Picker("Appearance", selection: $model.appearance) {
                ForEach(EngramAppearance.allCases) { Text($0.title).tag($0) }
            }
        } label: {
            Label("Appearance", systemImage: "circle.lefthalf.filled")
        }
    }
}

struct SettingsView: View {
    @Bindable var model: EngramModel
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var settings = StudySettings()
    @State private var changed = false
    @Environment(\.engramScreenshotAcknowledgements) private var captureAcknowledgements

    var body: some View {
        EngramTaskContainer(embedded: embedded) {
            ScrollView {
                VStack(alignment: .leading, spacing: EngramSpacing.regular) {
                    SettingsSection(title: "Appearance", subtitle: "Make Engram feel like yours. These choices are saved on this device.") {
                        SettingsField("Theme") {
                            Picker("Theme", selection: $model.theme) {
                                ForEach(EngramTheme.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden().pickerStyle(.menu)
                        }
                        SettingsField("Color appearance") {
                            Picker("Color appearance", selection: $model.appearance) {
                                ForEach(EngramAppearance.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden().pickerStyle(.menu)
                        }
                        SettingsHint(text: "Text size, Reduce Motion, Reduce Transparency and Increase Contrast follow your system accessibility settings.")
                    }

                    SettingsSection(title: "Study day", subtitle: "Set the rhythm for new cards and reviews. Limits are shared across decks.") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: EngramSpacing.regular) {
                            SettingsStepper(title: "New cards per day", value: $settings.newCardsPerDay, range: 0...10000)
                            SettingsStepper(title: "Reviews per day", value: $settings.reviewsPerDay, range: 0...100000)
                            SettingsStepper(title: "Day begins at", value: $settings.dayStartsAtHour, range: 0...23, suffix: ":00")
                        }
                        SettingsField("Time zone", helper: "Your saved time zone stays fixed while travelling; change it deliberately here.") {
                            TextField("Australia/Melbourne", text: $settings.timeZoneID).textFieldStyle(.roundedBorder)
                        }
                    }

                    SettingsSection(title: "Scheduling", subtitle: "Tune how often cards return as you build durable memory.") {
                        HStack {
                            Text("Engine").foregroundStyle(model.theme.palette(for: scheme).secondaryText)
                            Spacer()
                            Text("FSRS 6").font(model.theme.font(.control))
                        }
                        VStack(alignment: .leading, spacing: EngramSpacing.small) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Desired retention")
                                Spacer()
                                Text(settings.desiredRetention.formatted(.percent.precision(.fractionLength(0))))
                                    .font(model.theme.font(.control)).foregroundStyle(model.theme.palette(for: scheme).accentInk).monospacedDigit()
                            }
                            Slider(value: $settings.desiredRetention, in: 0.7...0.99, step: 0.01).tint(model.theme.palette(for: scheme).accentInk)
                            HStack { Text("70%"); Spacer(); Text("99%") }
                                .font(model.theme.font(.metadata)).foregroundStyle(model.theme.palette(for: scheme).secondaryText)
                        }
                        SettingsHint(text: "Higher retention generally means more frequent reviews. Changes affect future ratings; existing due dates remain until the next review.")
                    }

                    if let error = model.error { EngramInlineError(message: error) }

                    Button {
                        Task {
                            if await model.perform({ try await $0.updateSettings(settings) }) { changed = false }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if model.busy { ProgressView().controlSize(.small) }
                            Text(model.busy ? "Saving…" : "Save study settings")
                            Spacer()
                        }
                    }
                    .buttonStyle(EngramButtonStyle()).disabled(model.busy || !changed)

                    SettingsSection(title: "Your library", subtitle: "Engram works offline with your local cards, media and saved reviews.") {
                        Text("This installation does not sync with your other devices. Create a complete backup before moving devices or removing the app.")
                        Text("Anki import/export and core study do not depend on paid AI. AI generation, voice tutoring and cloud sync are not included in this build.")
                        NavigationLink {
                            acknowledgementsPage
                        } label: {
                            Label("Open-source acknowledgements", systemImage: "doc.text.magnifyingglass")
                        }.buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, EngramSpacing.page).padding(.vertical, EngramSpacing.section)
            }
            .scrollIndicators(.hidden).navigationTitle("Settings")
            .navigationDestination(isPresented: Binding(get: { captureAcknowledgements }, set: { _ in })) {
                acknowledgementsPage
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(changed ? "Save and close" : "Done") {
                Task {
                    let canClose = changed ? await model.perform({ try await $0.updateSettings(settings) }) : true
                    if canClose {
                        changed = false; model.settingsPresented = false; dismiss()
                    }
                }
            }.disabled(model.busy) } }
            .engramHideBack(changed)
            .engramCanvas()
            .task { settings = model.library.settings; changed = false }
            .onChange(of: settings) { _, value in changed = value != model.library.settings }
        }
        .modifier(EngramTaskSizing(embedded: embedded, width: 680, height: 640))
        .interactiveDismissDisabled(model.busy || changed)
    }

    private var acknowledgementsPage: some View {
        ScrollView {
            Text(acknowledgements).textSelection(.enabled)
                .frame(maxWidth: 720, alignment: .leading).padding(EngramSpacing.section)
        }.navigationTitle("Acknowledgements").engramCanvas()
    }

    private var acknowledgements: String {
        guard let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "Acknowledgements could not be loaded. The source distribution includes Vendor/FSRS/LICENSE and Sources/CArchive/LICENSE; SQLite is public domain."
        }
        return text
    }
}

private struct SettingsSection<Content: View>: View {
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: EngramSpacing.regular) {
            VStack(alignment: .leading, spacing: EngramSpacing.micro) {
                Text(title).font(theme.font(.section)).accessibilityAddTraits(.isHeader)
                Text(subtitle).font(theme.font(.metadata)).foregroundStyle(theme.palette(for: scheme).secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .engramSurface(padding: EngramSpacing.section)
    }
}

private struct SettingsField<Content: View>: View {
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    let title: String
    let helper: String?
    @ViewBuilder let content: () -> Content

    init(_ title: String, helper: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.helper = helper; self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: EngramSpacing.small) {
            Text(title).font(theme.font(.control))
            content().frame(maxWidth: .infinity, alignment: .leading)
            if let helper {
                Text(helper).font(theme.font(.metadata)).foregroundStyle(theme.palette(for: scheme).secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SettingsStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let suffix: String

    init(title: String, value: Binding<Int>, range: ClosedRange<Int>, suffix: String = "") {
        self.title = title; self._value = value; self.range = range; self.suffix = suffix
    }

    var body: some View {
        Stepper(value: $value, in: range) {
            VStack(alignment: .leading, spacing: EngramSpacing.micro) {
                Text(title)
                Text("\(value)\(suffix)").font(.system(.body, design: .rounded, weight: .semibold)).monospacedDigit()
            }.fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsHint: View {
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    let text: String

    var body: some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "info.circle") }
            .font(theme.font(.metadata)).foregroundStyle(theme.palette(for: scheme).secondaryText)
    }
}
