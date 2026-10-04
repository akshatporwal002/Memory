import SwiftUI
import LearningCore
import DesignSystem

struct NotebookInputSettings: View {
    @Bindable var model: EngramModel
    let deckID: String
    var body: some View {
        List {
            EngramListSection {
                Picker("Keyboard", selection: Binding(get: { model.library.liveDecks.first { $0.id == deckID }?.mathInputMode ?? .off }, set: { value in Task { _ = await model.perform { try await $0.setMathInputMode(deckID: deckID, mode: value) } } })) {
                    ForEach(MathInputMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } header: { Text("Maths input") } footer: { Text("Used only for questions marked as maths. Add a maths or equation tag to a question to enable its notation input.") }
        }.modifier(UtilityListStyle()).navigationTitle("Notebook input").engramInlineTitle()
    }
}
