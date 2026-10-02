import SwiftUI
import CloudAdapters
import LearningCore
import DesignSystem

struct CloudAccountView: View {
    @Bindable var model: EngramModel
    @State private var confirmSignOut = false
    @State private var token = ""
    var body: some View {
        Form {
            EngramListSection {
                if model.cloud.userID != nil {
                    Label("Connected",systemImage:"person.crop.circle.badge.checkmark")
                    Text(model.cloud.status).font(.caption).engramSecondaryText()
                    Button("Sync now") { Task { await model.cloud.sync(model:model) } }
                    Button("Sign out",role:.destructive) { confirmSignOut = true }
                } else {
                    Button("Continue with Apple",systemImage:"apple.logo") { Task { await model.cloud.signIn("apple") } }.disabled(!model.cloud.configured)
                    Button("Continue with Google") { Task { await model.cloud.signIn("google") } }.disabled(!model.cloud.configured)
                    if !model.cloud.configured { Text("Cloud accounts are awaiting setup. Your local library remains available.").font(.caption).engramSecondaryText() }
                }
            } header: { Text("Engram account") } footer: { Text("Your Engram account synchronizes your learning library. Your ChatGPT connection provides AI access and remains separate.") }
            if model.cloud.userID != nil {
                EngramListSection("Join a shared deck") {
                    TextField("Invitation link",text:$token).textContentType(.URL)
                    Button("Join deck") {
                        let value = URLComponents(string:token)?.queryItems?.first(where: { $0.name == "token" })?.value ?? token
                        Task { await model.cloud.accept(token:value,model:model) }
                    }.disabled(token.isEmpty)
                }
            }
            if !model.cloud.conflicts.isEmpty {
                EngramListSection("Conflicts") {
                    ForEach(model.cloud.conflicts) { conflict in NavigationLink(conflict.entity.id) { CloudConflictView(model:model,conflict:conflict) } }
                }
            }
            if let error = model.cloud.error { EngramInlineError(message:error) }
            if model.cloud.busy { ProgressView() }
        }.modifier(UtilityListStyle()).navigationTitle("Engram account").disabled(model.cloud.busy)
            .confirmationDialog("Choose your account's starting library",isPresented:Binding(get: { model.cloud.confirmationUserID != nil },set: { _ in })) {
                Button("Upload this device's local library") { Task { await model.cloud.confirmInitialLibrary(upload:true,model:model) } }
                Button("Start with my cloud library") { Task { await model.cloud.confirmInitialLibrary(upload:false,model:model) } }
            } message: { Text("Uploading is optional. Local libraries and other accounts remain separate on this device.") }
            .confirmationDialog("Sign out of Engram?",isPresented:$confirmSignOut) {
                Button("Sign out",role:.destructive) { Task { await model.cloud.signOut(model:model) } }
            } message: { Text("Your account's work stays saved privately on this device. The local library becomes active.") }
    }
}

private struct CloudConflictView: View {
    let model: EngramModel
    let conflict: CloudConflict
    @State private var selection: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            Text("Both versions are preserved. Select the version to apply as a new edit.").engramSecondaryText()
            ForEach([("base",conflict.base),("yours",conflict.yours),("theirs",conflict.theirs)],id:\.0) { label,value in
                Section(label.capitalized) {
                    Text(readable(value)).font(.system(.body,design:.monospaced)).textSelection(.enabled)
                    Button("Use " + label.capitalized) { selection = label }
                }
            }
        }.modifier(UtilityListStyle()).navigationTitle("Resolve conflict")
            .confirmationDialog("Apply this version?",isPresented:Binding(get:{selection != nil},set:{if !$0 { selection = nil }})) {
                if let selection { Button("Apply " + selection.capitalized) { Task { await model.cloud.resolve(conflict,choice:selection,model:model); if model.cloud.error == nil { dismiss() } } } }
            }
    }
    private func readable(_ value: JSONValue) -> String { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]; return (try? encoder.encode(value)).map { String(decoding:$0,as:UTF8.self) } ?? "Unavailable" }
}

struct DeckSharingView: View {
    let model: EngramModel
    let deckID: String
    @State private var role = "viewer"
    @State private var confirmInvite = false
    @State private var confirmRevoke = false
    var body: some View {
        Form {
            if model.cloud.userID == nil { Text("Connect your Engram account to share a deck."); NavigationLink("Engram account") { CloudAccountView(model:model) } }
            else {
                Picker("Access",selection:$role) { Text("Viewer").tag("viewer"); Text("Editor").tag("editor") }
                Button("Create invitation") { confirmInvite = true }
                if let invitation = model.cloud.invitation, model.cloud.invitationDeckID == deckID,
                   let url = URL(string:"engram://join?token=" + invitation.token) {
                    ShareLink("Share invitation",item:url)
                    Text("Expires after seven days. Original PDF files and your personal study history stay private.").font(.caption).engramSecondaryText()
                    Button("Revoke invitation",role:.destructive) { confirmRevoke = true }
                }
            }
            if let error = model.cloud.error { EngramInlineError(message:error) }
        }.modifier(UtilityListStyle()).navigationTitle("Share deck")
            .confirmationDialog("Create a \(role) invitation?",isPresented:$confirmInvite) { Button("Create invitation") { Task { await model.cloud.sync(model:model); await model.cloud.invite(deckID:deckID,role:role) } } }
            .confirmationDialog("Revoke this invitation?",isPresented:$confirmRevoke) { Button("Revoke",role:.destructive) { Task { await model.cloud.revokeInvitation() } } }
    }
}
