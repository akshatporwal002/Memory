import SwiftUI
import LearningCore
import DesignSystem

/// A single reading surface: memory, practice, then the two ways into a deck's content.
struct DeckOverviewView: View {
    @Bindable var model: EngramModel
    let deckID: String
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
                            Text("\(notes.reduce(0) { $0 + model.cards(for: $1).count }) cards · \(model.due(in: deck).count) ready")
                                .font(.subheadline).foregroundStyle(palette.secondaryText)
                        }
                        DeckMemoryPanel(model: model, deck: deck)
                            .accessibilityIdentifier("deck-memory-outlook")
                        Button { Task { await model.beginReview(deckID: deck.id) } } label: {
                            HStack { Text("Study deck"); Spacer(); Image(systemName: "arrow.right") }
                        }.buttonStyle(EngramButtonStyle()).disabled(model.busy)
                            .accessibilityIdentifier("deck-study")
                        Divider()
                        if textSize.isAccessibilitySize {
                            VStack(spacing: 12) { contentLinks }
                        } else {
                            HStack(alignment: .top, spacing: 20) { contentLinks }
                        }
                    }
                    .padding(EngramSpacing.section).padding(.bottom, 12)
                    .frame(maxWidth: 720).frame(maxWidth: .infinity)
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Add question", systemImage: "plus") { model.newNote(deckID: deckID) }
                            Button("Edit notes", systemImage: "square.and.pencil") { openNotes() }
                            Button("Rename deck", systemImage: "pencil") { model.deckForm = DeckForm(deck: deck) }
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
        .onAppear { model.selectedDeckID = deckID; model.activeDeckOverviewID = deckID }
        .onDisappear { if model.activeDeckOverviewID == deckID { model.activeDeckOverviewID = nil } }
    }

    private var contentLinks: some View {
        Group {
            contentLink("Questions", detail: "\(notes.count) to explore", symbol: "rectangle.stack", identifier: "deck-questions") {
                model.questionsDeckID = deckID
            }
            contentLink("Notes", detail: "Read and relearn", symbol: "book.pages", identifier: "deck-notes", action: openNotes)
        }
    }
    private func contentLink(_ title: String, detail: String, symbol: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol).font(.title3).foregroundStyle(palette.anchor)
                HStack { Text(title).font(.headline); Spacer(minLength: 4); Image(systemName: "arrow.up.right").font(.caption) }
                Text(detail).font(.caption).foregroundStyle(palette.secondaryText)
            }.frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier(identifier)
    }
    private func openNotes() { model.notebookWritingOnly = true; model.notebookDeckID = deckID }
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
                    }
                }.padding(EngramSpacing.section).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
            .onAppear {
                if let id = model.notebookFocusNoteID { proxy.scrollTo(id, anchor: .top); model.notebookFocusNoteID = nil }
            }
        }
        .navigationTitle("Questions").engramInlineTitle().engramCanvas().engramHideStudyTabs()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { model.newNote(deckID: deckID) } label: { Label("Add question", systemImage: "plus") }
                    .disabled(model.busy)
            }
        }
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
    private var correctInk: Color { scheme == .dark ? Color(red: 0.72, green: 0.87, blue: 0.66) : Color(red: 0.20, green: 0.36, blue: 0.22) }
    private var prefix: String { number.map { "\($0). " } ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let question = MultipleChoiceQuestion.parse(front: front, back: back) {
                Text(prefix + question.prompt).font(.body.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(question.choices) { choice in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(choice.id + ")").frame(width: 24, alignment: .leading)
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
                if !prefix.isEmpty { Text(prefix + "Question").font(.caption).foregroundStyle(palette.secondaryText) }
                CardContentView(text: front, media: media).font(.body.weight(.bold))
                VStack(alignment: .leading, spacing: 8) {
                    Text("Answer").font(.subheadline.weight(.semibold)).foregroundStyle(correctInk)
                    CardContentView(text: back, media: media).font(.subheadline)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
