import SwiftUI
import CloudAdapters
import LearningCore
import DesignSystem

struct CloudAccountView: View {
    @Bindable var model: EngramModel
    var body: some View {
        List { AccountSettingsRows(model: model) }
            .modifier(UtilityListStyle()).navigationTitle("Engram account")
    }
}

struct AccountSettingsRows: View {
    @Bindable var model: EngramModel
    @State private var confirmSignOut = false
    @State private var token = ""
    var body: some View {
        Group {
            if model.cloud.signedIn {
                EngramListSection {
                    Text("Engram library").font(.subheadline)
                    Text(model.cloud.userID != nil ? (model.cloud.syncEnabled ? model.cloud.status : "Signed in · cloud sync not enabled") : "ChatGPT profile · saved on this device").font(.caption).engramSecondaryText()
                    if model.cloud.syncEnabled && model.cloud.userID != nil { Button("Sync now") { Task { await model.cloud.sync(model:model) } } }
                } header: { Text("Library") }
                EngramListSection { LibrarySpacePicker(model: model) }
            }
            EngramAccountSignIn(model: model, compact: true)
            if model.cloud.signedIn || !model.chatGPT.registrations.isEmpty {
                Button("Sign out all", role: .destructive) { confirmSignOut = true }
                    .frame(minHeight: 44).accessibilityIdentifier("account-sign-out-all")
            }
            if model.cloud.pendingLinkUserID != nil {
                HStack { Text("Finish linking in your browser").font(.caption); Spacer(); Button("Cancel") { model.cloud.cancelLoginLink() } }
            }
            if model.cloud.userID != nil && model.cloud.syncEnabled {
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
        }.disabled(model.cloud.busy)
            .task(id: model.cloud.userID) { await model.cloud.refreshLoginIdentities() }
            .confirmationDialog("Choose your ChatGPT profile's starting library", isPresented: Binding(get: { model.cloud.pendingChatGPTProfile != nil && !model.chatGPT.showPlanConfirmation }, set: { if !$0 { model.cloud.pendingChatGPTProfile = nil } })) {
                if let account = model.cloud.pendingChatGPTProfile {
                    Button("Use this device's local library") { Task { await model.cloud.useChatGPTProfile(account, upload: true, model: model) } }
                    Button("Start with an empty library") { Task { await model.cloud.useChatGPTProfile(account, upload: false, model: model) } }
                }
                Button("Cancel", role: .cancel) { model.cloud.pendingChatGPTProfile = nil }
            } message: { Text("Your ChatGPT identity and AI access use one sign-in. Cloud library sync for this method is awaiting server setup; your libraries stay saved on this device.") }
            .onAppear { if let value = model.cloud.pendingJoinToken { token = value; model.cloud.pendingJoinToken = nil } }
            .confirmationDialog("Choose your account's starting library",isPresented:Binding(get: { model.cloud.confirmationUserID != nil },set: { _ in })) {
                Button(model.cloud.localProfileID != nil ? "Copy my ChatGPT profile's library" : (model.cloud.syncEnabled ? "Upload this device's local library" : "Use this device's local library")) { Task { await model.cloud.confirmInitialLibrary(upload:true,model:model) } }
                Button(model.cloud.syncEnabled ? "Start with my cloud library" : "Start with an empty library") { Task { await model.cloud.confirmInitialLibrary(upload:false,model:model) } }
                Button("Cancel",role:.cancel) { Task { await model.cloud.cancelInitialLibrary() } }
            } message: { Text(model.cloud.localProfileID != nil ? "Your ChatGPT connection stays connected. You can copy its local library to a new Engram profile, or use the account's existing library. The original is preserved." : "Uploading is optional. Local libraries and other accounts remain separate on this device.") }
            .confirmationDialog("Sign out of all accounts on this device?",isPresented:$confirmSignOut) {
                Button("Sign out all",role:.destructive) { Task { await model.cloud.signOutAll(model:model) } }
            } message: { Text("Signs out of Engram's Google, Apple and email session and disconnects all ChatGPT AI accounts on this device. Saved libraries remain preserved; the guest library becomes active. Other devices are not signed out.") }
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
    @State private var pendingMemberRemoval: UUID?
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
                if model.cloud.membersDeckID == deckID && !model.cloud.members.isEmpty {
                    EngramListSection("People with access") {
                        ForEach(model.cloud.members,id:\.user_id) { member in
                            HStack {
                                VStack(alignment:.leading) {
                                    Text("Member · " + String(member.user_id.uuidString.prefix(8)))
                                    Text(member.role.capitalized).font(.caption).engramSecondaryText()
                                }
                                Spacer()
                                Button("Remove access",role:.destructive) { pendingMemberRemoval = member.user_id }
                            }
                        }
                    }
                }
            }
            if let error = model.cloud.error { EngramInlineError(message:error) }
        }.modifier(UtilityListStyle()).navigationTitle("Share deck")
            .task(id:deckID) { await model.cloud.loadMembers(deckID:deckID) }
            .confirmationDialog("Create a \(role) invitation?",isPresented:$confirmInvite) { Button("Create invitation") { Task { await model.cloud.sync(model:model); await model.cloud.invite(deckID:deckID,role:role) } } }
            .confirmationDialog("Revoke this invitation?",isPresented:$confirmRevoke) { Button("Revoke",role:.destructive) { Task { await model.cloud.revokeInvitation() } } }
            .confirmationDialog("Remove this person's deck access?",isPresented:Binding(get:{pendingMemberRemoval != nil},set:{if !$0 { pendingMemberRemoval = nil }})) {
                if let memberID = pendingMemberRemoval { Button("Remove access",role:.destructive) { pendingMemberRemoval = nil; Task { await model.cloud.revokeMember(deckID:deckID,memberID:memberID,model:model) } } }
            } message: { Text("Their cached shared deck is removed when their device reconnects. Exported copies cannot be recalled.") }
    }
}
