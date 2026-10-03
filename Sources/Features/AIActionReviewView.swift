import SwiftUI
import LearningCore
import DesignSystem

struct AIActionReviewView: View {
    @Bindable var model: EngramModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @State private var conflict: String?
    @State private var undoConflict: UndoConflict?
    private var runs: [AIActionRun] { Array((model.library.assistantState?.runs ?? []).reversed()) }
    var body: some View {
        NavigationStack {
            List {
                if let conflict { Section("Later edits need resolution") { Text(conflict); Text("Your current content was kept. Resolve an individual change using Base, Yours, or Theirs before retrying the run.").engramSecondaryText() } }
                if runs.isEmpty { ContentUnavailableView("No assistant changes",systemImage:"clock.arrow.circlepath",description:Text("Edits and navigation actions will appear here.")) }
                ForEach(runs) { run in
                    Section {
                        ForEach(run.actions) { action in
                            VStack(alignment:.leading,spacing:10) {
                                HStack { Text(action.name.replacingOccurrences(of:"_",with:" ").capitalized).font(.headline); Spacer(); Text(action.status).font(.caption).engramSecondaryText() }
                                Text(action.summary).font(.subheadline)
                                if action.status == "pending" {
                                    Button("Review pending confirmation") { model.assistant.restoreConfirmation(action,run:run); dismiss() }
                                }
                                ForEach(action.changes) { change in
                                    VStack(alignment:.leading,spacing:8) {
                                        if let deckID = change.deckID { Text(model.deckName(deckID)).font(.caption.weight(.semibold)) }
                                        DisclosureGroup("Before / After") {
                                            Text("Before").font(.caption.weight(.semibold)); RichContentView(source:before(change))
                                            Divider()
                                            Text("After").font(.caption.weight(.semibold)); RichContentView(source:after(change))
                                        }
                                        if change.undoneAt == nil {
                                            Button("Undo this change") { Task { await undo(run,action:action,change:change) } }.disabled(model.busy)
                                        } else { Label("Undone",systemImage:"arrow.uturn.backward").font(.caption) }
                                    }.padding(.vertical,4)
                                }
                            }.padding(.vertical,6)
                        }
                        if run.actions.contains(where: { $0.changes.contains(where: { $0.undoneAt == nil }) }) {
                            Button("Undo this run") { Task {
                                conflict = nil
                                do { try await model.service.undoAIRun(id:run.id); await model.refresh() }
                                catch { conflict = error.localizedDescription }                            }}.disabled(model.busy)
                        }
                    } header: { Text(run.createdAt.formatted(date:.abbreviated,time:.shortened) + " · " + run.status) }
                }
            }.modifier(UtilityListStyle()).navigationTitle("Review changes")
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
        }
        .sheet(item:$undoConflict) { item in
            NavigationStack {
                List {
                    Text("Later edits overlap this undo. Apply a chosen version as a new edit; review history is preserved.").engramSecondaryText()
                    Section("Base · after the assistant edit") { RichContentView(source:after(item.change)); Button("Use Base") { resolve(item,choice:"base") } }
                    Section("Yours · current content") { RichContentView(source:current(item.change)); Button("Keep Yours") { resolve(item,choice:"yours") } }
                    Section("Theirs · proposed undo") { RichContentView(source:before(item.change)); Button("Apply Theirs") { resolve(item,choice:"theirs") } }
                    if let conflict { Text(conflict).foregroundStyle(theme.palette(for: scheme).againInk) }
                }.modifier(UtilityListStyle()).navigationTitle("Resolve undo")
                    .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { undoConflict = nil } } }
            }
        }
    }
    private func undo(_ run: AIActionRun,action: AIActionRecord,change: AIContentChange) async {
        conflict = nil
        do { try await model.service.undoAIChange(runID:run.id,actionID:action.id,changeID:change.id); await model.refresh() }
        catch { conflict = error.localizedDescription; await model.refresh(); if error as? EngramError == .conflict { undoConflict = UndoConflict(runID:run.id,actionID:action.id,change:change,revision:model.library.revision) } }
    }
    private func resolve(_ item: UndoConflict,choice: String) {
        Task {
            do { try await model.service.resolveAIUndo(runID:item.runID,actionID:item.actionID,changeID:item.change.id,choice:choice,expectedRevision:item.revision); await model.refresh(); conflict = nil; undoConflict = nil }
            catch { conflict = error.localizedDescription }
        }
    }
    private func current(_ change: AIContentChange) -> String {
        if change.afterPreferences != nil { return (model.library.assistantState?.preferences ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator:"\n") }
        if let id = change.noteID,let note = model.library.notes.first(where: { $0.id == id }),change.afterNote != nil { return note.front + "\n\n" + note.back }
        if let id = change.deckID,let deck = model.library.decks.first(where: { $0.id == id }),change.afterDeck != nil { return deck.name + "\n\n" + (deck.sourceDocument ?? "") }
        if let id = change.afterMemory?.id ?? change.beforeMemory?.id { return model.library.assistantState?.memory.first(where: { $0.id == id })?.text ?? "Deleted" }
        if change.afterSettings != nil { return "\(model.library.settings.newCardsPerDay) new/day · \(model.library.settings.reviewsPerDay) reviews/day" }
        if let id = change.afterCard?.id { return model.library.cards.first(where: { $0.id == id })?.suspended == true ? "Suspended" : "Active" }
        return "Unavailable"
    }
    private func before(_ change: AIContentChange) -> String {
        if let values = change.beforePreferences { return values.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator:"\n") }
        if let memory = change.beforeMemory { return memory.text }
        if let note = change.beforeNote { return note.front + "\n\n" + note.back }
        if let deck = change.beforeDeck { return deck.name + "\n\n" + (deck.sourceDocument ?? "") }
        if let settings = change.beforeSettings { return "\(settings.newCardsPerDay) new/day · \(settings.reviewsPerDay) reviews/day" }
        if let card = change.beforeCard { return card.suspended ? "Suspended" : "Active" }
        return "Did not exist"
    }
    private func after(_ change: AIContentChange) -> String {
        if let values = change.afterPreferences { return values.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator:"\n") }
        if let memory = change.afterMemory { return memory.text }
        if let note = change.afterNote { return note.deleted ? "Deleted" : note.front + "\n\n" + note.back }
        if let deck = change.afterDeck { return deck.deleted ? "Deleted" : deck.name + "\n\n" + (deck.sourceDocument ?? "") }
        if let settings = change.afterSettings { return "\(settings.newCardsPerDay) new/day · \(settings.reviewsPerDay) reviews/day" }
        if let card = change.afterCard { return card.suspended ? "Suspended" : "Active" }
        return "No content change"
    }
}
private struct UndoConflict: Identifiable {
    var id: String { change.id }
    let runID: String
    let actionID: String
    let change: AIContentChange
    let revision: Int
}
