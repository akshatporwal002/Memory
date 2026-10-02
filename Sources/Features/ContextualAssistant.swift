import AIInfrastructure
import SwiftUI
import LearningCore
import DesignSystem

private struct AssistantPassage: Identifiable, Sendable {
    let id: String
    let deckID: String
    let title: String
    let text: String
    let noteID: String?
    let blockID: String?
}

private struct AssistantMessage: Identifiable {
    var id: String = UUID().uuidString
    let isUser: Bool
    let text: String
    let sources: [AssistantPassage]
    var draftQuestion: String? = nil
    var draftAnswer: String? = nil
}

private enum AssistantRetrieval {
    static func passages(query: String, deckID: String, library: LibrarySnapshot) -> [AssistantPassage] {
        EvidenceRetrieval.retrieve(query:query,deckID:deckID,library:library,limit:5).map {
            AssistantPassage(id:$0.id,deckID:$0.deckID,title:$0.title,text:$0.text,noteID:$0.noteID,blockID:$0.blockID)
        }
    }
}
struct ContextualAssistant: View {
    @Bindable var model: EngramModel
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open = false
    @State private var expanded = false
    @State private var prompt = ""
    @State private var messages: [String: [AssistantMessage]] = [:]
    private var busy: Bool { model.assistant.busy }
    @State private var error: String?
    @State private var selectedDeckID: String?
    @State private var pdfSource: PDFLearningSource?
    @FocusState private var composerFocused: Bool
    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    private var palette: EngramPalette { theme.palette(for: scheme) }
    private var deckID: String? {
        if model.pdfLearningPresented { return nil }
        if model.creationPresented && model.notebookDeckID == nil && model.activeDeckOverviewID == nil && model.activeContentDeckID == nil { return nil }
        return model.activeContentDeckID ?? model.questionsDeckID ?? model.notebookDeckID ?? (model.editorPresented ? model.draft?.deckID : nil) ?? (model.reviewPresented ? model.library.session?.deckID : nil) ?? selectedDeckID ?? model.selectedDeckID ?? model.library.liveDecks.first?.id
    }
    private var deckName: String { deckID.map(model.deckName) ?? (model.creationPresented ? "New notebook" : "Your study material") }
    private var context: String {
        if model.pdfLearningPresented { return "pdf:" + (model.pdfLearning.draft.source?.id ?? "none") }
        let workflow = model.reviewPresented ? "review" : model.editorPresented ? "editor" : model.activeContentKind ?? (model.activeDeckOverviewID != nil ? "deck" : model.creationPresented ? "creation" : model.questionsDeckID != nil ? "questions" : model.notebookDeckID != nil ? "notebook" : model.destination.rawValue)
        return workflow + ":" + (deckID ?? "none")
    }
    private var thread: [AssistantMessage] { (messages[context] ?? []) + (model.library.assistantState?.conversations.first(where: { $0.id == context })?.messages.map { AssistantMessage(id: $0.id, isUser: $0.role == "user", text: $0.text, sources: []) } ?? []) }
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
    private var studyContext: String {
        if model.pdfLearningPresented {
            let draft = model.pdfLearning.draft
            return "PDF learning setup. Goal: \(draft.brief.goal). Topics: \(draft.brief.topics). Exclusions: \(draft.brief.exclusions). Difficulty: \(draft.brief.difficulty). The learner can adjust this brief manually; do not claim to have changed it."
        }
        if let currentReviewPrompt { return "Current review prompt: " + currentReviewPrompt }
        if model.editorPresented, let draft = model.draft {
            return "Current unsaved card draft. Question: \(draft.front.prefix(900)). Answer: \(draft.back.prefix(900))."
        }
        if model.creationPresented && model.activeDeckOverviewID == nil && model.activeContentDeckID == nil {
            let draft = model.deckCreationDraft
            return "Current unsaved notebook draft. Title: \(draft.title.prefix(120)). Subject: \(draft.subject.prefix(120)). Writing: \(draft.document.prefix(1800))."
        }
        if model.destination == .activity {
            return "Activity today: \(model.todaysReviews.count) review attempts saved, \(model.due.count) cards ready. Library target: \(Int(model.library.settings.desiredRetention * 100))%."
        }
        if model.destination == .library, model.selectedDeckID == nil {
            return "Library decks: " + model.library.liveDecks.prefix(30).map(\.name).joined(separator: ", ")
        }
        return "Current deck: " + deckName
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .trailing, spacing: 0) {
                Spacer(minLength: 0)
                glassContainer {
                    if open { assistantSurface(panel(height: geometry.size.height), open: true) }
                    else { dock(narrow: geometry.size.width < 600) }
                }
                .background(GeometryReader { dock in
                    Color.clear.preference(key: AssistantDockHeight.self, value: open ? 72 : dock.size.height + 8)
                })
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.horizontal, 16)
        }
        .confirmationDialog("Confirm the assistant's requested change", isPresented: Binding(get: { model.assistant.pendingConfirmation != nil }, set: { if !$0 { Task { await model.assistant.reject(model: model) } } })) {
            Button("Confirm change") { Task { await model.assistant.confirm(model: model) } }
            Button("Cancel", role: .cancel) { Task { await model.assistant.reject(model: model) } }
        } message: {
            Text(model.library.assistantState?.runs.flatMap(\.actions).last(where: { $0.id == model.assistant.pendingConfirmation?.id })?.summary ?? "Review this requested change before accepting.")
        }
        .animation(motion, value: open)
        .animation(motion, value: expanded)
        .animation(motion, value: thread.count)
        .onChange(of: context) { _, _ in prompt = ""; error = nil; expanded = false; close() }
        .onChange(of: model.selectedDeckID) { _, _ in selectedDeckID = nil }
        .sheet(isPresented: Binding(get: { pdfSource != nil }, set: { if !$0 { pdfSource = nil } })) {
            if let pdfSource { PDFSourcePagesView(source: pdfSource) }
        }
    }

    private var motion: Animation? { reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.88) }
    private var showsNavigation: Bool {
        !model.reviewPresented && !model.editorPresented && !model.creationPresented && model.notebookDeckID == nil && model.questionsDeckID == nil && model.activeContentDeckID == nil
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
        if #available(iOS 26.0, *), !reduceTransparency, contrast != .increased {
            content.glassEffect(.regular.tint(open ? palette.selection : .clear).interactive(), in: .rect(cornerRadius: open ? 24 : 25))
                .glassEffectID("assistant", in: glassNamespace)
        } else { fallbackSurface(content, open: open) }
        #else
        fallbackSurface(content, open: open)
        #endif
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
                withAnimation(motion) { open = true }
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
                    VStack(spacing: 3) {
                        Image(systemName: destination.symbol).font(.system(size: 18))
                        Text(destination.title).font(.caption2.weight(.medium))
                    }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Capsule())
                        .foregroundStyle(model.destination == destination ? (scheme == .dark ? palette.easyInk : palette.anchor) : palette.secondaryText)
                        .background(model.destination == destination ? palette.selection : .clear, in: Capsule())
                }.buttonStyle(.plain).accessibilityIdentifier("tab-" + destination.rawValue)
                    .accessibilityAddTraits(model.destination == destination ? [.isSelected] : [])
            }
        }.padding(3)
    }
    private func close() { composerFocused = false; withAnimation(motion) { open = false } }

    private func panel(height: CGFloat) -> some View {
        VStack(spacing: 0) {
          if !thread.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "sparkle").foregroundStyle(palette.accentInk)
                Text(deckName).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 8)
                if !thread.isEmpty {
                    Button { composerFocused = false; expanded.toggle() } label: {
                        Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                        .accessibilityLabel(expanded ? "Collapse assistant" : "Expand assistant")
                }
                Button(action: close) { Image(systemName: "xmark").frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .accessibilityLabel("Close assistant")
            }
            .buttonStyle(.plain).frame(minHeight: 44)
            if !model.library.liveDecks.isEmpty && !model.creationPresented && expanded {
                Menu {
                    ForEach(model.library.liveDecks) { deck in
                        Button(deck.name) { selectedDeckID = deck.id; prompt = "" }
                    }
                } label: { Label("Sources: \(deckName)", systemImage: "book.closed").lineLimit(1) }
                    .font(.caption).foregroundStyle(palette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 28)
            }
            if !thread.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(thread) { message in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(message.isUser ? "You" : "Assistant").font(.caption.weight(.semibold)).foregroundStyle(palette.secondaryText)
                                    RichContentView(source: message.text).font(.subheadline)
                                    if !message.isUser {
                                        ForEach(message.sources) { source in
                                            Button { openSource(source) } label: {
                                                Label(source.title, systemImage: "book.pages").lineLimit(2)
                                            }.font(.caption).frame(minHeight: 32, alignment: .leading)
                                        }
                                        if let question = message.draftQuestion, let answer = message.draftAnswer,
                                           model.editorPresented || model.creationPresented {
                                            Button("Apply suggested question") { apply(question: question, answer: answer) }
                                                .font(.caption.weight(.semibold)).frame(minHeight: 44)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }
                            if busy, !model.assistant.output.isEmpty { RichContentView(source: model.assistant.output) }
                            if busy { ProgressView("Thinking…").font(.caption).id("assistant-end") }
                        }.padding(.vertical, 10)
                    }
                    .frame(height: min(max(90, height * (expanded ? 0.60 : 0.32)), max(90, height - 170)))
                    .onChange(of: thread.count) { _, _ in
                        if let id = thread.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            }
          }
            if let error = error ?? model.assistant.error { Text(error).font(.caption).foregroundStyle(palette.againInk).frame(maxWidth: .infinity, alignment: .leading) }
            if model.chatGPT.activeAccount == nil && error != nil {
                Button("Connect ChatGPT in Settings") { close(); model.settingsPresented = true }
                    .font(.caption.weight(.medium)).frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            }
            HStack {
                Menu {
                    ForEach(model.aiMarker.models, id: \.self) { id in
                        Button(model.aiMarker.title(for:id)) { Task { await model.assistant.selectModel(id, contextID: context, model: model) } }
                    }
                    if model.chatGPT.activeAccount == nil { Button("Connect ChatGPT") { close(); model.settingsRoute = "AI & Connections"; model.settingsPresented = true } }
                    Button("Refresh models") { Task { await model.aiMarker.loadModels(connection: model.chatGPT) } }
                } label: {
                    Text(model.aiMarker.title(for:model.library.assistantState?.conversations.first(where: { $0.id == context })?.modelID ?? model.aiMarker.chatModel)).font(.caption).lineLimit(1)
                }.frame(minHeight:44).accessibilityLabel("AI model: " + model.aiMarker.title(for:model.library.assistantState?.conversations.first(where: { $0.id == context })?.modelID ?? model.aiMarker.chatModel)).disabled(busy)
                Spacer()
                if busy { Button("Stop") { model.assistant.cancel() } }
                Button("Review changes") { model.actionReviewPresented = true }
            }.font(.caption).frame(minHeight: 44)
            HStack(spacing: 10) {
                if thread.isEmpty { Image(systemName: "sparkle").foregroundStyle(palette.accentInk) }
                TextField(model.pdfLearningPresented ? "Ask about this PDF…" : "Ask about your notes…", text: $prompt, axis: .vertical)
                    .lineLimit(1...3).focused($composerFocused)
                    .submitLabel(.send).onSubmit { send() }
                    .accessibilityLabel("Message the study assistant")
                    .accessibilityIdentifier("assistant-composer")
                Button(action: send) { Image(systemName: "arrow.up").font(.headline).frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .disabled(busy || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Send message")
                if thread.isEmpty {
                    Button(action: close) { Image(systemName: "xmark").frame(width: 44, height: 44).contentShape(Rectangle()) }
                        .accessibilityLabel("Close assistant")
                }
            }
            .padding(.horizontal, 4).padding(.vertical, 2)
            if thread.isEmpty && expanded {
                Button(model.reviewPresented ? "Give me a hint" : model.editorPresented || model.creationPresented ? "Suggest a question" : "Explain this simply") {
                    prompt = model.reviewPresented ? "Give me a hint without revealing the answer" :
                        model.editorPresented || model.creationPresented ? "Draft one question and answer from these notes" :
                        "Explain the key idea in these notes simply"
                    send()
                }.font(.caption).frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: 530)
    }

    private func send() {
        let question = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !busy else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"), ProcessInfo.processInfo.arguments.contains("--ui-assistant-fixture") {
            messages[context, default: []].append(AssistantMessage(isUser: true, text: question, sources: []))
            messages[context, default: []].append(AssistantMessage(isUser: false, text: "CloudFront caches content at edge locations near your users. This reduces latency and the load on the origin. Use it for fast delivery of websites, images and video.\n\nUI review fixture — no live AI request was made.", sources: []))
            prompt = ""; composerFocused = false; return
        }
        #endif
        guard model.chatGPT.activeAccount != nil else {
            error = "Connect ChatGPT to ask about your notes."
            return
        }
        let key = context

        let search = question + " " + (currentReviewPrompt ?? "")
        let pdfRecord = deckID.flatMap { id in model.library.liveDecks.first(where: { $0.id == id })?.pdfLearning }
        let documentSource = model.pdfLearningPresented ? model.pdfLearning.draft.source : pdfRecord?.source
        let sourceOnly = documentSource != nil
        let allSources: [AssistantPassage]
        if let documentSource {
            let brief = model.pdfLearningPresented ? model.pdfLearning.draft.brief : (pdfRecord?.brief ?? model.pdfLearning.draft.brief)
            allSources = EvidenceRetrieval.retrieve(source: documentSource, brief: brief, query: search, limit: 5).map {
                AssistantPassage(id: "pdf-" + $0.id, deckID: deckID ?? "pdf-draft", title: "\(documentSource.filename) · page \($0.page ?? 0)", text: $0.text, noteID: nil, blockID: nil)
            }
        } else { allSources = deckID.map { AssistantRetrieval.passages(query: search, deckID: $0, library: model.library) } ?? [] }
        let currentNoteID = model.library.session?.current?.card.noteID
        let sources = hideReviewAnswer ? allSources.filter { $0.noteID != currentNoteID } : allSources
        let evidence = sources.enumerated().map { "[\($0.offset + 1)] \($0.element.title)\n\($0.element.text)" }.joined(separator: "\n\n")
        prompt = ""; error = nil; composerFocused = false
        model.assistant.start(question: question, contextID: key, context: studyContext + "\nWorkflow: " + key,
                              evidence: evidence, sourceOnly: sourceOnly, model: model)
    }
    private func parseDraft(_ response: String) -> (String, String)? {
        let lines = response.components(separatedBy: .newlines)
        guard let question = lines.first(where: { $0.lowercased().hasPrefix("question:") }).map({ String($0.dropFirst(9)).trimmingCharacters(in: .whitespacesAndNewlines) }),
              let answer = lines.first(where: { $0.lowercased().hasPrefix("answer:") }).map({ String($0.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines) }),
              !question.isEmpty, !answer.isEmpty else { return nil }
        return (question, answer)
    }

    private func apply(question: String, answer: String) {
        if model.editorPresented, var draft = model.draft {
            draft.front = question
            draft.back = answer
            model.draft = draft
        } else if model.creationPresented {
            let separator = model.deckCreationDraft.document.isEmpty ? "" : "\n\n"
            model.deckCreationDraft.document += separator + question + ": " + answer
        }
        close()
    }

    private func openSource(_ source: AssistantPassage) {
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
