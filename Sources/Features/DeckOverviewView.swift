import SwiftUI
import LearningCore
import DesignSystem
import UniformTypeIdentifiers
import PhotosUI

/// A single reading surface: memory, practice, then the two ways into a deck's content.
struct DeckOverviewView: View {
    @Bindable var model: EngramModel
    let deckID: String
    @Environment(\.engramWorkspaceLayout) private var workspace
    private enum ContentRoute: String, Identifiable { case questions, notes; var id: String { rawValue } }
    @State private var contentRoute: ContentRoute?
    @State private var showPDFSource = false
    @State private var openedDocument: LibraryDocument?
    @State private var importingDocument = false
    @State private var choosingPhoto = false
    @State private var selectedPhoto: PhotosPickerItem?
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var textSize
    private var palette: EngramPalette { theme.palette(for: scheme) }
    private var deck: Deck? { model.library.liveDecks.first { $0.id == deckID } }
    private var notes: [Note] { model.library.liveNotes.filter { $0.deckID == deckID } }

    var body: some View {
        Group {
            if let deck {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(deck.name.components(separatedBy: "::").last ?? deck.name)
                                .font(theme.font(.title)).accessibilityAddTraits(.isHeader)
                            let cardCount = notes.reduce(0) { $0 + model.cards(for: $1).count }
                            Text("\(cardCount) \(cardCount == 1 ? "card" : "cards") · \(model.due(in: deck).count) ready")
                                .font(.subheadline).foregroundStyle(palette.secondaryText)
                        }
                        if workspace && !textSize.isAccessibilitySize {
                            HStack(alignment: .top, spacing: 24) {
                                DeckMemoryPanel(model: model, deck: deck).frame(maxWidth: .infinity)
                                Divider()
                                studyActions(deck).frame(width: 190)
                            }
                        } else {
                            DeckMemoryPanel(model: model, deck: deck)
                            Button { Task { await model.beginReview(deckID: deck.id) } } label: {
                                HStack { Text("Study notebook"); Spacer(); Image(systemName: "arrow.up.right") }
                                    .font(.subheadline.weight(.semibold)).frame(minHeight:44)
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(model.busy)
                                .accessibilityIdentifier("deck-study")
                            Divider()
                            if textSize.isAccessibilitySize {
                                VStack(spacing: 12) { contentLinks }
                            } else {
                                HStack(alignment: .top, spacing: 20) { contentLinks }
                            }
                            if let documents = deck.documents,!documents.isEmpty {
                                VStack(alignment:.leading,spacing:4) {
                                    Text("Source files").font(theme.font(.section))
                                    ForEach(documents) { document in
                                        Button { openedDocument = document } label: {
                                            HStack(spacing:10) {
                                                Image(systemName:document.kind == .pdf ? "doc.richtext" : document.kind == .image ? "photo" : "doc.text")
                                                    .frame(width:20)
                                                Text(document.name).lineLimit(1)
                                                Spacer(minLength:8)
                                                Image(systemName:"arrow.up.right").font(.caption)
                                            }.font(.subheadline).frame(minHeight:44).contentShape(Rectangle())
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                    }
                    .padding(EngramSpacing.section).padding(.bottom, 12)
                    .frame(maxWidth: workspace ? 1040 : 720).frame(maxWidth: .infinity)
                }
                .engramAssistantClearance()
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Add question", systemImage: "plus") { model.newNote(deckID: deckID) }
                            Button("Edit notes", systemImage: "square.and.pencil") { openNotes() }
                            Button("Add PDF or Markdown", systemImage:"doc.badge.plus") { importingDocument = true }
                            Button("Add image from Photos",systemImage:"photo.on.rectangle") { selectedPhoto = nil; choosingPhoto = true }
                            Button("Rename deck", systemImage: "pencil") { model.deckForm = DeckForm(deck: deck) }
                            if deck.pdfLearning != nil {
                                Button("PDF source pages", systemImage: "doc.text.magnifyingglass") { showPDFSource = true }
                            }
                            NavigationLink { DeckSharingView(model:model,deckID:deckID) } label: { Label("Share deck",systemImage:"person.2") }
                            Button("Delete deck", systemImage: "trash", role: .destructive) { model.deleteDeck = deck }
                        } label: { Image(systemName: "gearshape").frame(minWidth: 44, minHeight: 44) }
                            .accessibilityLabel("Deck actions").accessibilityIdentifier("deck-actions")
                            .disabled(model.busy)
                    }
                }
            } else {
                EngramEmptyState(title: "Deck unavailable", message: "This deck may have been removed.")
            }
        }
        .navigationTitle("").engramInlineTitle().engramCanvas()
        .sheet(isPresented: $showPDFSource) {
            if let source = deck?.pdfLearning?.source { PDFSourcePagesView(source: source) }
        }
        .sheet(item:$openedDocument) { document in LibraryDocumentReader(document:document) }
        .photosPicker(isPresented:$choosingPhoto,selection:$selectedPhoto,matching:.images)
        .onChange(of:selectedPhoto) { _,photo in
            guard let photo else { return }
            Task {
                defer { selectedPhoto = nil }
                do {
                    guard let data = try await photo.loadTransferable(type:Data.self) else { throw EngramError.invalid("The selected photo could not be read.") }
                    let name = "Photo-" + String(UUID().uuidString.prefix(8)) + ".jpg"
                    let document = try await Task.detached(priority:.userInitiated) { try LibraryDocumentImport.image(data:data,name:name) }.value
                    _ = await model.perform { try await $0.addDocument(document,to:deckID) }
                } catch { model.error = "The photo could not be imported. \(error.localizedDescription)" }
            }
        }
        .fileImporter(isPresented:$importingDocument,
                      allowedContentTypes:[.pdf,UTType(filenameExtension:"md") ?? .plainText,.image],
                      allowsMultipleSelection:true) { result in
            Task {
                do {
                    for url in try result.get() {
                        let document = try await Task.detached(priority:.userInitiated) { try LibraryDocumentImport.read(url) }.value
                        guard await model.perform({ try await $0.addDocument(document,to:deckID) }) else { return }
                    }
                } catch { model.error = "The source file could not be imported. \(error.localizedDescription)" }
            }
        }
        .navigationDestination(item: $contentRoute) { route in
            switch route {
            case .questions: DeckQuestionsView(model: model, deckID: deckID)
            case .notes: NotebookView(model: model, deckID: deckID, writingOnly: true)
            }
        }
        .onAppear { model.selectedDeckID = deckID; model.activeDeckOverviewID = deckID }
        .onDisappear { if model.activeDeckOverviewID == deckID { model.activeDeckOverviewID = nil } }
    }

    private func studyActions(_ deck: Deck) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            Button { Task { await model.beginReview(deckID: deck.id) } } label: {
                HStack { Text("Study notebook"); Spacer(); Image(systemName: "arrow.up.right") }
                    .font(.subheadline.weight(.semibold)).frame(minHeight:44)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(model.busy)
                .accessibilityIdentifier("deck-study")
            Divider()
            if textSize.isAccessibilitySize || workspace {
                VStack(spacing: 12) { contentLinks }
            } else {
                HStack(alignment: .top, spacing: 20) { contentLinks }
            }
            if let documents = deck.documents,!documents.isEmpty {
                VStack(alignment:.leading,spacing:4) {
                    Text("Source files").font(theme.font(.section))
                    ForEach(documents) { document in
                        Button { openedDocument = document } label: {
                            HStack(spacing:10) {
                                Image(systemName:document.kind == .pdf ? "doc.richtext" : document.kind == .image ? "photo" : "doc.text")
                                    .frame(width:20)
                                Text(document.name).lineLimit(1)
                                Spacer(minLength:8)
                                Image(systemName:"arrow.up.right").font(.caption)
                            }.font(.subheadline).frame(minHeight:44).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var contentLinks: some View {
        Group {
            contentLink("Questions", detail: "\(notes.count) to explore", symbol: "rectangle.stack", identifier: "deck-questions") {
                contentRoute = .questions
            }
            contentLink("Notes", detail: "Read and relearn", symbol: "book.pages", identifier: "deck-notes", action: openNotes)
        }
    }
    private func contentLink(_ title: String, detail: String, symbol: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol).font(.title3).foregroundStyle(scheme == .dark ? palette.easyInk : palette.anchor)
                HStack { Text(title).font(.headline); Spacer(minLength: 4); Image(systemName: "arrow.up.right").font(.caption) }
                Text(detail).font(.caption).foregroundStyle(palette.secondaryText)
            }.frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier(identifier)
    }
    private func openNotes() { contentRoute = .notes }
}

struct DeckQuestionsView: View {
    @Bindable var model: EngramModel
    let deckID: String
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: EngramPalette { theme.palette(for: scheme) }
    private var notes: [Note] { model.library.liveNotes.filter { $0.deckID == deckID } }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    Text(model.deckName(deckID).replacingOccurrences(of: "::", with: " / "))
                        .font(.subheadline).foregroundStyle(palette.secondaryText)
                    if notes.isEmpty {
                        EngramEmptyState(title: "Your first question", message: "Add a question to start practising this deck.")
                        Button("Add question") { model.newNote(deckID: deckID) }.buttonStyle(EngramButtonStyle())
                    }
                    ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                        VStack(alignment: .leading, spacing: 12) {
                            QuestionReadingView(front: note.front, back: note.back, number: index + 1, media: model.library.media)
                            if !note.source.isEmpty {
                                DisclosureGroup("Source evidence") { Text(note.source).font(.caption).textSelection(.enabled) }
                                    .font(.caption).foregroundStyle(palette.secondaryText)
                            }
                            HStack {
                                Button("Edit question") {
                                    // Questions has its own reading destination; editing uses the existing card editor.
                                    model.draft = NoteDraft(note: note); model.editorPresented = true
                                }.font(.caption).frame(minHeight: 44)
                                Spacer()
                                Menu {
                                    ForEach(model.cards(for: note)) { card in
                                        Button(card.suspended ? "Resume card \(card.ordinal + 1)" : "Suspend card \(card.ordinal + 1)") {
                                            Task { _ = await model.perform { try await $0.setSuspended(cardID: card.id, suspended: !card.suspended) } }
                                        }
                                    }
                                    Button("Delete question", role: .destructive) { model.deleteNote = note }
                                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                                    .accessibilityLabel("Question \(index + 1) actions")
                            }.foregroundStyle(palette.secondaryText).disabled(model.busy)
                            Divider()
                        }.id(note.id).accessibilityIdentifier("question-\(note.id)")
                            .background(GeometryReader { geometry in
                                Color.clear.preference(key: VisibleQuestionPositions.self,
                                    value:[note.id:geometry.frame(in:.named("questions-scroll")).minY])
                            })
                    }
                }.padding(EngramSpacing.section).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
            .coordinateSpace(name:"questions-scroll")
            .onPreferenceChange(VisibleQuestionPositions.self) { positions in
                model.visibleQuestionID = positions.min(by: { abs($0.value - 130) < abs($1.value - 130) })?.key
            }
            .engramAssistantClearance()
            .onAppear {
                if let id = model.notebookFocusNoteID { proxy.scrollTo(id, anchor: .top); model.notebookFocusNoteID = nil }
            }
            .onChange(of: model.notebookFocusNoteID) { _, id in
                if let id { proxy.scrollTo(id, anchor: .top); model.notebookFocusNoteID = nil }
            }
        }
        .navigationTitle("Questions").engramInlineTitle().engramCanvas().engramHideStudyTabs()
        .onAppear { model.activeContentDeckID = deckID; model.activeContentKind = "questions" }
        .onDisappear { if model.activeContentDeckID == deckID { model.activeContentDeckID = nil; model.activeContentKind = nil }; model.visibleQuestionID = nil }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { model.newNote(deckID: deckID) } label: { Label("Add question", systemImage: "plus") }
                    .disabled(model.busy)
            }
        }
    }
}

private struct VisibleQuestionPositions: PreferenceKey {
    static var defaultValue: [String:CGFloat] = [:]
    static func reduce(value: inout [String:CGFloat], nextValue: () -> [String:CGFloat]) {
        value.merge(nextValue(),uniquingKeysWith: { _,latest in latest })
    }
}

/// Shared structured Q&A typography for reading; deliberately separate from review selection UI.
struct QuestionReadingView: View {
    let front: String
    let back: String
    var number: Int? = nil
    var media: [MediaFile] = []
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: EngramPalette { theme.palette(for: scheme) }
    private var correctInk: Color { palette.successInk }
    private var prefix: String { number.map { "\($0). " } ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let question = MultipleChoiceQuestion.parse(front: front, back: back) {
                Text(prefix + question.prompt).font(.body.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(question.choices) { choice in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(choice.id + ")").fixedSize(horizontal: true, vertical: false)
                                .frame(minWidth: 24, alignment: .leading)
                            Text(choice.text).frame(maxWidth: .infinity, alignment: .leading)
                            if choice.id == question.correctID { Image(systemName: "checkmark").font(.caption.weight(.semibold)).accessibilityHidden(true) }
                        }
                        .font(.subheadline.italic())
                        .foregroundStyle(choice.id == question.correctID ? correctInk : palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(choice.id == question.correctID ? "Correct answer" : "")
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Answer \(question.correctID)").font(.subheadline.weight(.semibold)).foregroundStyle(correctInk)
                    Text(question.explanation).font(.subheadline).foregroundStyle(correctInk).lineSpacing(4).textSelection(.enabled)
                }
            } else {
                CardContentView(text: prefix + front, media: media).font(.body.weight(.bold))
                VStack(alignment: .leading, spacing: 8) {
                    Text("Answer").font(.subheadline.weight(.semibold)).foregroundStyle(correctInk)
                    CardContentView(text: back, media: media, ink: correctInk).font(.subheadline)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
