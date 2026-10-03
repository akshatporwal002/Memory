import SwiftUI
import LearningCore
import DesignSystem
import StudyApplication

struct TodayView: View {
    @Bindable var model: EngramModel
    var showsPageTitle = false
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EngramSpacing.section) {
                if showsPageTitle {
                    Text("Today").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                }
                Text(model.now.formatted(date: .complete, time: .omitted)).font(theme.font(.metadata)).foregroundStyle(theme.palette(for: scheme).secondaryText)
                Text("A little study,\na lasting memory.").font(theme.font(.hero)).accessibilityAddTraits(.isHeader)
                if model.library.liveDecks.isEmpty {
                    EngramEmptyState(title: "Your first deck", message: "Save a question you want to remember. Your library stays on this device.")
                    Button("Create a deck") { model.creationPresented = true }.buttonStyle(EngramButtonStyle())
                } else {
                    VStack(alignment: .leading, spacing: EngramSpacing.regular) {
                        Text("READY WHEN YOU ARE").font(theme.font(.metadata))
                        Text(model.due.count, format: .number).font(theme.font(.hero)).monospacedDigit()
                            .engramNumericTransition(value: model.due.count)
                        Text("cards available now").font(theme.font(.section))
                        Text("\(model.due.filter { $0.schedule.phase == .new }.count) new · \(model.due.filter { $0.schedule.phase != .new }.count) due, within daily limits")
                            .font(theme.font(.metadata))
                        Button { Task { await model.beginReview() } } label: {
                            HStack(spacing:8) {
                                Text(model.due.isEmpty ? "Check study queue" : "Start review")
                                Image(systemName:"arrow.up.right").font(.caption)
                            }.font(.subheadline.weight(.semibold)).frame(minHeight:44)
                        }.buttonStyle(.plain).disabled(model.busy)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(EngramSpacing.section)
                    .foregroundStyle(theme.palette(for: scheme).onAnchor)
                    .background(theme.palette(for: scheme).anchor, in: RoundedRectangle(cornerRadius: EngramShape.study, style: .continuous))
                    if model.library.session?.current != nil {
                        Button { Task { await model.resumeReview() } } label: {
                            Label("Resume saved session", systemImage: "arrow.uturn.forward")
                                .font(.subheadline.weight(.medium)).frame(minHeight:44)
                        }.buttonStyle(.plain).disabled(model.busy)
                    }
                    Text("Your notebooks").font(theme.font(.section))
                    LazyVStack(spacing: 0) {
                        ForEach(model.library.liveDecks.prefix(6)) { deck in
                            Button { model.selectedDeckID = deck.id; model.libraryDeckRequest = deck.id; model.destination = .library } label: { DeckRow(model: model, deck: deck) }.buttonStyle(.plain)
                            Divider()
                        }
                    }
                    Text("\(model.todaysReviews.count) reviews saved today").font(theme.font(.body))
                        .engramNumericTransition(value: model.todaysReviews.count)
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
                    .engramNumericTransition(value: cards.count)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
        }.padding(.vertical, EngramSpacing.regular).contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
}

struct LibraryView: View {
    @Bindable var model: EngramModel
    var portabilityAction: (() -> Void)?
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: EngramPalette { theme.palette(for: scheme) }
    @State private var retention: [String:Double] = [:]
    private var decks: [Deck] {
        guard !model.search.isEmpty else { return model.library.liveDecks }
        return model.library.liveDecks.filter { deck in
            deck.name.localizedCaseInsensitiveContains(model.search) ||
                model.library.liveNotes.contains { $0.deckID == deck.id && ($0.front + " " + $0.back).localizedCaseInsensitiveContains(model.search) }
        }
    }
    var body: some View {
        Group {
            if let id = model.selectedDeckID {
                DeckOverviewView(model: model, deckID: id)
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Button("All decks") { model.selectedDeckID = nil; model.libraryDeckRequest = nil }
                        }
                    }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: EngramSpacing.regular) {
                        if model.library.liveDecks.isEmpty {
                            EngramEmptyState(title: "A home for your knowledge", message: "Create a deck, then add a question and answer.")
                            Button("Create a deck") { model.creationPresented = true }.buttonStyle(EngramButtonStyle())
                        } else {
                            ForEach(decks) { deck in
                                Button { model.selectedDeckID = deck.id } label: { directoryRow(deck) }.buttonStyle(.plain)
                                Divider()
                            }
                            if decks.isEmpty { Text("No matching decks").foregroundStyle(palette.secondaryText) }
                        }
                        if let portabilityAction {
                            Button("Import or export library", action: portabilityAction)
                                .font(.caption).foregroundStyle(palette.secondaryText).frame(minHeight: 44)
                                .accessibilityIdentifier("library-import-export")
                        }
                    }.padding(EngramSpacing.section).frame(maxWidth: 760).frame(maxWidth: .infinity)
                }
                .engramAssistantClearance()
                .searchable(text: $model.search, prompt: "Search decks or questions")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { model.creationPresented = true } label: { Label("New deck", systemImage: "folder.badge.plus") }
                    }
                }
            }
        }
        .onChange(of: model.libraryDeckRequest) { _, id in
            if let id { model.selectedDeckID = id; model.libraryDeckRequest = nil }
        }
        .task(id:model.library.revision) {
            let snapshot = model.library,now = model.now
            var values: [String:Double] = [:]
            for deck in snapshot.liveDecks {
                let outlook = await model.service.memoryOutlook(for:deck,in:snapshot,now:now)
                guard !Task.isCancelled else { return }
                if let average = outlook.average.first { values[deck.id] = average }
            }
            retention = values
        }
    }
    private func directoryRow(_ deck: Deck) -> some View {
        let due = model.due(in:deck)
        let reviewCount = due.filter { $0.schedule.phase != .new }.count
        let newCount = due.count - reviewCount
        return HStack(spacing:12) {
            VStack(alignment:.leading,spacing:5) {
                if let average = retention[deck.id] {
                    HStack(spacing:5) {
                        Capsule().fill(palette.accentInk.opacity(0.2)).frame(width:36,height:2)
                            .overlay(alignment:.leading) { Capsule().fill(palette.accentInk).frame(width:36 * average,height:2) }
                        Text(average,format:.percent.precision(.fractionLength(0)))
                    }.font(.caption2).foregroundStyle(palette.secondaryText)
                        .accessibilityLabel("Estimated retention \(Int(average * 100)) percent")
                }
                Text(deck.name.components(separatedBy:"::").last ?? deck.name).font(theme.font(.control))
                    .fixedSize(horizontal:false,vertical:true)
                let parent = deck.name.components(separatedBy:"::").dropLast().joined(separator:" / ")
                if !parent.isEmpty { Text(parent).font(.caption2).foregroundStyle(palette.secondaryText) }
            }
            Spacer(minLength:8)
            Text(reviewCount > 0 ? "\(reviewCount) due" : newCount > 0 ? "\(newCount) new" : "No cards due")
                .font(.caption).monospacedDigit().foregroundStyle(due.isEmpty ? palette.secondaryText : palette.accentInk)
            Image(systemName:"chevron.right").font(.caption).accessibilityHidden(true)
        }.frame(minHeight:44).padding(.vertical,12).contentShape(Rectangle())
            .accessibilityElement(children:.combine)
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
