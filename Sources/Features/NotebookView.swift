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
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @State private var draft: NotebookEditingDraft?
    @State private var confirmRemoval = false
    @State private var confirmReload = false
    @State private var saved = false
    @FocusState private var focusedBlock: String?
    private var palette: EngramPalette { theme.palette(for: scheme) }
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
                        Text("Your notes and questions, together. Changes to questions update their cards.")
                            .font(theme.font(.metadata)).foregroundStyle(palette.secondaryText)
                    }
                    if let error = model.error { EngramInlineError(message: error) }
                    if otherCount > 0 {
                        Text("\(otherCount) formatted or cloze notes remain in Cards. Their content and schedules are preserved.")
                            .font(theme.font(.metadata)).foregroundStyle(palette.secondaryText)
                    }
                    if let draft {
                        ForEach(draft.blocks) { block in
                            blockEditor(block).id(block.id)
                        }
                        if draft.blocks.isEmpty {
                            Text("Start with a thought, a heading, or a question.")
                                .foregroundStyle(palette.secondaryText).padding(.vertical, 32)
                        }
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) { insertButtons }
                        VStack(alignment: .leading, spacing: 8) { insertButtons }
                    }
                    .id("notebook-end")
                }
                .padding(EngramSpacing.section).frame(maxWidth: 760).frame(maxWidth: .infinity)
                .disabled(model.busy)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: focusedBlock) { _, id in
                if let id { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .navigationTitle("Notebook").engramInlineTitle().engramCanvas().engramHideStudyTabs()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Text(status).font(theme.font(.metadata)).foregroundStyle(palette.secondaryText)
                Spacer(minLength: 8)
                if model.busy { ProgressView() }
            }.padding(EngramSpacing.regular).background(palette.canvas)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(model.busy ? "Saving…" : "Save") {
                    if removedCount > 0 { confirmRemoval = true } else { save() }
                }.disabled(model.busy || draft?.changed != true).keyboardShortcut("s", modifiers: .command)
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button("Reload saved notebook") { confirmReload = true }
                } label: { Label("Notebook options", systemImage: "ellipsis.circle") }.disabled(model.busy)
            }
        }
        .confirmationDialog("Remove \(removedCount) cards from study?", isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button("Save and remove cards", role: .destructive) { save() }
        } message: { Text("Questions removed from this notebook will be removed from study. Their review history remains in your library backup.") }
        .confirmationDialog("Reload the saved notebook?", isPresented: $confirmReload, titleVisibility: .visible) {
            Button("Discard draft and reload", role: .destructive) { load(useDraft: false) }
        } message: { Text("This replaces your unsaved writing with the latest saved notes and cards.") }
        .onAppear {
            if draft == nil { load(useDraft: true) }
            if let noteID = model.notebookFocusNoteID {
                focusedBlock = draft?.blocks.first { $0.noteID == noteID }?.id
                model.notebookFocusNoteID = nil
            }
        }
        .onDisappear { persist() }
        .task(id: draft) {
            do { try await Task.sleep(for: .milliseconds(350)); persist() } catch { }
        }
    }

    private var status: String {
        let count = draft?.blocks.filter { $0.kind == .question }.count ?? 0
        if model.busy { return "Saving notebook and cards…" }
        if draft?.changed == true { return "\(count) questions · Draft kept on this device" }
        return "\(count) questions · \(saved ? "Saved" : "Up to date")"
    }
    @ViewBuilder private var insertButtons: some View {
        Button { insert(.text) } label: { Label("Add writing", systemImage: "text.alignleft") }
            .buttonStyle(EngramButtonStyle(.secondary))
        Button { insert(.question) } label: { Label("Add question", systemImage: "plus") }
            .buttonStyle(EngramButtonStyle(.secondary))
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
        guard let deck = model.library.liveDecks.first(where: { $0.id == deckID }) else { return }
        let blocks = NotebookDocument.blocks(for: deck, in: model.library)
        let cached = useDraft ? model.notebookDraft(deckID) : nil
        draft = cached ?? NotebookEditingDraft(blocks: blocks, original: blocks, revision: model.library.revision)
        saved = false; model.error = nil; persist()
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

struct NotebookCreationPage: View {
    @Bindable var model: EngramModel
    @State private var createdID: String?
    var body: some View {
        if let createdID { NotebookView(model: model, deckID: createdID) }
        else { LibraryCreateDeckView(model: model) { id in model.selectedDeckID = id; createdID = id } }
    }
}
