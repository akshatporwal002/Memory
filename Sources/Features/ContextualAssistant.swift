import AIInfrastructure
import SwiftUI
import LearningCore
import DesignSystem
private struct AssistantTranscriptHeight: PreferenceKey {
    static let defaultValue: CGFloat = 90
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
#if os(iOS)
import UIKit
#endif

private extension View {
    @ViewBuilder func assistantScrollAnchors() -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            defaultScrollAnchor(.bottom).defaultScrollAnchor(.top, for: .alignment)
        } else {
            defaultScrollAnchor(.bottom)
        }
    }
}

private struct AssistantPassage: Identifiable, Sendable {
    let id: String
    let deckID: String
    let title: String
    let text: String
    let noteID: String?
    let blockID: String?
    let documentID: String?
}

private struct AssistantMessage: Identifiable {
    var id: String = UUID().uuidString
    let isUser: Bool
    let text: String
    let sources: [AssistantPassage]
}

private enum AssistantRetrieval {
    static func passages(query: String, deckID: String, library: LibrarySnapshot) -> [AssistantPassage] {
        EvidenceRetrieval.retrieve(query:query,deckID:deckID,library:library,limit:5).map {
            AssistantPassage(id:$0.id,deckID:$0.deckID,title:$0.title,text:$0.text,noteID:$0.noteID,blockID:$0.blockID,documentID:$0.documentID)
        }
    }
}
struct ContextualAssistant: View {
    private enum PanelStage { case closed, compact, medium, expanded }
    @Bindable var model: EngramModel
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage: PanelStage = .closed
    @State private var showingHistory = false
    @State private var selectedHistoryID: String?
    @State private var transcriptHeight: CGFloat = 90
    @State private var prompt = ""
    @State private var composerEpoch = 0
    @State private var messages: [String: [AssistantMessage]] = [:]
    private var busy: Bool { model.assistant.busy }
    @State private var error: String?
    @State private var selectedDeckID: String?
    @State private var pdfSource: PDFLearningSource?
    @State private var openLibraryDocument: LibraryDocument?
    @FocusState private var composerFocused: Bool
    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    private var palette: EngramPalette { theme.palette(for: scheme) }
    private var chatScheme: ColorScheme { theme == .monochrome ? (scheme == .dark ? .light : .dark) : scheme }
    private var chatPalette: EngramPalette { theme.palette(for: chatScheme) }
    private var open: Bool { stage != .closed }
    private var expanded: Bool { stage == .expanded }
    private var showsTranscript: Bool { stage == .medium || expanded }
    private var chatTitle: String { thread.first(where: { $0.isUser })?.text ?? "New chat" }
    private var phoneDock: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }
    private var deckID: String? {
        if model.pdfLearningPresented { return nil }
        if model.creationPresented && model.notebookDeckID == nil && model.activeDeckOverviewID == nil && model.activeContentDeckID == nil { return nil }
        return model.activeContentDeckID ?? model.questionsDeckID ?? model.notebookDeckID ?? (model.editorPresented ? model.draft?.deckID : nil) ?? (model.reviewPresented ? model.library.session?.deckID : nil) ?? selectedDeckID ?? model.selectedDeckID ?? model.library.liveDecks.first?.id
    }
    private var deckName: String { deckID.map(model.deckName) ?? (model.creationPresented ? "New notebook" : "Your study material") }
    private var context: String {
        let prefix = model.activeLibraryID == LibrarySpace.defaultID ? "" : "library:" + model.activeLibraryID + ":"
        if model.pdfLearningPresented { return prefix + "pdf:" + (model.pdfLearning.draft.source?.id ?? "none") }
        let workflow = model.reviewPresented ? "review" : model.editorPresented ? "editor" : model.activeContentKind ?? (model.activeDeckOverviewID != nil ? "deck" : model.creationPresented ? "creation" : model.questionsDeckID != nil ? "questions" : model.notebookDeckID != nil ? "notebook" : model.destination.rawValue)
        return prefix + workflow + ":" + (deckID ?? "none")
    }
    private var activeConversationID: String { selectedHistoryID ?? context }
    private var recentConversations: [LearningConversation] {
        (model.library.assistantState?.conversations ?? []).filter { !$0.messages.isEmpty }
            .sorted { ($0.messages.last?.createdAt ?? .distantPast) > ($1.messages.last?.createdAt ?? .distantPast) }
    }
    private var thread: [AssistantMessage] {
        (messages[activeConversationID] ?? []) + (model.library.assistantState?.conversations.first(where: { $0.id == activeConversationID })?.messages.map {
            AssistantMessage(id:$0.id,isUser:$0.role == "user",text:$0.text,sources:[])
        } ?? [])
    }
    private var recentSavedAction: AIActionRecord? {
        model.library.assistantState?.runs.last(where: { $0.conversationID == activeConversationID })?.actions.last(where: {
            $0.status == "completed" && $0.changes.contains(where: { $0.undoneAt == nil })
        })
    }
    private var currentReviewPrompt: String? {
        guard model.reviewPresented, let card = model.library.session?.current?.card,
              let note = model.library.liveNotes.first(where: { $0.id == card.noteID }) else { return nil }
        if let item = model.library.session?.current, let mcq = note.mcq?.ordered(for: item.presentationID) {
            return mcq.prompt + "\n" + mcq.choices.map { mcq.displayLetter(for: $0.id) + ") " + $0.text }.joined(separator: "\n")
        }
        return note.front
    }
    private var hideReviewAnswer: Bool {
        model.reviewPresented && model.library.session?.current?.revealedAt == nil
    }
    private var viewingContext: String {
        if model.reviewPresented { return "Screen: active study review. " + (currentReviewPrompt.map { "Visible question: \($0.prefix(1200))" } ?? "") }
        if let id = model.activeContentDeckID,model.activeContentKind == "questions" {
            let note = model.library.liveNotes.first { $0.id == model.visibleQuestionID && $0.deckID == id }
            return "Screen: Questions in \(model.deckName(id)). " + (note.map { "Visible question ID: \($0.id). Prompt: \($0.front.prefix(1200)). Expected answer: \($0.back.prefix(1200))." } ?? "")
        }
        if let id = model.activeContentDeckID,["notes","notebook"].contains(model.activeContentKind ?? ""),
           let deck = model.library.liveDecks.first(where:{ $0.id == id }) {
            let block = NotebookDocument.blocks(for:deck,in:model.library).first { $0.id == model.visibleNotebookBlockID }
            return "Screen: \(model.activeContentKind == "notes" ? "Notes" : "Notebook") in \(deck.name). " +
                (block.map { "Visible section ID: \($0.id). Content: \($0.text.prefix(1800))." } ?? "")
        }
        if let id = model.activeDeckOverviewID { return "Screen: deck overview for \(model.deckName(id))." }
        if model.creationPresented { return "Screen: create notebook." }
        if model.destination == .library {
            if let id = model.visibleLibraryDocumentID,
               let document = model.library.folderDocuments?.first(where: { $0.id == id })?.document ?? model.library.liveDecks.compactMap({ $0.documents?.first(where: { $0.id == id }) }).first {
                return "Screen: reading source file \(document.name). File ID: \(id)."
            }
            return "Screen: Library file tree."
        }
        if model.destination == .activity { return "Screen: Activity." }
        return "Screen: Today."
    }
    private var studyContext: String {
        if model.pdfLearningPresented {
            let draft = model.pdfLearning.draft
            return "Screen: PDF learning setup. Goal: \(draft.brief.goal). Topics: \(draft.brief.topics). Exclusions: \(draft.brief.exclusions). Difficulty: \(draft.brief.difficulty). The learner can adjust this brief manually; do not claim to have changed it."
        }
        if let currentReviewPrompt { return viewingContext + " Current review prompt: " + currentReviewPrompt }
        if model.editorPresented, let draft = model.draft {
            return "Screen: question editor. Current unsaved card draft. Question: \(draft.front.prefix(900)). Answer: \(draft.back.prefix(900))."
        }
        if model.creationPresented && model.activeDeckOverviewID == nil && model.activeContentDeckID == nil {
            let draft = model.deckCreationDraft
            return viewingContext + " Current unsaved notebook draft. Title: \(draft.title.prefix(120)). Subject: \(draft.subject.prefix(120)). Writing: \(draft.document.prefix(1800))."
        }
        if model.destination == .activity {
            return viewingContext + " Activity today: \(model.todaysReviews.count) review attempts saved, \(model.due.count) cards ready. Library target: \(Int(model.library.settings.desiredRetention * 100))%."
        }
        if model.destination == .library, model.selectedDeckID == nil {
            return viewingContext + " Library decks: " + model.library.liveDecks.prefix(30).map(\.name).joined(separator: ", ")
        }
        return viewingContext + " Current deck: " + deckName
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .trailing, spacing: 0) {
                Spacer(minLength: 0)
                glassContainer {
                    if open {
                        panel(height: geometry.size.height)
                            .foregroundStyle(chatPalette.primaryText).tint(chatPalette.accentInk)
                            .environment(\.colorScheme, chatScheme)
                    }
                    else { dock(narrow: phoneDock || geometry.size.width < 600) }
                }
                .background(GeometryReader { dock in
                    Color.clear.preference(key: AssistantDockHeight.self, value: open ? 72 : dock.size.height + 8)
                })
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.horizontal, 16)
            .padding(.bottom, open ? 8 : 0)
        }
        .confirmationDialog("Confirm the assistant's requested change", isPresented: Binding(get: { model.assistant.pendingConfirmation != nil }, set: { if !$0 { Task { await model.assistant.reject(model: model) } } })) {
            Button("Confirm change") { Task { await model.assistant.confirm(model: model) } }
            Button("Cancel", role: .cancel) { Task { await model.assistant.reject(model: model) } }
        } message: {
            Text(model.library.assistantState?.runs.flatMap(\.actions).last(where: { $0.id == model.assistant.pendingConfirmation?.id })?.summary ?? "Review this requested change before accepting.")
        }
        .animation(motion, value: stage)
        .animation(motion, value: thread.count)
        .onChange(of: context) { _, _ in prompt = ""; error = nil; showingHistory = false; selectedHistoryID = nil; close() }
        .onChange(of: model.libraryPresentationEpoch) { _, _ in messages = [:]; selectedDeckID = nil; selectedHistoryID = nil; prompt = ""; error = nil; close() }
        .onChange(of: prompt) { _, value in
            if stage == .compact && !value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { withAnimation(motion) { stage = .medium } }
        }
        .onChange(of: model.selectedDeckID) { _, _ in selectedDeckID = nil }
        .sheet(isPresented: Binding(get: { pdfSource != nil }, set: { if !$0 { pdfSource = nil } })) {
            if let pdfSource { PDFSourcePagesView(source: pdfSource) }
        }
        .sheet(item:$openLibraryDocument) { document in LibraryDocumentReader(document:document) }
    }

    private var motion: Animation? { reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.88) }
    private var showsNavigation: Bool {
        !model.reviewPresented && !model.editorPresented && !model.creationPresented && model.notebookDeckID == nil && model.questionsDeckID == nil && model.activeContentDeckID == nil && model.activeDeckOverviewID == nil
    }
    @ViewBuilder private func glassContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *), !reduceTransparency, contrast != .increased {
            GlassEffectContainer(spacing: 12, content: content)
        } else { content() }
        #else
        content()
        #endif
    }
    @ViewBuilder private func assistantSurface<Content: View>(_ content: Content, open: Bool) -> some View {
        #if os(iOS)
        if #available(iOS 26.0,*), !reduceTransparency, contrast != .increased {
            content.glassEffect(.regular.interactive(),in:.capsule)
                .glassEffectID("assistant",in:glassNamespace)
        } else { fallbackSurface(content,open:false) }
        #else
        fallbackSurface(content,open:false)
        #endif
    }
    @ViewBuilder private func composerSurface<Content: View>(_ content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26.0,*), !reduceTransparency, contrast != .increased {
            content.background(chatPalette.canvas.opacity(0.78),in:Capsule())
                .glassEffect(.clear.tint(chatPalette.canvas.opacity(0.15)).interactive(),in:.capsule)
                .glassEffectID("assistant",in:glassNamespace)
        } else { composerFallback(content) }
        #else
        composerFallback(content)
        #endif
    }
    private func composerFallback<Content: View>(_ content: Content) -> some View {
        content.background(chatPalette.canvas.opacity(reduceTransparency || contrast == .increased ? 1 : 0.65),in:Capsule())
            .background(.regularMaterial,in:Capsule())
    }
    private var readingShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
    }
    @ViewBuilder private var readingBackdrop: some View {
        if !showsTranscript { Color.clear }
        else if reduceTransparency || contrast == .increased {
            readingShape.fill(chatPalette.canvas)
                .overlay(readingShape.strokeBorder(chatPalette.primaryText.opacity(0.18), lineWidth: 1))
        } else {
            readingGlass
                .overlay(readingShape.strokeBorder(chatPalette.primaryText.opacity(0.18), lineWidth: 0.75))
        }
    }
    private var readingGlass: some View {
        readingShape.fill(.regularMaterial)
            .overlay(readingShape.fill(chatPalette.canvas.opacity(0.78)))
            .overlay(readingShape.strokeBorder(.white.opacity(chatScheme == .dark ? 0.12 : 0.35), lineWidth: 1))
    }
    private func fallbackSurface<Content: View>(_ content: Content, open: Bool) -> some View {
        content.background(open ? palette.selection : palette.surface, in: RoundedRectangle(cornerRadius: open ? 24 : 25))
            .matchedGeometryEffect(id: reduceMotion ? (open ? "panel" : "button") : "assistant", in: glassNamespace)
    }
    private func dock(narrow: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if showsNavigation && narrow { navigationDock }
            else { Spacer(minLength: 0) }
            Button {
                if !busy { selectedHistoryID = UUID().uuidString; prompt = ""; error = nil }
                withAnimation(motion) { stage = busy ? .medium : .compact }
                composerFocused = true
            } label: {
                assistantSurface(Image(systemName: "sparkle").font(.system(size: 17, weight: .medium))
                    .frame(width: 48, height: 48).foregroundStyle(palette.primaryText), open: false)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Ask the study assistant").accessibilityIdentifier("assistant-entry")
        }
    }
    @ViewBuilder private var navigationDock: some View {
        #if os(iOS)
        if #available(iOS 26.0, *), !reduceTransparency, contrast != .increased {
            navigationButtons.glassEffect(.regular.interactive(), in: .capsule)
        } else if reduceTransparency || contrast == .increased {
            navigationButtons.background(palette.surface, in: Capsule())
        } else { navigationButtons.background(.regularMaterial, in: Capsule()) }
        #else
        navigationButtons.background(palette.surface, in: Capsule())
        #endif
    }
    private var navigationButtons: some View {
        HStack(spacing: 0) {
            ForEach(EngramDestination.allCases) { destination in
                Button { model.destination = destination } label: {
                    let selected = model.destination == destination
                    let content = VStack(spacing: 3) {
                        Image(systemName: destination.symbol).font(.system(size: 17,weight:selected ? .semibold : .regular))
                        Text(destination.title).font(.caption2.weight(.medium))
                    }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Capsule())
                        .foregroundStyle(selected ? (scheme == .dark ? palette.easyInk : palette.anchor) : palette.secondaryText)
                    navigationSelection(content, selected:selected)
                }.buttonStyle(.plain).accessibilityIdentifier("tab-" + destination.rawValue)
                    .accessibilityAddTraits(model.destination == destination ? [.isSelected] : [])
            }
        }.padding(3)
    }
    @ViewBuilder private func navigationSelection<Content:View>(_ content:Content,selected:Bool) -> some View {
        #if os(iOS)
        if #available(iOS 26.0,*),!reduceTransparency,contrast != .increased {
            if selected { content.glassEffect(.regular.tint(palette.selection).interactive(),in:.capsule) }
            else { content }
        } else { content.background(selected ? palette.selection : .clear,in:Capsule()) }
        #else
        content.background(selected ? palette.selection : .clear,in:Capsule())
        #endif
    }
    private func close() { composerFocused = false; showingHistory = false; withAnimation(motion) { stage = .closed } }

    private func panel(height: CGFloat) -> some View {
        VStack(spacing: 8) {
          VStack(spacing:0) {
          Capsule().fill(chatPalette.secondaryText.opacity(0.5)).frame(width:32,height:4)
            .frame(maxWidth:.infinity,minHeight:24).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance:8).onEnded { value in changeStage(for:value.translation.height) })
            .accessibilityLabel("Drag up to expand chat or down to collapse")
            .accessibilityIdentifier("assistant-drag-handle")
            .accessibilityAction(named:Text("Expand chat")) { changeStage(for:-100) }
            .accessibilityAction(named:Text("Collapse chat")) { changeStage(for:100) }
          if showsTranscript {
            HStack(spacing: 0) {
                Button {
                    composerFocused = false
                    withAnimation(motion) { showingHistory.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Text(showingHistory ? "Chats" : chatTitle).lineLimit(1)
                        Image(systemName:"chevron.down").font(.system(size:9))
                    }.frame(minHeight:44).contentShape(Rectangle())
                }.accessibilityLabel("Chat history").disabled(busy)
                Spacer(minLength:8)
                if showingHistory {
                Button(action:newChat) { Image(systemName:"plus").frame(width:44,height:44).contentShape(Rectangle()) }
                    .accessibilityLabel("New chat").disabled(busy)
                }
                Button { withAnimation(motion) { stage = expanded ? .medium : .expanded } } label: {
                    Image(systemName:expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right").frame(width:44,height:44).contentShape(Rectangle())
                }.accessibilityLabel(expanded ? "Collapse assistant" : "Expand assistant")
                Menu {
                    ForEach(model.aiMarker.models, id: \.self) { id in
                        Button(model.aiMarker.title(for:id) + " · " + (model.aiMarker.descriptor(for:id)?.provider.capitalized ?? "")) { Task { await model.assistant.selectModel(id, contextID: activeConversationID, model: model) } }
                    }
                    Button("Manage AI connections") { close(); model.settingsRoute = "AI & Connections"; model.settingsPresented = true }
                    Button("Refresh models") { Task { await model.aiMarker.loadModels(connection: model.chatGPT) } }
                } label: {
                    Image(systemName:"ellipsis").font(.caption).frame(width:44,height:44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("AI model: " + model.aiMarker.title(for:model.library.assistantState?.conversations.first(where: { $0.id == activeConversationID })?.modelID ?? model.aiMarker.chatModel)).disabled(busy)
                Button(action:close) { Image(systemName:"xmark").frame(width:44,height:44).contentShape(Rectangle()) }
                    .accessibilityLabel("Close assistant")
            }.font(.caption).foregroundStyle(chatPalette.secondaryText).buttonStyle(.plain)
            if showingHistory {
                List {
                    ForEach(recentConversations) { conversation in
                        Button {
                            selectedHistoryID = conversation.id
                            showingHistory = false
                        } label: {
                            VStack(alignment:.leading,spacing:4) {
                                Text(conversation.messages.first(where: { $0.role == "user" })?.text ?? "New chat")
                                    .font(.subheadline).lineLimit(1)
                                Text(conversation.messages.last?.text ?? "")
                                    .font(.caption).foregroundStyle(chatPalette.secondaryText).lineLimit(1)
                            }.frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
                        }.buttonStyle(.plain).listRowBackground(Color.clear)
                        .swipeActions { Button("Delete",role:.destructive) { deleteChat(conversation.id) } }
                    }
                }.listStyle(.plain).scrollContentBackground(.hidden)
                .frame(height:min(max(100,height * (expanded ? 0.82 : 0.43)),max(100,height - 90)))
            } else if !thread.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(thread) { message in
                                VStack(alignment: .leading, spacing: 8) {
                                    RichContentView(source: message.text,
                                        alignment: message.isUser ? .trailing : .leading,
                                        textColor: message.isUser ? chatPalette.secondaryText : chatPalette.primaryText)
                                        .font(message.isUser ? .subheadline.italic() : .body)
                                        .foregroundStyle(message.isUser ? chatPalette.secondaryText : chatPalette.primaryText)
                                        .multilineTextAlignment(message.isUser ? .trailing : .leading)
                                    if !message.isUser {
                                        ForEach(message.sources) { source in
                                            Button { openSource(source) } label: {
                                                Label(source.title, systemImage: "book.pages").lineLimit(2)
                                            }.font(.caption).frame(minHeight: 32, alignment: .leading)
                                        }
                                    }
                                }
                                .padding(.leading, message.isUser ? 28 : 0)
                                .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
                                .padding(.vertical, 4)
                                .accessibilityElement(children: .contain)
                                .accessibilityLabel(message.isUser ? "Your message" : "Assistant response")
                                .id(message.id)
                            }
                            if busy, !model.assistant.output.isEmpty { RichContentView(source: model.assistant.output) }
                            if busy { ProgressView("Thinking…").font(.caption) }
                            Color.clear.frame(height:1).id("assistant-bottom")
                        }.padding(.vertical, 10)
                        .background(GeometryReader { content in Color.clear.preference(key:AssistantTranscriptHeight.self,value:content.size.height) })
                    }
                    .accessibilityIdentifier("assistant-transcript")
                    .scrollDismissesKeyboard(.never)
                    .frame(height: expanded ? min(max(90,height * 0.72),max(90,height - 160)) : min(max(80,transcriptHeight),min(max(90,height * 0.45),max(90,height - 160))))
                    .onPreferenceChange(AssistantTranscriptHeight.self) { transcriptHeight = $0 }
                    .assistantScrollAnchors()
                    .onAppear { scrollChatToBottom(proxy) }
                    .onChange(of: thread.count) { _, _ in scrollChatToBottom(proxy) }
                    .onChange(of: expanded) { _, _ in scrollChatToBottom(proxy) }
                    .onChange(of: height) { _, _ in scrollChatToBottom(proxy) }
                    .onChange(of: model.assistant.output) { _, _ in scrollChatToBottom(proxy) }
                }
            } else {
                Color.clear.frame(height:expanded ? min(max(90,height * 0.72),max(90,height - 160)) : 24)
            }
          }
            if showsTranscript, let action = recentSavedAction,let change = action.changes.last(where: { $0.undoneAt == nil }),!showingHistory {
                Button { openSavedChange(change) } label: {
                    Label(change.afterNote != nil ? "Question saved · Open Questions" : "Notes saved · Open notebook",systemImage:"checkmark.circle")
                        .font(.caption.weight(.medium)).frame(maxWidth:.infinity,minHeight:38,alignment:.leading)
                }.buttonStyle(.plain)
            }
            if let error = error ?? model.assistant.error { Text(error).font(.caption).foregroundStyle(chatPalette.againInk).frame(maxWidth: .infinity, alignment: .leading) }
            if model.chatGPT.activeAccount == nil && !model.aiMarker.hasConnection && error != nil {
                Button("Manage AI connections") { close(); model.settingsRoute = "AI & Connections"; model.settingsPresented = true }
                    .font(.caption.weight(.medium)).frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            }
            if busy || recentSavedAction != nil {
            HStack {
                Spacer()
                if busy { Button("Stop") { model.assistant.cancel() } }
                if recentSavedAction != nil {
                    Button("Review changes") { model.actionReviewPresented = true }
                }
            }.font(.caption).frame(minHeight: 44)
            }
          }.padding(.horizontal,16).padding(.bottom,12)
            .background(readingBackdrop)
            if !showingHistory {
            composerSurface(HStack(spacing: 10) {
                if !showsTranscript { Image(systemName: "sparkle").foregroundStyle(chatPalette.accentInk) }
                TextField("", text: $prompt,
                    prompt: Text(model.pdfLearningPresented ? "Ask about this PDF…" : "Ask about your notes…").foregroundStyle(chatPalette.secondaryText), axis: .vertical)
                    .lineLimit(1...3).focused($composerFocused)
                    .simultaneousGesture(TapGesture().onEnded { composerFocused = true })
                    .id(composerEpoch)
                    .submitLabel(.send).onSubmit { send() }
                    .accessibilityLabel("Message the study assistant")
                    .accessibilityIdentifier("assistant-composer")
                Button(action: send) { Image(systemName: "arrow.up").font(.headline).frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .disabled(busy || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Send message")
                if !showsTranscript {
                    Button(action: close) { Image(systemName: "xmark").frame(width: 44, height: 44).contentShape(Rectangle()) }
                        .accessibilityLabel("Close assistant")
                }
            }
            .padding(.horizontal,16).padding(.vertical,4))
            }
            if thread.isEmpty && expanded && !showingHistory {
                Button(model.reviewPresented ? "Give me a hint" : model.editorPresented || model.creationPresented ? "Suggest a question" : "Explain this simply") {
                    prompt = model.reviewPresented ? "Give me a hint without revealing the answer" :
                        model.editorPresented || model.creationPresented ? "Draft one question and answer from these notes" :
                        "Explain the key idea in these notes simply"
                    send()
                }.font(.caption).frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            }
        }
        .padding(.bottom,4)
        .frame(maxWidth: 530)
    }

    private func changeStage(for translation: CGFloat) {
        guard abs(translation) > 10 else { return }
        withAnimation(motion) {
            if translation < 0 { stage = stage == .compact ? .medium : .expanded }
            else if showingHistory { showingHistory = false; stage = .compact }
            else { stage = expanded ? .medium : stage == .medium ? .compact : .closed }
        }
        if stage == .closed { composerFocused = false }
    }
    private func newChat() {
        selectedHistoryID = UUID().uuidString
        prompt = ""; error = nil; showingHistory = false
        withAnimation(motion) { stage = .compact }
        composerFocused = true
    }
    private func deleteChat(_ id: String) {
        guard !busy else { return }
        Task {
            let deleted = await model.perform { try await $0.deleteConversation(id) }
            if deleted {
                messages.removeValue(forKey:id)
                if activeConversationID == id { newChat() }
            }
        }
    }
    private func scrollChatToBottom(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            await Task.yield()
            guard open else { return }
            proxy.scrollTo("assistant-bottom", anchor:.bottom)
        }
    }

    private func send() {
        if model.cloud.userID != nil {
            let account = model.cloud.userID
            Task {
                await model.cloud.sync(model:model)
                guard account == model.cloud.userID else { error = "The Engram account changed. Please send your question again."; return }
                preparedSend()
            }
        } else { preparedSend() }
    }
    private func preparedSend() {
        let question = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !busy else { return }
        withAnimation(motion) { if stage == .compact { stage = .medium } }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"), ProcessInfo.processInfo.arguments.contains("--ui-assistant-fixture") {
            messages[activeConversationID, default: []].append(AssistantMessage(isUser: true, text: question, sources: []))
            messages[activeConversationID, default: []].append(AssistantMessage(isUser: false, text: question.localizedCaseInsensitiveContains("brief") ? "CloudFront is AWS’s content delivery network." : question.localizedCaseInsensitiveContains("formula") ? #"For a quadratic equation, \(ax^2+bx+c=0\), the roots are:\#n\#n\[x=\frac{-b\pm\sqrt{b^2-4ac}}{2a}\]"# : "CloudFront caches content at edge locations near your users. This reduces latency and the load on the origin. Use it for fast delivery of websites, images and video.\n\nUI review fixture — no live AI request was made.", sources: []))
            prompt = ""; composerFocused = false; composerEpoch += 1; return
        }
        #endif
        guard model.chatGPT.activeAccount != nil || model.aiMarker.hasConnection else {
            error = "Connect ChatGPT or add a personal API key to ask about your notes."
            return
        }
        let key = activeConversationID

        let search = question + " " + (currentReviewPrompt ?? "")
        let pdfRecord = deckID.flatMap { id in model.library.liveDecks.first(where: { $0.id == id })?.pdfLearning }
        let documentSource = model.pdfLearningPresented ? model.pdfLearning.draft.source : pdfRecord?.source
        let visibleFileID = model.visibleLibraryDocumentID
        let sourceOnly = visibleFileID != nil || documentSource != nil || deckID.flatMap { id in model.library.liveDecks.first(where: { $0.id == id })?.documents }?.isEmpty == false
        let allSources: [AssistantPassage]
        if let documentSource {
            let brief = model.pdfLearningPresented ? model.pdfLearning.draft.brief : (pdfRecord?.brief ?? model.pdfLearning.draft.brief)
            let pdf = EvidenceRetrieval.retrieve(source: documentSource, brief: brief, query: search, limit: 4).map {
                AssistantPassage(id: "pdf-" + $0.id, deckID: deckID ?? "pdf-draft", title: "\(documentSource.filename) · page \($0.page ?? 0)", text: $0.text, noteID: nil, blockID: nil,documentID:nil)
            }
            allSources = pdf + (deckID.map { AssistantRetrieval.passages(query:search,deckID:$0,library:model.library) } ?? [])
        } else if let visibleFileID,
                  let document = model.library.folderDocuments?.first(where: { $0.id == visibleFileID })?.document ?? model.library.liveDecks.compactMap({ $0.documents?.first(where: { $0.id == visibleFileID }) }).first {
            allSources = EvidenceRetrieval.retrieve(document:document,query:search,limit:6).map {
                    AssistantPassage(id:$0.id,deckID:$0.deckID,title:$0.title,text:$0.text,noteID:$0.noteID,blockID:$0.blockID,documentID:$0.documentID)
                }
        } else { allSources = deckID.map { AssistantRetrieval.passages(query: search, deckID: $0, library: model.library) } ?? [] }
        let currentNoteID = model.library.session?.current?.card.noteID
        let sources = hideReviewAnswer ? allSources.filter { $0.noteID != currentNoteID } : allSources
        let evidence = sources.enumerated().map { "[\($0.offset + 1)] \($0.element.title)\n\($0.element.text)" }.joined(separator: "\n\n")
        prompt = ""; error = nil; composerFocused = false; composerEpoch += 1
        model.assistant.start(question: question, contextID: key, context: studyContext + "\nWorkflow: " + key,
                              evidence: evidence, sourceOnly: sourceOnly, model: model)
    }
    private func openSavedChange(_ change: AIContentChange) {
        guard let id = change.deckID else { model.actionReviewPresented = true; return }
        if let note = change.afterNote {
            model.notebookFocusNoteID = note.id
            model.questionsDeckID = id
        } else {
            if let before = change.beforeDeck?.notebookBlocks,let after = change.afterDeck?.notebookBlocks {
                model.notebookFocusBlockID = after.first(where: { !before.contains($0) })?.id
            }
            model.notebookWritingOnly = true
            model.notebookDeckID = id
        }
        close()
    }
    private func openSource(_ source: AssistantPassage) {
        if let documentID = source.documentID,
           let document = model.library.liveDecks.first(where: { $0.id == source.deckID })?.documents?.first(where: { $0.id == documentID }) ?? model.library.folderDocuments?.first(where: { $0.id == documentID })?.document {
            openLibraryDocument = document; close(); return
        }
        if source.id.hasPrefix("pdf-") {
            pdfSource = model.pdfLearningPresented ? model.pdfLearning.draft.source : model.library.liveDecks.first(where: { $0.id == source.deckID })?.pdfLearning?.source
            close(); return
        }
        if source.noteID != nil {
            model.notebookFocusNoteID = source.noteID
            if model.activeContentDeckID != source.deckID || model.activeContentKind != "questions" {
                model.questionsDeckID = source.deckID
            }
        } else {
            model.notebookFocusBlockID = source.blockID
            if model.activeContentDeckID != source.deckID || model.activeContentKind != "notes" {
                model.notebookWritingOnly = true; model.notebookDeckID = source.deckID
            }
        }
        close()
    }
}
