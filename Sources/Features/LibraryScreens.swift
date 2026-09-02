import SwiftUI
import LearningCore
import DesignSystem

struct TodayView: View {
    @Bindable var model: EngramModel
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EngramSpacing.section) {
                Text(model.now.formatted(date: .complete, time: .omitted)).font(theme.font(.metadata)).foregroundStyle(theme.palette(for: scheme).secondaryText)
                Text("A little study,\na lasting memory.").font(theme.font(.hero)).accessibilityAddTraits(.isHeader)
                if model.library.liveDecks.isEmpty {
                    EngramEmptyState(title: "Your first deck", message: "Save a question you want to remember. Your library stays on this device.")
                    Button("Create a deck") { model.deckForm = DeckForm() }.buttonStyle(EngramButtonStyle())
                } else {
                    VStack(alignment: .leading, spacing: EngramSpacing.regular) {
                        Text("READY WHEN YOU ARE").font(theme.font(.metadata))
                        Text(model.due.count, format: .number).font(theme.font(.hero)).monospacedDigit()
                        Text("cards available now").font(theme.font(.section))
                        Text("\(model.due.filter { $0.schedule.phase == .new }.count) new · \(model.due.filter { $0.schedule.phase != .new }.count) due, within daily limits")
                            .font(theme.font(.metadata))
                        Button(model.due.isEmpty ? "Check study queue" : "Start review") { Task { await model.beginReview() } }
                            .buttonStyle(EngramButtonStyle(.secondary)).disabled(model.busy)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(EngramSpacing.section)
                    .foregroundStyle(theme.palette(for: scheme).onAnchor)
                    .background(theme.palette(for: scheme).anchor, in: RoundedRectangle(cornerRadius: EngramShape.study, style: .continuous))
                    if model.library.session?.current != nil {
                        Button { Task { await model.resumeReview() } } label: { Label("Resume saved session", systemImage: "arrow.uturn.forward") }
                            .buttonStyle(EngramButtonStyle(.secondary)).disabled(model.busy)
                    }
                    HStack { Text("Your decks").font(theme.font(.section)); Spacer(); Button("New deck") { model.deckForm = DeckForm() } }
                    LazyVStack(spacing: 0) {
                        ForEach(model.library.liveDecks.prefix(6)) { deck in
                            Button { model.selectedDeckID = deck.id; model.destination = .library } label: { DeckRow(model: model, deck: deck) }.buttonStyle(.plain)
                            Divider()
                        }
                    }
                    Text("\(model.todaysReviews.count) reviews saved today").font(theme.font(.body))
                    Text("Each installation has its own library. Export a backup to protect your cards and review history.")
                        .font(theme.font(.metadata)).foregroundStyle(theme.palette(for: scheme).secondaryText)
                }
            }
            .frame(maxWidth: 1000, alignment: .leading).padding(EngramSpacing.section).frame(maxWidth: .infinity)
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
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
        }.padding(.vertical, EngramSpacing.regular).contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
}

struct LibraryView: View {
    @Bindable var model: EngramModel
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(spacing: 0) {
            if model.library.liveDecks.isEmpty {
                Spacer()
                EngramEmptyState(title: "A home for your knowledge", message: "Create a deck, then add a question and answer.")
                Button("Create a deck") { model.deckForm = DeckForm() }.buttonStyle(EngramButtonStyle())
                Spacer()
            } else {
                List {
                    Section {
                        Picker("Deck", selection: $model.selectedDeckID) {
                            Text("All decks").tag(String?.none)
                            ForEach(model.library.liveDecks) { Text($0.name).tag(Optional($0.id)) }
                        }
                        if let deck = model.library.liveDecks.first(where: { $0.id == model.selectedDeckID }) {
                            DeckRow(model: model, deck: deck)
                            HStack {
                                Button("Study deck") { Task { await model.beginReview(deckID: deck.id) } }
                                Spacer()
                                Menu("Deck actions") {
                                    Button("Rename deck") { model.deckForm = DeckForm(deck: deck) }
                                    Button("Delete deck", role: .destructive) { model.deleteDeck = deck }
                                }
                            }.disabled(model.busy)
                        }
                    }
                    Section("\(model.visibleNotes.count) notes") {
                        if model.visibleNotes.isEmpty {
                            Text(model.search.isEmpty ? "No notes yet. Add a basic or cloze card to start." : "No matching notes. Try fewer terms or a different deck.")
                                .foregroundStyle(theme.palette(for: scheme).secondaryText)
                        }
                        ForEach(model.visibleNotes) { note in
                            VStack(alignment: .leading, spacing: EngramSpacing.small) {
                                Button { model.edit(note) } label: {
                                    VStack(alignment: .leading, spacing: EngramSpacing.small) {
                                        Text(note.front).font(theme.font(.body)).lineLimit(3)
                                        Text("\(model.deckName(note.deckID)) · \(note.kind.rawValue.capitalized)")
                                            .font(theme.font(.metadata)).foregroundStyle(theme.palette(for: scheme).secondaryText)
                                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(.plain)
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
                                        }.font(theme.font(.metadata)).disabled(model.busy)
                                    }
                                }
                            }
                            .padding(.vertical, EngramSpacing.small)
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
                Button { model.deckForm = DeckForm() } label: { Label("New deck", systemImage: "folder.badge.plus") }
                Button { model.newNote() } label: { Label("Add card", systemImage: "plus") }
                    .disabled(model.library.liveDecks.isEmpty).keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

struct ActivityView: View {
    let model: EngramModel
    @Environment(\.engramTheme) private var theme
    var body: some View {
        List {
            Section("Today") {
                LabeledContent("Reviews saved", value: String(model.todaysReviews.count))
                LabeledContent("Cards reviewed", value: String(Set(model.todaysReviews.map(\.cardID)).count))
            }
            Section("Recent reviews") {
                if model.library.activeReviews.isEmpty {
                    EngramEmptyState(title: "Your learning, over time", message: "Reviews appear here after you study. There are no reviews yet.", symbol: "chart.bar.xaxis")
                }
                ForEach(model.library.activeReviews.sorted { $0.reviewedAt > $1.reviewedAt }.prefix(100)) { event in
                    VStack(alignment: .leading, spacing: EngramSpacing.micro) {
                        Text("\(event.rating.label) · \(model.deckName(event.deckID))").font(theme.font(.body))
                        Text(event.reviewedAt.formatted(date: .abbreviated, time: .shortened)).font(theme.font(.metadata))
                    }
                }
            }
            if !model.library.importedReviews.isEmpty {
                Section("Imported evidence") { Text("\(model.library.importedReviews.count) original Anki review records are preserved separately in your library and complete backups.") }
            }
        }.scrollContentBackground(.hidden)
    }
}
