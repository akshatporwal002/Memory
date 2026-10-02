import SwiftUI
import LearningCore
import DesignSystem

struct AIActionReviewView: View {
    @Bindable var model: EngramModel
    @Environment(\.dismiss) private var dismiss
    @State private var conflict: String?
    private var runs: [AIActionRun] { Array((model.library.assistantState?.runs ?? []).reversed()) }
    var body: some View {
        NavigationStack {
            List {
                if let conflict { Section("Later edits need resolution") { Text(conflict); Text("Your current content was kept. Compare the original and proposed content below before editing it manually.").engramSecondaryText() } }
                if runs.isEmpty { ContentUnavailableView("No assistant changes",systemImage:"clock.arrow.circlepath",description:Text("Edits and navigation actions will appear here.")) }
                ForEach(runs) { run in
                    Section {
                        ForEach(run.actions) { action in
                            VStack(alignment:.leading,spacing:10) {
                                HStack { Text(action.name.replacingOccurrences(of:"_",with:" ").capitalized).font(.headline); Spacer(); Text(action.status).font(.caption).engramSecondaryText() }
                                Text(action.summary).font(.subheadline)
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
    }
    private func undo(_ run: AIActionRun,action: AIActionRecord,change: AIContentChange) async {
        conflict = nil
        do { try await model.service.undoAIChange(runID:run.id,actionID:action.id,changeID:change.id); await model.refresh() }
        catch { conflict = error.localizedDescription }
    }
    private func before(_ change: AIContentChange) -> String {
        if let note = change.beforeNote { return note.front + "\n\n" + note.back }
        if let deck = change.beforeDeck { return deck.name + "\n\n" + (deck.sourceDocument ?? "") }
        if let settings = change.beforeSettings { return "\(settings.newCardsPerDay) new/day · \(settings.reviewsPerDay) reviews/day" }
        if let card = change.beforeCard { return card.suspended ? "Suspended" : "Active" }
        return "Did not exist"
    }
    private func after(_ change: AIContentChange) -> String {
        if let note = change.afterNote { return note.deleted ? "Deleted" : note.front + "\n\n" + note.back }
        if let deck = change.afterDeck { return deck.deleted ? "Deleted" : deck.name + "\n\n" + (deck.sourceDocument ?? "") }
        if let settings = change.afterSettings { return "\(settings.newCardsPerDay) new/day · \(settings.reviewsPerDay) reviews/day" }
        if let card = change.afterCard { return card.suspended ? "Suspended" : "Active" }
        return "No content change"
    }
}
