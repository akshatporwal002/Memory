import Foundation
import Observation
import CloudAdapters
import PersistenceAdapters
import LearningCore
import SchedulingAdapters
import ChatGPTAuth
import CryptoKit

@MainActor @Observable final class CloudAccountController {
    private let repository: SQLiteLibraryRepository?
    private var client: SupabaseCloudClient?
    private var engine: CloudSyncEngine?
    private var notificationTask: Task<Void,Never>?
    private(set) var userID: UUID?
    private(set) var localProfileID: String?
    var pendingChatGPTProfile: ChatGPTRegistration?
    var signedIn: Bool { userID != nil || localProfileID != nil }
    private(set) var loginIdentities: [AppLoginIdentity] = []
    private(set) var pendingLinkUserID: UUID?
    private static let pendingLinkKey = "engram.pendingIdentityLink"
    var hasPendingLoginLink: Bool {
        pendingLinkUserID != nil || UserDefaults.standard.data(forKey: Self.pendingLinkKey) != nil
    }
    private func savePendingLink(_ id: UUID?) {
        pendingLinkUserID = id
        if let id, let data = try? JSONEncoder().encode(PendingIdentityLink(userID: id)) {
            UserDefaults.standard.set(data, forKey: Self.pendingLinkKey)
        } else { UserDefaults.standard.removeObject(forKey: Self.pendingLinkKey) }
    }
    private func restoredPendingLink(for id: UUID) -> PendingIdentityLink? {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingLinkKey),
              let link = try? JSONDecoder().decode(PendingIdentityLink.self, from: data),
              link.isValid(for: id) else { return nil }
        return link
    }
    var appleSignInEnabled: Bool { Bundle.main.object(forInfoDictionaryKey: "EngramAppleSignInEnabled") as? Bool == true }
    func refreshLoginIdentities() async {
        guard let client, userID != nil else { loginIdentities = []; return }
        do { loginIdentities = try await client.loginIdentities() }
        catch { self.error = error.localizedDescription }
    }
    func linkLoginMethod(_ provider: String) async {
        guard let client, let id = userID, !busy, pendingLinkUserID == nil else { return }
        busy = true; error = nil; savePendingLink(id); defer { busy = false }
        do { try await client.linkProvider(provider, expectedUserID: id) }
        catch { savePendingLink(nil); self.error = error.localizedDescription }
    }
    func cancelLoginLink() { savePendingLink(nil) }
    func completeLoginLink(_ url: URL) async {
        guard let client, !busy else { return }
        do {
            let id = try await client.currentUserID()
            guard restoredPendingLink(for: id) != nil, userID == nil || userID == id else {
                savePendingLink(nil); error = "This linking request expired. Try linking the account again."; return
            }
            pendingLinkUserID = id
        } catch { savePendingLink(nil); self.error = error.localizedDescription; return }
        guard let id = pendingLinkUserID else { return }
        busy = true; defer { busy = false; savePendingLink(nil) }
        do { try await client.completeIdentityLink(url, expectedUserID: id); await refreshLoginIdentities() }
        catch { self.error = error.localizedDescription }
    }
    func useChatGPTProfile(_ account: ChatGPTRegistration, upload: Bool, model: EngramModel) async {
        guard let repository, account.credentials != nil, !busy, !model.busy, !model.typedAnswer.busy, !model.markingAnswer else { return }
        busy = true; defer { busy = false }
        let id = "chatgpt-" + SHA256.hash(data: Data(account.subject.utf8)).map { String(format: "%02x", $0) }.joined()
        do {
            await model.assistant.stopAndWait(); model.voice.stop(); model.pdfLearning.cancel()
            notificationTask?.cancel(); notificationTask = nil
            // This is an isolated local identity profile, never a fabricated Supabase session.
            try await repository.selectAccount(id, uploadLocal: upload, syncEnabled: false)
            localProfileID = id; userID = nil; pendingChatGPTProfile = nil
            UserDefaults.standard.set("chatgpt", forKey: "engram.accountMethod")
            status = "Signed in with ChatGPT · libraries saved on this device"
            await model.restoreLibrarySelection(); await model.refresh()
        } catch { self.error = error.localizedDescription }
    }
    private(set) var busy = false
    private(set) var status = "Local library"
    var error: String?
    var conflicts: [CloudConflict] = []
    var invitation: CloudInvitation?
    var invitationDeckID: String?
    private(set) var members: [CloudMembership] = []
    private(set) var membersDeckID: String?
    var confirmationUserID: UUID?
    var pendingJoinToken: String?
    private(set) var emailCodeAddress: String?
    private(set) var emailResendAfter = Date.distantPast
    var configured: Bool { client != nil }
    var syncEnabled: Bool { engine != nil }
    init(repository: SQLiteLibraryRepository? = nil) {
        self.repository = repository
        // Hosted pilot remains disabled until two-device/two-user acceptance is complete.
        if let repository,
           let raw = Bundle.main.object(forInfoDictionaryKey:"EngramSupabaseURL") as? String,let url = URL(string:raw),
           let key = Bundle.main.object(forInfoDictionaryKey:"EngramSupabasePublishableKey") as? String {
            do { let client = try SupabaseCloudClient(url:url,publishableKey:key); self.client = client; if Bundle.main.object(forInfoDictionaryKey:"EngramCloudPilotEnabled") as? Bool == true { engine = CloudSyncEngine(repository:repository,client:client,scheduler:FSRSScheduler()) } }
            catch { self.error = error.localizedDescription }
        }
    }
    func signIn(_ provider: String) async {
        if userID != nil { await linkLoginMethod(provider); return }
        guard let client,!busy else { return }; busy = true; error = nil; defer { busy = false }
        do { finishSignIn(try await client.signIn(provider:provider)) }
        catch { self.error = error.localizedDescription }
    }
    func signInWithApple(idToken: String, nonce: String) async {
        guard let client, !busy else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            if let id = userID { try await client.linkApple(idToken: idToken, nonce: nonce, expectedUserID: id); await refreshLoginIdentities() }
            else { finishSignIn(try await client.signInWithApple(idToken: idToken, nonce: nonce)) }
        }
        catch { self.error = error.localizedDescription }
    }
    func sendEmailCode(_ email: String) async {
        guard let client, !busy else { return }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.count <= 254, address.contains("@"), !address.contains(where: { $0.isWhitespace }) else { error = "Enter a valid email address."; return }
        guard Date() >= emailResendAfter else { error = "Please wait a minute before requesting another code."; return }
        busy = true; error = nil; defer { busy = false }
        do {
            if let id = userID { try await client.requestEmailLink(address, expectedUserID: id) }
            else { try await client.sendEmailCode(email: address) }
            emailCodeAddress = address; emailResendAfter = Date().addingTimeInterval(60)
        }
        catch { self.error = error.localizedDescription }
    }
    func verifyEmailCode(_ code: String) async {
        guard let client, let email = emailCodeAddress, !busy else { return }
        let value = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (6...10).contains(value.count), value.allSatisfy({ $0.isASCII && $0.isNumber }) else { error = "Enter the verification code from your email."; return }
        busy = true; error = nil; defer { busy = false }
        do {
            if let id = userID {
                if try await client.verifyEmailLink(email, code: value, expectedUserID: id) { emailCodeAddress = nil; await refreshLoginIdentities() }
                else { error = "Confirm the code from your other inbox too to finish linking email." }
            } else { finishSignIn(try await client.verifyEmailCode(email: email, code: value)); emailCodeAddress = nil }
        }
        catch { self.error = error.localizedDescription }
    }
    func changeEmail() { emailCodeAddress = nil; error = nil }
    func removeLoginIdentity(_ identity: AppLoginIdentity) async {
        guard let client, let id = userID, !busy else { return }
        busy = true; error = nil; defer { busy = false }
        do { try await client.removeLoginIdentity(identity.id, expectedUserID: id); await refreshLoginIdentities() }
        catch { self.error = error.localizedDescription }
    }
    func signOutAll(model: EngramModel) async {
        guard !busy, !model.chatGPT.busy, !model.busy, !model.typedAnswer.busy, !model.markingAnswer else {
            error = "Finish the current request or answer review before signing out."; return
        }
        error = nil
        if signedIn { await signOut(model: model); guard !signedIn else { return } }
        await model.assistant.stopAndWait(); model.voice.stop(); model.pdfLearning.cancel()
        await model.chatGPT.signOutAll()
        if let failure = model.chatGPT.error { error = failure }
    }
    private func finishSignIn(_ id: UUID) {
        // Keep the current profile active until the learner accepts a library.
        // Cancelling Google sign-in must not orphan a ChatGPT local profile.
        confirmationUserID = id
    }
    func confirmInitialLibrary(upload: Bool,model: EngramModel) async {
        guard let id = confirmationUserID,let repository,!busy else { return }
        guard !model.busy,!model.typedAnswer.busy,!model.markingAnswer else { error = "Finish the current edit or answer review before switching accounts."; return }
        busy = true; defer { busy = false }
        do {
            await model.assistant.stopAndWait(); model.voice.stop(); model.pdfLearning.cancel()
            try await repository.selectAccount(id.uuidString.lowercased(),uploadLocal:upload,syncEnabled:syncEnabled,
                copyCurrentChatGPTProfile: upload && localProfileID != nil)
            model.pdfLearning.selectAccount(id)
            userID = id; localProfileID = nil; confirmationUserID = nil
            UserDefaults.standard.set("cloud", forKey: "engram.accountMethod")
            status = syncEnabled ? "Connected" : "Signed in · libraries saved on this device"
            await refreshLoginIdentities()
            await model.restoreLibrarySelection(); startNotifications(model:model); await model.refresh()
            busy = false; await sync(model:model)
        } catch { self.error = error.localizedDescription }
    }
    func cancelInitialLibrary() async {
        do { try await client?.signOut(); confirmationUserID = nil }
        catch { self.error = error.localizedDescription }
    }
    func restore(model: EngramModel) async {
        if UserDefaults.standard.string(forKey: "engram.accountMethod") == "chatgpt", let account = model.chatGPT.activeAccount, account.credentials != nil {
            await useChatGPTProfile(account, upload: false, model: model); return
        }
        guard let client,let repository,!busy else { return }
        do {
            let id = try await client.currentUserID()
            guard try await repository.hasAccount(id.uuidString.lowercased()) else { confirmationUserID = id; return }
            try await repository.selectAccount(id.uuidString.lowercased(),syncEnabled:syncEnabled); model.pdfLearning.selectAccount(id); userID = id
            status = syncEnabled ? "Connected" : "Signed in · libraries saved on this device"
            await refreshLoginIdentities()
            await model.restoreLibrarySelection(); startNotifications(model:model); await model.refresh(); await sync(model:model)
        }
        catch { status = "Local library" }
    }
    func signOut(model: EngramModel) async {
        guard !model.busy, !model.typedAnswer.busy, !model.markingAnswer else {
            error = "Finish the current edit or answer review before switching accounts."; return
        }
        savePendingLink(nil); loginIdentities = []; emailCodeAddress = nil
        if localProfileID != nil, let repository {
            guard !busy, !model.busy, !model.typedAnswer.busy else { return }
            do {
                await model.assistant.stopAndWait(); model.voice.stop(); model.pdfLearning.cancel()
                await model.chatGPT.signOut(); try await repository.selectAccount(nil)
                localProfileID = nil; status = "Local library"; UserDefaults.standard.removeObject(forKey: "engram.accountMethod")
                await model.restoreLibrarySelection(); await model.refresh()
            } catch { self.error = error.localizedDescription }
            return
        }
        guard let client,let repository,!busy else { return }; busy = true; defer { busy = false }
        if !syncEnabled {
            do {
                await model.assistant.stopAndWait(); model.voice.stop(); model.pdfLearning.selectAccount(nil)
                try await client.signOut(); try await repository.selectAccount(nil); userID = nil; status = "Local library"
                UserDefaults.standard.removeObject(forKey: "engram.accountMethod")
                await model.restoreLibrarySelection(); await model.refresh()
            }
            catch { self.error = error.localizedDescription }
            return
        }
        guard !model.busy,!model.typedAnswer.busy else { error = "Finish the current edit or answer review before switching accounts."; return }
        do { await model.assistant.stopAndWait(); try await client.signOut(); notificationTask?.cancel(); notificationTask = nil; model.voice.stop(); model.pdfLearning.selectAccount(nil); try await repository.selectAccount(nil); userID = nil; conflicts = []; members = []; membersDeckID = nil; status = "Local library"; UserDefaults.standard.removeObject(forKey: "engram.accountMethod"); await model.restoreLibrarySelection(); await model.refresh() }
        catch { self.error = error.localizedDescription }
    }
    private func startNotifications(model: EngramModel) {
        notificationTask?.cancel()
        guard engine != nil,let client,let id = userID else { return }
        notificationTask = Task { [weak self,weak model] in
            do {
                for try await _ in await client.notifications() {
                    guard !Task.isCancelled,let self,let model,self.userID == id else { break }
                    await self.sync(model:model)
                }
            } catch { /* Offline notification failure leaves cursor-based polling active. */ }
        }
    }
    func sync(model: EngramModel,allowStudyBoundary: Bool = false) async {
        guard let engine,userID != nil,!busy else { return }; busy = true; status = "Syncing…"; defer { busy = false }
        do {
            let report = try await engine.synchronize(allowStudyBoundary:allowStudyBoundary); conflicts = report.conflicts
            status = report.conflicts.isEmpty ? (report.pending == 0 ? "Synced" : "\(report.pending) pending") : "\(report.conflicts.count) conflicts"
            if !report.removedDecks.isEmpty { status += " · shared access removed" }
            if report.adjustedDueDates > 0 { status += " · \(report.adjustedDueDates) due dates reconciled" }
            error = nil; await model.refresh()
        } catch { self.error = error.localizedDescription; status = "Local work saved · sync pending" }
    }
    func resolve(_ conflict: CloudConflict,choice: String,model: EngramModel) async {
        guard let engine else { return }
        do { try await engine.resolve(conflict.id,using:choice); await sync(model:model) }
        catch { self.error = error.localizedDescription }
    }
    func invite(deckID: String,role: String) async {
        guard let client else { return }
        do { invitation = try await client.invite(deckID:deckID,role:role); invitationDeckID = deckID }
        catch { self.error = error.localizedDescription }
    }
    func accept(token: String,model: EngramModel) async {
        guard let client else { return }
        do { _ = try await client.accept(token:token); await sync(model:model) }
        catch { self.error = error.localizedDescription }
    }
    func revokeInvitation() async {
        guard let client,let invitation,let deck = invitationDeckID else { return }
        do { try await client.revoke(deckID:deck,invitationID:invitation.id); self.invitation = nil }
        catch { self.error = error.localizedDescription }
    }
    func loadMembers(deckID: String) async {
        guard let client,let userID else { members = []; membersDeckID = nil; return }
        do {
            guard try await client.decks().contains(where: { $0.id == deckID && $0.owner_id == userID }) else { members = []; membersDeckID = nil; return }
            let rows = try await client.memberships()
            members = rows.filter { $0.deck_id == deckID && $0.user_id != userID }.sorted { $0.user_id.uuidString < $1.user_id.uuidString }
            membersDeckID = deckID; error = nil
        } catch { members = []; membersDeckID = nil; self.error = error.localizedDescription }
    }
    func revokeMember(deckID: String,memberID: UUID,model: EngramModel) async {
        guard let client,let userID,memberID != userID else { return }
        do {
            guard try await client.decks().contains(where: { $0.id == deckID && $0.owner_id == userID }) else { throw EngramError.invalid("Only the owner can remove a member.") }
            try await client.revoke(deckID:deckID,userID:memberID)
            await sync(model:model); await loadMembers(deckID:deckID)
        } catch { self.error = error.localizedDescription }
    }
}
