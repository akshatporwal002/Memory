import SwiftUI
import LearningCore
import DesignSystem

public struct EngramRootView: View {
    @Bindable private var model: EngramModel
    private let portabilityAction: (() -> Void)?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme
    public init(model: EngramModel, portabilityAction: (() -> Void)? = nil) {
        self.model = model; self.portabilityAction = portabilityAction
    }
    public var body: some View {
        GeometryReader { geometry in
            Group {
                if geometry.size.width < 600 {
                    TabView(selection: $model.destination) {
                        ForEach(EngramDestination.allCases) { destination in
                            NavigationStack { page(destination) }
                                .tabItem { Label(destination.title, systemImage: destination.symbol) }
                                .tag(destination)
                        }
                    }
                } else {
                    NavigationSplitView {
                        List(selection: Binding<EngramDestination?>(get: { model.destination }, set: { if let value = $0 { model.destination = value } })) {
                            Section("Engram") {
                                ForEach(EngramDestination.allCases) { item in Label(item.title, systemImage: item.symbol).tag(item) }
                            }
                            Section("On this device") {
                                ForEach(model.library.liveDecks) { deck in
                                    Button { model.selectedDeckID = deck.id; model.destination = .library } label: {
                                        Label(deck.name, systemImage: "rectangle.stack")
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        .navigationTitle("Engram").navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
                    } detail: { NavigationStack { page(model.destination) } }
                }
            }
            .overlay { if !model.loaded && model.error == nil { ProgressView("Opening your library…").padding().engramSurface() } }
        }
        .engramCanvas()
        .sheet(isPresented: $model.editorPresented) { EditorView(model: model) }
        .sheet(isPresented: $model.reviewPresented) { ReviewView(model: model) }
        .sheet(isPresented: $model.settingsPresented) { SettingsView(model: model) }
        .sheet(item: $model.deckForm) { form in DeckFormView(model: model, form: form) }
        .confirmationDialog("Delete deck?", isPresented: Binding(get: { model.deleteDeck != nil }, set: { if !$0 { model.deleteDeck = nil } }), titleVisibility: .visible) {
            if let deck = model.deleteDeck {
                Button("Delete “\(deck.name)”", role: .destructive) {
                    Task { if await model.perform({ try await $0.deleteDeck(id: deck.id) }) { model.deleteDeck = nil } }
                }
            }
            Button("Cancel", role: .cancel) { model.deleteDeck = nil }
        } message: {
            Text("This removes the deck, its subdecks and their cards from study. Historical evidence remains in complete backups. This cannot be undone in the app.")
        }
        .confirmationDialog("Delete note and its cards?", isPresented: Binding(get: { model.deleteNote != nil }, set: { if !$0 { model.deleteNote = nil } }), titleVisibility: .visible) {
            if let note = model.deleteNote {
                Button("Delete note and all generated cards", role: .destructive) {
                    Task { if await model.perform({ try await $0.deleteNote(id: note.id) }) { model.deleteNote = nil } }
                }
            }
        } message: { Text("The note will leave your library and all its generated cards will stop appearing in study. History is retained in backups.") }
        .task {
            await model.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                await model.refresh()
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.refresh() } } }
        .environment(\.engramTheme, model.theme)
        .preferredColorScheme(model.appearance.colorScheme)
    }
    @ViewBuilder private func page(_ destination: EngramDestination) -> some View {
        VStack(spacing: 0) {
            if let error = model.error {
                HStack(alignment: .top) {
                    EngramInlineError(message: error)
                    Button { model.error = nil } label: { Image(systemName: "xmark.circle") }.accessibilityLabel("Dismiss error")
                }.padding(EngramSpacing.regular)
            }
            switch destination {
            case .today: TodayView(model: model)
            case .library: LibraryView(model: model)
            case .activity: ActivityView(model: model)
            }
        }
        .navigationTitle(destination.title)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if let portabilityAction { Button(action: portabilityAction) { Label("Import and export", systemImage: "square.and.arrow.up.on.square") } }
                Button { model.settingsPresented = true } label: { Label("Settings", systemImage: "gearshape") }
            }
        }
        .toolbarBackground(model.theme.palette(for: scheme).surface,
                           for: .automatic)
        .toolbarBackground(EngramNavigationPolicy.needsOpaqueChrome(reduceTransparency: reduceTransparency, increasedContrast: contrast == .increased) ? .visible : .automatic, for: .automatic)
        .engramCanvas()
    }
}

struct DeckFormView: View {
    @Bindable var model: EngramModel
    @State var form: DeckForm
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Deck name", text: $form.name).focused($focused) }
                footer: { Text("Use :: for nested decks, for example Biology::Plants.") }
                if let error = model.error { EngramInlineError(message: error) }
            }
            .navigationTitle(form.deckID == nil ? "New deck" : "Rename deck")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            let succeeded = await model.perform { service in
                                if let id = form.deckID { try await service.renameDeck(id: id, name: form.name) }
                                else { _ = try await service.createDeck(name: form.name) }
                            }
                            if succeeded { dismiss() }
                        }
                    }.disabled(model.busy || form.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .engramCanvas().task { focused = true }
        }
        .engramSheetSizing(idealWidth: 460, minimumHeight: 280)
        .interactiveDismissDisabled(model.busy)
    }
}
