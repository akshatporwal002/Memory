import SwiftUI
import LearningCore
import DesignSystem

struct LibrarySpacePicker: View {
    let model: EngramModel
    @State private var creating = false
    @State private var name = ""
    @State private var deviceOnly = false
    var body: some View {
        Menu {
            ForEach(model.librarySpaces) { space in
                Button { Task { await model.selectLibrary(space.id) } } label: {
                    Label(space.name + (space.deviceOnly ? " · This device" : ""), systemImage: space.id == model.activeLibraryID ? "checkmark" : "books.vertical")
                }
            }
            Divider()
            Button("New library", systemImage: "plus") { name = ""; deviceOnly = false; creating = true }
        } label: {
            HStack(spacing: 6) {
                Text(model.activeLibraryName).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2)
            }.font(.subheadline).frame(minHeight: 44)
        }.accessibilityLabel("Library: " + model.activeLibraryName).accessibilityIdentifier("library-space-picker")
            .disabled(model.busy || model.typedAnswer.busy || model.cloud.busy)
            .sheet(isPresented: $creating) {
                NavigationStack {
                    Form {
                        TextField("Library name", text: $name)
                        Toggle("Keep on this device only", isOn: $deviceOnly)
                        Text(deviceOnly ? "This library won't upload to your account. Keep a backup if you need to recover it." : "This library can sync with your account when cloud sync is available. Each device remembers which library you open.")
                            .font(.footnote).engramSecondaryText()
                    }.modifier(UtilityListStyle()).navigationTitle("New library")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { creating = false } }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Create") {
                                    Task { await model.createLibrary(name: name, deviceOnly: deviceOnly); if model.error == nil { creating = false } }
                                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
                            }
                        }
                    if let error = model.error { EngramInlineError(message: error).padding() }
                }.presentationDetents([.medium, .large])
            }
    }
}

struct MoveDeckToLibraryMenu: View {
    let model: EngramModel
    let deckID: String
    var body: some View {
        if model.librarySpaces.count > 1 {
            Menu("Move to library", systemImage: "books.vertical") {
                ForEach(model.librarySpaces.filter { $0.id != model.activeLibraryID }) { space in
                    Button(space.name) { Task { await model.moveDeckToLibrary(deckID, libraryID: space.id) } }
                }
            }
        }
    }
}
