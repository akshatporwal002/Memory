import SwiftUI
import LearningCore
import DesignSystem

struct LearningMemoryView: View {
    @Bindable var model: EngramModel
    @State private var editing: LearningMemory?
    @State private var deleting: LearningMemory?
    var body: some View {
        List {
            Section {
                Text("Accepted corrections help with relevant tutoring. They never decide a future grade and remain private to your account.").engramSecondaryText()
            }
            ForEach(model.library.assistantState?.memory ?? []) { memory in
                VStack(alignment:.leading,spacing:8) {
                    if let note = model.library.notes.first(where: { $0.id == memory.noteID }) { Text(note.front).font(.headline).lineLimit(2) }
                    RichContentView(source:memory.text)
                    HStack {
                        Button("Edit") { editing = memory }
                        Spacer()
                        Button("Delete",role:.destructive) { deleting = memory }
                    }.font(.caption).buttonStyle(.borderless)
                }.padding(.vertical,6)
            }
        }.modifier(UtilityListStyle()).navigationTitle("Learning memory")
            .sheet(item:$editing) { memory in LearningMemoryEditor(model:model,memory:memory) }
            .confirmationDialog("Delete this accepted memory?",isPresented:Binding(get:{deleting != nil},set:{if !$0 { deleting = nil }})) {
                if let deleting { Button("Delete",role:.destructive) { Task { if await model.perform({ try await $0.deleteLearningMemory(id:deleting.id) }) { self.deleting = nil } } } }
            }
    }
}
private struct LearningMemoryEditor: View {
    let model: EngramModel
    let memory: LearningMemory
    @State private var text: String
    @Environment(\.dismiss) private var dismiss
    init(model: EngramModel,memory: LearningMemory) { self.model = model; self.memory = memory; _text = State(initialValue:memory.text) }
    var body: some View {
        NavigationStack {
            Form { TextEditor(text:$text).frame(minHeight:180) }
                .navigationTitle("Edit memory")
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement:.confirmationAction) { Button("Save") { Task { var updated = memory; updated.text = text; if await model.perform({ try await $0.saveLearningMemory(updated) }) { dismiss() } } }.disabled(text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || text.utf8.count > 10_000) }
                }
        }
    }
}
