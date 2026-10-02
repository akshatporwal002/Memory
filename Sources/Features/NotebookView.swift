import SwiftUI
import LearningCore
import DesignSystem

struct NotebookEditingDraft: Codable, Hashable {
    var blocks: [NotebookBlock]
    var original: [NotebookBlock]
    var revision: Int
    var changed: Bool { blocks != original }
}

/// A continuous writing surface. Cards retain their identities when blocks move or change.
struct NotebookView: View {
    @Bindable var model: EngramModel
    let deckID: String
    var writingOnly = false
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @State private var draft: NotebookEditingDraft?
    @State private var confirmRemoval = false
    @State private var confirmReload = false
    @State private var saved = false
    @State private var editing = false
    @State private var activeBlockID: String?
    @State private var railVisible = false
    @State private var railHideTask: Task<Void,Never>?
    @State private var previousPositions: [String:CGFloat] = [:]
    @State private var hasNewerSavedContent = false
    @FocusState private var focusedBlock: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var palette: EngramPalette { theme.palette(for: scheme) }
    private var storedBlocks: [NotebookBlock] {
        guard let deck = model.library.liveDecks.first(where: { $0.id == deckID }) else { return [] }
        return NotebookDocument.blocks(for:deck,in:model.library)
    }
    private var progressKey: String { "engram.notebook.readingSection." + deckID + (writingOnly ? ".notes" : "") }
    private var removedCount: Int {
        guard let draft else { return 0 }
        return Set(draft.original.compactMap(\.noteID)).subtracting(draft.blocks.compactMap(\.noteID)).count
    }
    private var otherCount: Int {
        model.library.liveNotes.filter { $0.deckID == deckID && !NotebookDocument.supports($0) }.count
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: EngramSpacing.section) {
                    VStack(alignment: .leading, spacing: EngramSpacing.small) {
                        Text(model.deckName(deckID).replacingOccurrences(of: "::", with: " / "))
                            .font(theme.font(.title)).accessibilityAddTraits(.isHeader)
                        Text(writingOnly ? "Read, connect, remember." : "Your notes and questions, together. Changes to questions update their cards.")
                            .font(theme.font(.metadata)).foregroundStyle(palette.secondaryText)
                        if let status { Text(status).font(theme.font(.metadata)).foregroundStyle(palette.secondaryText) }
                    }
                    if hasNewerSavedContent {
                        Button("New saved notes are available · Reload") { confirmReload = true }
                            .font(.subheadline.weight(.medium)).frame(minHeight:44)
                    }
                    if let error = model.error { EngramInlineError(message: error) }
                    if otherCount > 0 && !writingOnly {
                        Text("\(otherCount) formatted or cloze notes remain in Cards. Their content and schedules are preserved.")
                            .font(theme.font(.metadata)).foregroundStyle(palette.secondaryText)
                    }
                    if draft != nil {
                        ForEach(visibleBlocks) { block in
                            notebookBlock(block).id(block.id)
                        }
                        if visibleBlocks.isEmpty {
                            Text(writingOnly ? "Add the ideas and explanations you want to revisit." : "Start with a thought, a heading, or a question.")
                                .foregroundStyle(palette.secondaryText).padding(.vertical, 32)
                        }
                    }
                    notebookActions.id("notebook-end")
                }
                .padding(EngramSpacing.section)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
                .disabled(model.busy)
            }
            .coordinateSpace(name: "notebook-scroll")
            .onPreferenceChange(NotebookBlockPositions.self) { positions in
                if !previousPositions.isEmpty,
                   positions.contains(where: { entry in abs(entry.value - (previousPositions[entry.key] ?? entry.value)) > 6 }) {
                    revealRail()
                }
                previousPositions = positions
                if focusedBlock == nil,
                   let nearest = positions.min(by: { abs($0.value - 130) < abs($1.value - 130) }) {
                    setActive(nearest.key)
                }
            }
            .overlay(alignment: .topTrailing) { sectionRail(proxy: proxy) }
            .simultaneousGesture(DragGesture(minimumDistance:8).onChanged { _ in revealRail() })
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: focusedBlock) { _, id in
                if let id { setActive(id); proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: proxyScrollTarget) { _, id in
                if let id { jump(to: id, proxy: proxy); proxyScrollTarget = nil }
            }
        }
        .navigationTitle(writingOnly ? "Notes" : "Notebook").engramInlineTitle().engramCanvas().engramHideStudyTabs()
        .engramAssistantClearance()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(editing ? "Done editing" : "Edit") { focusedBlock = nil; editing.toggle() }
                    .disabled(model.busy)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(model.busy ? "Saving…" : "Save") {
                    if removedCount > 0 { confirmRemoval = true } else { save() }
                }.disabled(model.busy || draft?.changed != true).keyboardShortcut("s", modifiers: .command)
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    if draft != nil {
                        ForEach(visibleBlocks) { block in
                            Button(sectionTitle(block)) {
                                setActive(block.id)
                                proxyScrollTarget = block.id
                            }
                        }
                    }
                    Button("Reload saved notebook") { confirmReload = true }
                } label: { Label("Contents", systemImage: "list.bullet") }.disabled(model.busy)
            }
        }
        .confirmationDialog("Remove \(removedCount) cards from study?", isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button("Save and remove cards", role: .destructive) { save() }
        } message: { Text("Questions removed from this notebook will be removed from study. Their review history remains in your library backup.") }
        .confirmationDialog("Reload the saved notebook?", isPresented: $confirmReload, titleVisibility: .visible) {
            Button("Discard draft and reload", role: .destructive) { load(useDraft: false) }
        } message: { Text("This replaces your unsaved writing with the latest saved notes and cards.") }
        .onAppear {
            model.activeContentDeckID = deckID; model.activeContentKind = writingOnly ? "notes" : "notebook"
            UserDefaults.standard.set(deckID, forKey: "engram.notebook.lastDeckID")
            if draft == nil { load(useDraft: true) }
            if let noteID = model.notebookFocusNoteID {
                proxyScrollTarget = draft?.blocks.first { $0.noteID == noteID }?.id
                model.notebookFocusNoteID = nil
            }
            if let blockID = model.notebookFocusBlockID {
                proxyScrollTarget = blockID
                model.notebookFocusBlockID = nil
            } else if proxyScrollTarget == nil {
                let remembered = UserDefaults.standard.string(forKey: progressKey)
                proxyScrollTarget = visibleBlocks.first { $0.id == remembered }?.id ?? visibleBlocks.first?.id
            }
        }
        .onChange(of: model.notebookFocusBlockID) { _, id in
            if let id { proxyScrollTarget = id; model.notebookFocusBlockID = nil }
        }
        .onChange(of: model.notebookFocusNoteID) { _, id in
            if let id {
                proxyScrollTarget = draft?.blocks.first { $0.noteID == id }?.id
                model.notebookFocusNoteID = nil
            }
        }
        .onChange(of: storedBlocks) { _, updated in
            guard let draft,updated != draft.original else { return }
            if draft.changed { hasNewerSavedContent = true }
            else { load(useDraft:false) }
        }
        .onDisappear {
            railHideTask?.cancel()
            persist()
            if model.activeContentDeckID == deckID { model.activeContentDeckID = nil; model.activeContentKind = nil }
            model.visibleNotebookBlockID = nil
        }
        .task(id: draft) {
            do { try await Task.sleep(for: .milliseconds(350)); persist() } catch { }
        }
    }

    private var status: String? {
        if writingOnly {
            if model.busy { return "Saving notes…" }
            return draft?.changed == true ? "Draft kept on this device" : nil
        }
        let count = draft?.blocks.filter { $0.kind == .question }.count ?? 0
        if model.busy { return "Saving notebook and cards…" }
        if draft?.changed == true { return "\(count) questions · Draft kept on this device" }
        return nil
    }
    @ViewBuilder private func notebookBlock(_ block: NotebookBlock) -> some View {
        if editing { blockEditor(block) }
        else { blockReader(block) }
    }
    @ViewBuilder private var notebookActions: some View {
        if editing {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { insertButtons }
                VStack(alignment: .leading, spacing: 8) { insertButtons }
            }
        } else {
            Button { editing = true; insert(writingOnly ? .text : .question) } label: { Label(writingOnly ? "Add writing" : "Add a question", systemImage: "plus") }
                .buttonStyle(EngramButtonStyle(.secondary))
        }
    }
    private func setActive(_ id: String) {
        model.visibleNotebookBlockID = id
        guard activeBlockID != id else { return }
        activeBlockID = id
        UserDefaults.standard.set(id, forKey: progressKey)
    }
    @State private var proxyScrollTarget: String?

    private func sectionTitle(_ block: NotebookBlock) -> String {
        let first = block.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let title = first.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespacesAndNewlines))
        return title.isEmpty ? (block.kind == .question ? "Untitled question" : "Untitled section") : String(title.prefix(48))
    }
    private var visibleBlocks: [NotebookBlock] {
        (draft?.blocks ?? []).filter { !writingOnly || $0.kind == .text }
    }
    private var railBlocks: [NotebookBlock] {
        let blocks = visibleBlocks
        guard blocks.count > 5 else { return blocks }
        let center = blocks.firstIndex { $0.id == activeBlockID } ?? 0
        let start = min(max(0, center - 2), blocks.count - 5)
        return Array(blocks[start..<(start + 5)])
    }

    private func sectionRail(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            if visibleBlocks.count > 1 {
                ForEach(railBlocks) { block in
                    HStack(spacing: 0) {
                        if activeBlockID == block.id {
                            Text(sectionTitle(block)).font(.caption2.weight(.medium))
                                .foregroundStyle(palette.accentInk).lineLimit(1)
                                .frame(maxWidth: 104, alignment: .trailing)
                        } else {
                            Capsule().fill(palette.hairline).frame(width: 10, height: 2)
                        }
                    }.frame(width: 110, height: 14, alignment: .trailing)
                }
            }
        }
        .frame(minHeight: visibleBlocks.count > 1 ? 44 : 0, alignment: .topTrailing)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onEnded { value in
            let blocks = railBlocks
            guard visibleBlocks.count > 1, !blocks.isEmpty else { return }
            let index = min(blocks.count - 1, max(0, Int(value.location.y / 14)))
            jump(to: blocks[index].id, proxy: proxy)
        })
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Notes contents")
        .accessibilityValue(visibleBlocks.first { $0.id == activeBlockID }.map(sectionTitle) ?? "")
        .accessibilityHint("Swipe up or down to choose a section. The Contents menu lists every heading.")
        .accessibilityAdjustableAction { direction in
            let blocks = visibleBlocks
            guard !blocks.isEmpty else { return }
            let current = blocks.firstIndex { $0.id == activeBlockID } ?? 0
            switch direction {
            case .increment: jump(to: blocks[min(blocks.count - 1, current + 1)].id, proxy: proxy)
            case .decrement: jump(to: blocks[max(0, current - 1)].id, proxy: proxy)
            @unknown default: break
            }
        }
        .padding(.trailing, 8).padding(.top, 8)
        .opacity(railVisible ? 1 : 0)
        .allowsHitTesting(railVisible)
        .animation(reduceMotion ? nil : .easeOut(duration:0.2),value:railVisible)
        .accessibilityIdentifier("notes-contents-rail")
    }

    private func revealRail() {
        guard visibleBlocks.count > 1 else { return }
        railVisible = true
        railHideTask?.cancel()
        railHideTask = Task {
            try? await Task.sleep(for:.seconds(1.5))
            guard !Task.isCancelled else { return }
            railVisible = false
        }
    }

    private func jump(to id: String, proxy: ScrollViewProxy) {
        setActive(id)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .top) }
    }
    private func blockReader(_ block: NotebookBlock) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if block.kind == .question {
                QuestionReadingView(front: block.text, back: block.answer)
            } else {
                RichContentView(source: block.text).font(theme.font(.body))
            }
            Divider()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GeometryReader { geometry in
            Color.clear.preference(key: NotebookBlockPositions.self,
                                   value: [block.id: geometry.frame(in: .named("notebook-scroll")).minY])
        })
    }
    @ViewBuilder private var insertButtons: some View {
        Button { insert(.text) } label: { Label("Add writing", systemImage: "text.alignleft") }
            .buttonStyle(EngramButtonStyle(.secondary))
        if !writingOnly {
            Button { insert(.question) } label: { Label("Add question", systemImage: "plus") }
                .buttonStyle(EngramButtonStyle(.secondary))
        }
    }
    private func blockEditor(_ block: NotebookBlock) -> some View {
        VStack(alignment: .leading, spacing: EngramSpacing.small) {
            HStack {
                Text(block.kind == .text ? "Writing" : "Question")
                    .font(theme.font(.metadata)).foregroundStyle(palette.secondaryText)
                Spacer()
                Menu {
                    if block.kind == .text {
                        Button("Create cards from Q&A lines") { convert(block) }
                    }
                    Button("Insert writing below") { insert(.text, after: block.id) }
                    Button("Insert question below") { insert(.question, after: block.id) }
                    Button("Move up") { move(block.id, by: -1) }.disabled(draft?.blocks.first?.id == block.id)
                    Button("Move down") { move(block.id, by: 1) }.disabled(draft?.blocks.last?.id == block.id)
                    Button("Remove block", role: .destructive) { draft?.blocks.removeAll { $0.id == block.id }; saved = false }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .accessibilityLabel("Options for \(block.kind == .text ? "writing" : "question") block")
            }
            TextField(block.kind == .text ? "Write your notes…" : "What do you want to remember?", text: binding(block.id, \.text), axis: .vertical)
                .textFieldStyle(.plain).font(theme.font(.body)).lineLimit(1...100)
                .frame(minHeight: 44, alignment: .topLeading)
                .focused($focusedBlock, equals: block.id)
                .accessibilityLabel(block.kind == .text ? "Notebook writing" : "Question")
            if block.kind == .question {
                Text("Answer").font(theme.font(.metadata)).foregroundStyle(palette.secondaryText).padding(.top, 8)
                TextField("Write the answer…", text: binding(block.id, \.answer), axis: .vertical)
                    .textFieldStyle(.plain).font(theme.font(.body)).lineLimit(1...100)
                    .frame(minHeight: 44, alignment: .topLeading).accessibilityLabel("Answer")
                if block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || block.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Add a question and answer before saving.").font(theme.font(.metadata)).foregroundStyle(palette.accentInk)
                }
            }
            Divider().padding(.top, EngramSpacing.regular)
        }
        .background(GeometryReader { geometry in
            Color.clear.preference(key: NotebookBlockPositions.self,
                                   value: [block.id: geometry.frame(in: .named("notebook-scroll")).minY])
        })
    }
    private func binding(_ id: String, _ path: WritableKeyPath<NotebookBlock, String>) -> Binding<String> {
        Binding(get: { draft?.blocks.first { $0.id == id }?[keyPath: path] ?? "" }, set: { value in
            guard let i = draft?.blocks.firstIndex(where: { $0.id == id }) else { return }
            draft?.blocks[i][keyPath: path] = value; saved = false
        })
    }
    private func insert(_ kind: NotebookBlock.Kind, after id: String? = nil) {
        let block = NotebookBlock(kind: kind)
        let index = id.flatMap { key in draft?.blocks.firstIndex { $0.id == key } }.map { $0 + 1 } ?? draft?.blocks.count ?? 0
        draft?.blocks.insert(block, at: index); saved = false; focusedBlock = block.id
    }
    private func convert(_ block: NotebookBlock) {
        guard let index = draft?.blocks.firstIndex(where: { $0.id == block.id }) else { return }
        do {
            let converted = try NotebookDocument.expandWriting(block.text)
            guard converted.contains(where: { $0.kind == .question }) else {
                model.error = "Add a question: answer line to turn writing into cards."; return
            }
            draft?.blocks.replaceSubrange(index...index, with: converted)
            model.error = nil; saved = false
        } catch { model.error = error.localizedDescription }
    }
    private func move(_ id: String, by offset: Int) {
        guard let i = draft?.blocks.firstIndex(where: { $0.id == id }), let count = draft?.blocks.count,
              (0..<count).contains(i + offset) else { return }
        draft?.blocks.swapAt(i, i + offset); saved = false
    }
    private func load(useDraft: Bool) {
        guard model.library.liveDecks.contains(where: { $0.id == deckID }) else { return }
        let blocks = storedBlocks
        let cached = useDraft ? model.notebookDraft(deckID) : nil
        draft = cached ?? NotebookEditingDraft(blocks: blocks, original: blocks, revision: model.library.revision)
        activeBlockID = visibleBlocks.first?.id
        model.visibleNotebookBlockID = activeBlockID
        saved = false; hasNewerSavedContent = false; model.error = nil; persist()
    }
    private func persist() { model.keepNotebookDraft(draft?.changed == true ? draft : nil, deckID: deckID) }
    private func save() {
        guard let draft else { return }
        focusedBlock = nil
        Task {
            if await model.perform({ try await $0.saveNotebook(deckID: deckID, blocks: draft.blocks, expectedRevision: draft.revision, originalBlocks: draft.original) }) {
                model.keepNotebookDraft(nil, deckID: deckID); load(useDraft: false); saved = true
            }
        }
    }
}

private struct NotebookBlockPositions: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newest in newest })
    }
}

struct NotebookCreationPage: View {
    @Bindable var model: EngramModel
    @State private var createdID: String?
    var body: some View {
        if let createdID { NotebookView(model: model, deckID: createdID) }
        else { LibraryCreateDeckView(model: model) { id in model.selectedDeckID = id; createdID = id } }
    }
}
