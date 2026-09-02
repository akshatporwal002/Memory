import SwiftUI
import LearningCore
import DesignSystem

struct EditorView: View {
    @Bindable var model: EngramModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var previewMode = false
    @State private var previewOrdinal = 0
    @State private var discardConfirmation = false
    @State private var tagsText = ""
    @FocusState private var focus: Field?
    enum Field { case front, back }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: EngramSpacing.section) {
                        if let error = model.error { EngramInlineError(message: error) }
                        if geometry.size.width >= 900 && !textSize.isAccessibilitySize {
                            HStack(alignment: .top, spacing: EngramSpacing.generous) {
                                fields.frame(maxWidth: .infinity)
                                preview.frame(maxWidth: .infinity)
                            }
                        } else {
                            Picker("Editor mode", selection: $previewMode) { Text("Edit").tag(false); Text("Preview").tag(true) }.pickerStyle(.segmented)
                            Group {
                                if previewMode { preview } else { fields }
                            }
                            .id(previewMode)
                            .transition(EngramMotion.contentTransition(reduceMotion: reduceMotion))
                            .animation(EngramMotion.navigation(reduceMotion: reduceMotion), value: previewMode)
                        }
                    }.padding(EngramSpacing.section).frame(maxWidth: 1200).frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(model.draft?.id == nil ? "New card" : "Edit card")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { discardConfirmation = true }.disabled(model.busy) }
                ToolbarItem(placement: .automatic) { ThemeMenu(model: model) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.busy ? "Saving…" : "Save") {
                        Task {
                            await model.saveDraft()
                            if model.error != nil { previewMode = false; focus = model.draft?.front.isEmpty == true || model.draft?.kind == .cloze ? .front : .back }
                        }
                    }.disabled(model.busy || model.draft?.kind == .unsupported).keyboardShortcut("s", modifiers: .command)
                }
            }
            .confirmationDialog("Discard this draft?", isPresented: $discardConfirmation, titleVisibility: .visible) {
                Button("Discard draft", role: .destructive) { model.draft = nil; dismiss() }
                Button("Keep editing", role: .cancel) { }
            } message: { Text("Unsaved changes will be lost. The saved note and review history will not change.") }
            .engramCanvas().task {
                tagsText = model.draft?.tags.joined(separator: " ") ?? ""
                if model.draft?.id == nil { focus = .front }
            }
        }
        .engramSheetSizing(idealWidth: 1050, minimumHeight: 600)
        .interactiveDismissDisabled(model.draft != nil)
    }
    private func draftBinding<T>(_ path: WritableKeyPath<NoteDraft, T>, fallback: T) -> Binding<T> {
        Binding(get: { model.draft?[keyPath: path] ?? fallback }, set: { model.draft?[keyPath: path] = $0 })
    }
    @ViewBuilder private var fields: some View {
        if let draft = model.draft {
            VStack(alignment: .leading, spacing: EngramSpacing.regular) {
                Picker("Card type", selection: draftBinding(\.kind, fallback: .basic)) {
                    Text("Basic").tag(NoteKind.basic); Text("Cloze").tag(NoteKind.cloze)
                    if draft.kind == .reversed { Text("Basic + reverse").tag(NoteKind.reversed) }
                    if draft.kind == .unsupported { Text("Unsupported imported type").tag(NoteKind.unsupported) }
                }.disabled(draft.id != nil)
                if draft.kind == .unsupported {
                    EngramInlineError(message: "This imported template is preserved, but cannot be edited or studied here. Export a backup to keep its original fields and templates.")
                }
                if draft.kind == .cloze {
                    Text("Use {{c1::answer}} or {{c1::answer::hint}}. Each distinct number creates a card; repeated numbers hide together. Siblings keep separate schedules.")
                        .font(theme.font(.metadata))
                }
                Text(draft.kind == .cloze ? "Cloze text" : "Question").font(theme.font(.control))
                TextEditor(text: draftBinding(\.front, fallback: "")).font(theme.font(.body)).frame(minHeight: 140)
                    .scrollContentBackground(.hidden)
                    .focused($focus, equals: .front).accessibilityLabel(draft.kind == .cloze ? "Cloze text" : "Question")
                    .engramSurface(padding: EngramSpacing.compact)
                    .overlay { RoundedRectangle(cornerRadius: EngramShape.study).strokeBorder(theme.palette(for: scheme).controlBorder, lineWidth: focus == .front ? 2 : 1) }
                Text(draft.kind == .cloze ? "Extra explanation (optional)" : "Answer").font(theme.font(.control))
                TextEditor(text: draftBinding(\.back, fallback: "")).font(theme.font(.body)).frame(minHeight: 140)
                    .scrollContentBackground(.hidden)
                    .focused($focus, equals: .back).accessibilityLabel(draft.kind == .cloze ? "Extra explanation" : "Answer")
                    .engramSurface(padding: EngramSpacing.compact)
                    .overlay { RoundedRectangle(cornerRadius: EngramShape.study).strokeBorder(theme.palette(for: scheme).controlBorder, lineWidth: focus == .back ? 2 : 1) }
                Picker("Deck", selection: draftBinding(\.deckID, fallback: "")) { ForEach(model.library.liveDecks) { Text($0.name).tag($0.id) } }
                Text("Tags (space separated)").font(theme.font(.control))
                TextField("plants transport", text: $tagsText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Tags, space separated")
                    .onChange(of: tagsText) { _, value in model.draft?.tags = value.split(whereSeparator: \.isWhitespace).map(String.init) }
                Text("Source / reference (optional)").font(theme.font(.control))
                TextField("Book, chapter or URL", text: draftBinding(\.source, fallback: ""), axis: .vertical)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Source or reference, optional")
                Text("Ordinary text edits and moves preserve existing schedules. Removing a cloze number retires that generated card.")
                    .font(theme.font(.metadata))
            }.disabled(model.busy || draft.kind == .unsupported)
        }
    }
    @ViewBuilder private var preview: some View {
        if let draft = model.draft {
            let ordinals = Result { try CardRenderer.ordinals(for: draft) }
            VStack(alignment: .leading, spacing: EngramSpacing.section) {
                Text("Card preview").font(theme.font(.section)).accessibilityAddTraits(.isHeader)
                switch ordinals {
                case .failure(let error): EngramInlineError(message: error.localizedDescription)
                case .success(let values):
                    let ordinal = values.contains(previewOrdinal) ? previewOrdinal : values[0]
                    if values.count > 1 { Picker("Generated card", selection: $previewOrdinal) { ForEach(values, id: \.self) { Text("Card \($0 + 1)").tag($0) } } }
                    let note = Note(deckID: draft.deckID, kind: draft.kind, front: draft.front, back: draft.back, source: draft.source)
                    let card = StudyCard(noteID: note.id, deckID: note.deckID, ordinal: ordinal,
                        schedule: ScheduleState(schedulerID: "preview", due: model.now, phase: .new))
                    if let content = try? CardRenderer.render(note: note, card: card, revealed: true) {
                        VStack(alignment: .leading, spacing: EngramSpacing.section) {
                            Text("Question").font(theme.font(.metadata))
                            CardContentView(text: content.prompt, media: model.library.media).font(theme.font(.prompt))
                            Divider()
                            Text("Answer").font(theme.font(.metadata))
                            CardContentView(text: content.answer ?? "", media: model.library.media).font(theme.font(.body))
                        }.frame(maxWidth: .infinity, alignment: .leading).engramSurface()
                    }
                }
            }
        }
    }
}
