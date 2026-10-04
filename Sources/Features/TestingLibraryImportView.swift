import SwiftUI
import StudyApplication
import DesignSystem

struct TestingLibraryImportView: View {
    @Bindable var model: EngramModel
    @Environment(\.dismiss) private var dismiss
    @State private var result: TestingLibraryImport?
    var body: some View {
        NavigationStack {
            Form {
                EngramListSection {
                    ForEach(TestingLibraryContent.decks, id: \.key) { deck in
                        LabeledContent(deck.name, value: "\(deck.questions.count) questions")
                    }
                } header: { Text("Testing folder") } footer: {
                    Text("Original practice content, not official AWS exam questions. Maths examples use existing text-answer cards; no new question type or solver is included.")
                }
                EngramListSection {
                    LabeledContent("Destination", value: model.activeLibraryName)
                    Text("Existing sample edits, deleted questions and study progress are preserved. Reimporting only adds missing samples.")
                        .font(.subheadline)
                    Button("Add testing samples") {
                        Task {
                            var imported: TestingLibraryImport?
                            if await model.perform({ imported = try await $0.importTestingLibrary() }) { result = imported }
                        }
                    }.disabled(model.busy).accessibilityIdentifier("import-testing-samples")
                    if model.busy { ProgressView("Adding samples…") }
                    if let result {
                        Text("Added \(result.addedQuestions) questions in \(result.addedDecks) notebooks. Preserved \(result.preservedQuestions) existing questions.")
                            .font(.subheadline).accessibilityIdentifier("testing-samples-result")
                    }
                    if let error = model.error { Text(error).engramErrorText() }
                } footer: {
                    Text("Available immediately in this library. Account upload uses Engram's normal sync when connected; this screen does not write directly to another account.")
                }
            }
            .modifier(UtilityListStyle()).navigationTitle("Testing samples").engramInlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(model.busy) } }
        }
    }
}
