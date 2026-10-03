import SwiftUI
import LearningCore
import DesignSystem
#if os(iOS)
import UIKit
#endif

public struct EngramRootView: View {
    @Bindable private var model: EngramModel
    private let portabilityAction: (() -> Void)?
    private let screenshotAction: (() -> Void)?
    private let capturingScreenshots: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme
    @State private var assistantDockHeight: CGFloat = 72
    private var usesPhoneTodayTitle: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }
    public init(model: EngramModel, portabilityAction: (() -> Void)? = nil, screenshotAction: (() -> Void)? = nil, capturingScreenshots: Bool = false) {
        self.model = model; self.portabilityAction = portabilityAction
        self.screenshotAction = screenshotAction; self.capturingScreenshots = capturingScreenshots
    }
    public var body: some View {
        GeometryReader { geometry in
            Group {
                // Keep the phone's navigation stack alive through rotation; tablet windows still adapt.
                if usesPhoneTodayTitle || geometry.size.width < 600 {
                    TabView(selection: $model.destination) {
                        ForEach(EngramDestination.allCases) { destination in
                            NavigationStack { page(destination) }.engramHideStudyTabs(!capturingScreenshots)
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

                        }
                        .navigationTitle("Engram").navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
                    } detail: { NavigationStack { page(model.destination) } }
                }
            }
            .environment(\.engramWorkspaceLayout, !usesPhoneTodayTitle && geometry.size.width >= 1100)
            .overlay { if !model.loaded && model.error == nil { ProgressView("Opening your library…").padding().engramSurface() } }
        }
        .engramCanvas()
        .engramCaptureSurface()
        .overlay(alignment: .bottomTrailing) {
            if model.loaded && !capturingScreenshots && !model.settingsPresented { ContextualAssistant(model: model) }
        }
        .task { await model.cloud.restore(model:model) }
        .onChange(of:model.chatGPT.activeClientID) { _,_ in
            model.assistant.cancel(); model.pdfLearning.cancel(); model.aiMarker.invalidateCatalog()
            Task { if model.chatGPT.activeClientID != nil { await model.aiMarker.loadModels(connection:model.chatGPT) } }
        }
        .onPreferenceChange(AssistantDockHeight.self) { assistantDockHeight = max(72, $0 + 12) }
        .sheet(item: $model.deckForm) { form in DeckFormView(model: model, form: form).engramCaptureSurface() }
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
        } message: {
            if let note = model.deleteNote {
                Text("Delete “\(note.front.prefix(120))” and all its generated cards? They will leave study; history is retained in complete backups.")
            }
        }
        .task {
            await model.refresh()
            guard !capturingScreenshots else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                await model.refresh()
                await model.cloud.sync(model:model)
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.refresh(); await model.cloud.sync(model:model) } } }
        .onChange(of:model.library.session?.current?.presentationID) { old,new in
            if old != nil,new != nil { Task { await model.cloud.sync(model:model,allowStudyBoundary:true) } }
        }
        .onChange(of: model.portabilityRequested) { _, value in
            if value { model.portabilityRequested = false; portabilityAction?() }
        }
        .sheet(isPresented: $model.actionReviewPresented) { AIActionReviewView(model: model) }
        .sheet(isPresented: $model.cloudAccountPresented) { NavigationStack { CloudAccountView(model:model) } }
        .sheet(isPresented:$model.memoryPresented) { NavigationStack { LearningMemoryView(model:model) } }
        .sheet(isPresented:Binding(get:{model.sharingDeckID != nil},set:{if !$0 { model.sharingDeckID = nil }})) {
            if let id = model.sharingDeckID { NavigationStack { DeckSharingView(model:model,deckID:id) } }
        }
        .onOpenURL { url in
            guard url.scheme == "engram",url.host == "join",let token = URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems?.first(where: { $0.name == "token" })?.value,
                  token.count == 64,token.allSatisfy({ $0.isHexDigit }) else { return }
            model.cloud.pendingJoinToken = token; model.cloudAccountPresented = true
        }
        .environment(\.engramTheme, model.theme)
        .environment(\.engramAssistantBottomInset, capturingScreenshots ? 0 : assistantDockHeight)
        .tint(scheme == .dark ? model.theme.palette(for: scheme).easyInk : model.theme.palette(for: scheme).anchor)
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
            case .today: TodayView(model: model, showsPageTitle: usesPhoneTodayTitle).engramAssistantClearance()
            case .library:
                #if os(iOS)
                LibraryExplorerView(model: model, importAction: portabilityAction).engramAssistantClearance()
                #else
                LibraryView(model: model, portabilityAction: portabilityAction)
                #endif
            case .activity: ActivityView(model: model).engramAssistantClearance()
            }
        }
        .navigationDestination(isPresented: Binding(get: { model.destination == destination && model.editorPresented }, set: { model.editorPresented = $0 })) {
            EditorView(model: model, embedded: true).engramAssistantClearance().engramCaptureSurface()
        }
        .navigationDestination(isPresented: Binding(get: { model.destination == destination && model.settingsPresented }, set: { model.settingsPresented = $0 })) {
            SettingsView(model: model, embedded: true, portabilityAction: portabilityAction, screenshotAction: screenshotAction).engramCaptureSurface()
        }
        .navigationDestination(isPresented: Binding(get: { model.destination == destination && model.creationPresented }, set: { model.creationPresented = $0 })) {
            NotebookCreationPage(model: model).engramAssistantClearance().engramCaptureSurface()
        }
        .navigationDestination(isPresented: Binding(get: { model.destination == destination && model.reviewPresented }, set: { model.reviewPresented = $0 })) {
            ReviewView(model: model, embedded: true).engramAssistantClearance().engramCaptureSurface()
        }
        .navigationDestination(item: Binding(get: { model.destination == destination ? model.notebookDeckID : nil }, set: { model.notebookDeckID = $0 })) { id in
            NotebookView(model: model, deckID: id, writingOnly: model.notebookWritingOnly).engramCaptureSurface()
        }
        .navigationDestination(item: Binding(get: { model.destination == destination ? model.questionsDeckID : nil }, set: { model.questionsDeckID = $0 })) { id in
            DeckQuestionsView(model: model, deckID: id).engramCaptureSurface()
        }
        .navigationTitle(usesPhoneTodayTitle && destination != .activity ? "" : destination.title)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
              if model.activeDeckOverviewID == nil && model.activeContentDeckID == nil && model.notebookDeckID == nil && model.questionsDeckID == nil && !model.reviewPresented && !model.editorPresented && !model.creationPresented {
                Button { model.settingsPresented = true } label: { Label("Settings", systemImage: "gearshape") }

              }
            }
        }
        .toolbarBackground(model.theme.palette(for: scheme).surface,
                           for: .automatic)
        .toolbarBackground(EngramNavigationPolicy.needsOpaqueChrome(reduceTransparency: reduceTransparency, increasedContrast: contrast == .increased) ? .visible : .automatic, for: .automatic)
        .modifier(PhoneTodayNavigation(enabled: usesPhoneTodayTitle && destination != .activity))
        .engramCanvas()
    }
}

/// Keep Today's heading in the page, without a collapsing centered title or bar fill.
private struct PhoneTodayNavigation: ViewModifier {
    let enabled: Bool
    @ViewBuilder func body(content: Content) -> some View {
        #if os(iOS)
        if enabled {
            if #available(iOS 26.0, *) {
                content.navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.hidden, for: .navigationBar)
                    .scrollEdgeEffectHidden(true, for: .top)
            } else {
                content.navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.hidden, for: .navigationBar)
            }
        } else { content }
        #else
        content
        #endif
    }
}

struct DeckFormView: View {
    @Bindable var model: EngramModel
    @State var form: DeckForm
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @Environment(\.engramScreenshotCapture) private var capturing
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
            .engramCanvas().task { focused = !capturing }
        }
        .engramSheetSizing(idealWidth: 460, minimumHeight: 280)
        .interactiveDismissDisabled(model.busy)
    }
}
