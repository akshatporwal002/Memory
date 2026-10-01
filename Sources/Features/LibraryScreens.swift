import SwiftUI
import LearningCore
import DesignSystem

struct TodayView: View {
    @Bindable var model: EngramModel
    var showsPageTitle = false
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: EngramPalette { theme.palette(for: scheme) }
    private var readingDeck: Deck? {
        if let recent = UserDefaults.standard.string(forKey: "engram.notebook.lastDeckID"),
           let deck = model.library.liveDecks.first(where: { $0.id == recent }) { return deck }
        return model.library.liveDecks.first { deck in
            NotebookDocument.blocks(for: deck, in: model.library).contains { $0.kind == .text && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        } ?? model.library.liveDecks.first
    }
    private func readingTitle(_ deck: Deck) -> String {
        let blocks = NotebookDocument.blocks(for: deck, in: model.library)
        let saved = UserDefaults.standard.string(forKey: "engram.notebook.readingSection." + deck.id)
        let block = blocks.first { $0.id == saved } ?? blocks.first { $0.kind == .text } ?? blocks.first
        return String((block?.text ?? "Open your notes and questions").prefix(75))
    }
    private var missedNote: Note? {
        let failed = model.library.activeReviews.reversed().first { $0.rating == .again || $0.rating == .hard }
        let card = model.library.liveCards.first { $0.id == failed?.cardID }
        return model.library.liveNotes.first { $0.id == card?.noteID }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if showsPageTitle {
                    Text("Today").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                }
                Text(model.now.formatted(date: .complete, time: .omitted))
                    .font(theme.font(.metadata)).foregroundStyle(palette.secondaryText)
                if model.library.liveDecks.isEmpty {
                    EngramEmptyState(title: "Your first deck", message: "Save a question you want to remember. Your library stays on this device.")
                    Button("Create a deck") { model.creationPresented = true }.buttonStyle(EngramButtonStyle())
                } else {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(model.due.count) cards ready").font(.headline)
                            Text("\(model.due.filter { $0.schedule.phase != .new }.count) due · \(model.due.filter { $0.schedule.phase == .new }.count) new")
                                .font(.subheadline).foregroundStyle(palette.secondaryText)
                        }
                        Spacer(minLength: 4)
                        Button("Review") { Task { await model.beginReview() } }
                            .buttonStyle(EngramButtonStyle(.secondary)).disabled(model.busy)
                    }
                    .padding(16).background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
                    if model.library.session?.current != nil {
                        Button { Task { await model.resumeReview() } } label: { Label("Resume saved session", systemImage: "arrow.uturn.forward") }
                            .buttonStyle(EngramButtonStyle(.secondary)).disabled(model.busy)
                    }
                    if let deck = readingDeck {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Pick up your notebook").font(theme.font(.section))
                            Button {
                                model.notebookDeckID = deck.id
                            } label: {
                                VStack(alignment: .leading, spacing: 16) {
                                    Text(deck.name.replacingOccurrences(of: "::", with: " / "))
                                        .font(.caption).foregroundStyle(palette.secondaryText)
                                    Text(readingTitle(deck))
                                        .font(.system(.title2, design: .serif)).lineLimit(3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Label("Continue reading", systemImage: "arrow.right")
                                        .font(.subheadline.weight(.medium)).foregroundStyle(palette.accentInk)
                                }
                                .padding(22).frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
                                .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(alignment: .leading) { Rectangle().fill(palette.accent).frame(width: 2).padding(.vertical, 16) }
                            }.buttonStyle(.plain)
                        }
                    }
                    if let note = missedNote {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Worth another look").font(theme.font(.section))
                            Button {
                                model.notebookFocusNoteID = note.id
                                model.notebookDeckID = note.deckID
                            } label: {
                                HStack { Text(note.front).lineLimit(2); Spacer(); Image(systemName: "arrow.right") }
                                    .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }.buttonStyle(.plain)
                            Text("A recent answer was difficult. Revisit its source before practising again.")
                                .font(.caption).foregroundStyle(palette.secondaryText)
                        }
                    }
                }
            }
            .frame(maxWidth: 720, alignment: .leading).padding(EngramSpacing.section).frame(maxWidth: .infinity)
        }
    }
}

struct DeckRow: View {
    let model: EngramModel
    let deck: Deck
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: EngramSpacing.regular) {
            Image(systemName: "rectangle.stack").frame(width: 44, height: 44)
                .background(theme.palette(for: scheme).selection, in: Circle()).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: EngramSpacing.micro) {
                Text(deck.name).font(theme.font(.section)).fixedSize(horizontal: false, vertical: true)
                let cards = model.due(in: deck)
                Text("\(cards.filter { $0.schedule.phase != .new }.count) due · \(cards.filter { $0.schedule.phase == .new }.count) new")
                    .font(theme.font(.metadata)).foregroundStyle(theme.palette(for: scheme).secondaryText)
                    .engramNumericTransition(value: cards.count)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
        }.padding(.vertical, EngramSpacing.regular).contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
}

struct LibraryView: View {
    @Bindable var model: EngramModel
    var deckScoped = false
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 850 && !textSize.isAccessibilitySize
            HStack(spacing: 0) {
                libraryList(wide: wide)
                    .frame(minWidth: wide ? 280 : nil, idealWidth: wide ? 320 : nil, maxWidth: wide ? 360 : .infinity)
                if wide {
                    Divider()
                    if let note = model.visibleNotes.first(where: { $0.id == model.selectedNoteID }) {
                        LibraryNoteDetail(model: model, note: note)
                            .id(note.id)
                            .transition(EngramMotion.contentTransition(reduceMotion: reduceMotion))
                            .frame(maxWidth: .infinity)
                    } else {
                        EngramEmptyState(title: "A closer look", message: "Select a note to see its cards, content and study progress.", symbol: "rectangle.split.2x1")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .animation(EngramMotion.navigation(reduceMotion: reduceMotion), value: model.selectedNoteID)
        }
    }
    private func libraryList(wide: Bool) -> some View {
        VStack(spacing: 0) {
            if model.library.liveDecks.isEmpty {
                Spacer()
                EngramEmptyState(title: "A home for your knowledge", message: "Create a deck, then add a question and answer.")
                Button("Create a deck") { model.creationPresented = true }.buttonStyle(EngramButtonStyle())
                Spacer()
            } else {
                List {
                    Section {
                        if !deckScoped {
                            Picker("Deck", selection: $model.selectedDeckID) {
                                Text("All decks").tag(String?.none)
                                ForEach(model.library.liveDecks) { Text($0.name).tag(Optional($0.id)) }
                            }
                        }
                        if let deck = model.library.liveDecks.first(where: { $0.id == model.selectedDeckID }) {
                            DeckRow(model: model, deck: deck)
                            DeckMemoryPanel(model: model, deck: deck).listRowSeparator(.hidden)
                            HStack {
                                Button("Study deck") { Task { await model.beginReview(deckID: deck.id) } }
                                Spacer()
                                Menu("Deck actions") {
                                    Button("Rename deck") { model.deckForm = DeckForm(deck: deck) }
                                    Button("Delete deck", role: .destructive) { model.deleteDeck = deck }
                                }
                            }.disabled(model.busy)
                            Button { model.notebookDeckID = deck.id } label: {
                                Label("Open notebook", systemImage: "book.pages")
                            }.frame(minHeight: EngramShape.touchTarget)
                        }
                    }
                    Section("\(model.visibleNotes.count) notes") {
                        if model.visibleNotes.isEmpty {
                            Text(model.search.isEmpty ? "No notes yet. Add a basic or cloze card to start." : "No matching notes. Try fewer terms or a different deck.")
                                .foregroundStyle(theme.palette(for: scheme).secondaryText)
                        }
                        ForEach(model.visibleNotes) { note in
                            VStack(alignment: .leading, spacing: EngramSpacing.small) {
                                Button {
                                    model.selectedNoteID = note.id
                                    model.selectedCardID = model.cards(for: note).first?.id
                                    if !wide { model.edit(note) }
                                } label: {
                                    VStack(alignment: .leading, spacing: EngramSpacing.small) {
                                        Text(note.front).font(theme.font(.body)).lineLimit(3)
                                        Text("\(model.deckName(note.deckID)) · \(note.kind.rawValue.capitalized)")
                                            .font(theme.font(.metadata)).foregroundStyle(theme.palette(for: scheme).secondaryText)
                                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityValue(wide && model.selectedNoteID == note.id ? "Selected" : "")
                                if !note.tags.isEmpty {
                                    Text(note.tags.map { "#" + $0 }.joined(separator: " ")).font(theme.font(.metadata)).foregroundStyle(theme.palette(for: scheme).accentInk)
                                }
                                ForEach(model.cards(for: note)) { card in
                                    HStack(alignment: .firstTextBaseline) {
                                        Text("Card \(card.ordinal + 1) · \(card.suspended ? "Suspended" : card.schedule.phase == .new ? "New" : card.schedule.due <= model.now ? "Due" : card.schedule.due.formatted(date: .abbreviated, time: .omitted))")
                                            .font(theme.font(.metadata))
                                        Spacer()
                                        Button(card.suspended ? "Resume" : "Suspend") {
                                            Task { _ = await model.perform { try await $0.setSuspended(cardID: card.id, suspended: !card.suspended) } }
                                        }.font(theme.font(.metadata)).frame(minHeight: EngramShape.touchTarget).disabled(model.busy)
                                    }
                                }
                            }
                            .padding(.vertical, EngramSpacing.small)
                            .listRowBackground(wide && model.selectedNoteID == note.id ? theme.palette(for: scheme).selection : theme.palette(for: scheme).canvas)
                            .contextMenu {
                                Button("Edit note") { model.edit(note) }
                                Button("Delete note and cards", role: .destructive) { model.deleteNote = note }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .searchable(text: $model.search, prompt: "Search notes, tag:plants, is:suspended")
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if !deckScoped { Button { model.creationPresented = true } label: { Label("New deck", systemImage: "folder.badge.plus") } }
                Button { model.newNote() } label: { Label("Add card", systemImage: "plus") }
                    .disabled(model.library.liveDecks.isEmpty).keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

struct LibraryNoteDetail: View {
    @Bindable var model: EngramModel
    let note: Note
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EngramSpacing.section) {
                Text(model.deckName(note.deckID)).font(theme.font(.metadata)).foregroundStyle(theme.palette(for: scheme).secondaryText)
                Text("Card detail").font(theme.font(.title)).accessibilityAddTraits(.isHeader)
                HStack {
                    Button("Edit note") { model.edit(note) }.buttonStyle(EngramButtonStyle(.secondary))
                    Spacer()
                    Menu("Note actions") { Button("Delete note and cards", role: .destructive) { model.deleteNote = note } }
                }
                let cards = model.cards(for: note)
                if let card = cards.first(where: { $0.id == model.selectedCardID }) ?? cards.first {
                    if cards.count > 1 {
                        Picker("Generated card", selection: Binding(get: { card.id }, set: { model.selectedCardID = $0 })) {
                            ForEach(cards) { Text("Card \($0.ordinal + 1)").tag($0.id) }
                        }
                    }
                    let rendered = Result { try CardRenderer.render(note: note, card: card, revealed: true) }
                    switch rendered {
                    case .success(let content):
                        VStack(alignment: .leading, spacing: EngramSpacing.section) {
                            Text("Question").font(theme.font(.metadata))
                            CardContentView(text: content.prompt, media: model.library.media).font(theme.font(.body))
                            Divider()
                            Text("Answer").font(theme.font(.metadata))
                            CardContentView(text: content.answer ?? "", media: model.library.media).font(theme.font(.body))
                        }.frame(maxWidth: .infinity, alignment: .leading).engramSurface()
                    case .failure(let error): EngramInlineError(message: error.localizedDescription)
                    }
                    LabeledContent("State", value: card.suspended ? "Suspended" : card.schedule.phase.rawValue.capitalized)
                    if card.schedule.phase != .new { LabeledContent("Next due", value: card.schedule.due.formatted(date: .abbreviated, time: .shortened)) }
                    LabeledContent("Saved reviews", value: String(model.library.activeReviews.filter { $0.cardID == card.id }.count))
                    Button(card.suspended ? "Resume card" : "Suspend card") {
                        Task { _ = await model.perform { try await $0.setSuspended(cardID: card.id, suspended: !card.suspended) } }
                    }.buttonStyle(EngramButtonStyle(.secondary)).disabled(model.busy)
                } else {
                    Text("This note has no active generated cards. Edit it to add a supported question or cloze marker.")
                }
                if !note.tags.isEmpty { Text(note.tags.map { "#" + $0 }.joined(separator: " ")).font(theme.font(.metadata)) }
                if !note.source.isEmpty { Text("Reference: " + note.source).font(theme.font(.metadata)).textSelection(.enabled) }
            }.frame(maxWidth: EngramShape.readingWidth, alignment: .leading).padding(EngramSpacing.section).frame(maxWidth: .infinity)
        }
    }
}
