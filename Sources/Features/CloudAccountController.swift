import Foundation
import Observation
import CloudAdapters
import PersistenceAdapters
import LearningCore
import SchedulingAdapters

@MainActor @Observable final class CloudAccountController {
    private let repository: SQLiteLibraryRepository?
    private var client: SupabaseCloudClient?
    private var engine: CloudSyncEngine?
    private(set) var userID: UUID?
    private(set) var busy = false
    private(set) var status = "Local library"
    var error: String?
    var conflicts: [CloudConflict] = []
    var invitation: CloudInvitation?
    var invitationDeckID: String?
    var confirmationUserID: UUID?
    var configured: Bool { client != nil }
    init(repository: SQLiteLibraryRepository? = nil) {
        self.repository = repository
        // Hosted pilot remains disabled until two-device/two-user acceptance is complete.
        if let repository, Bundle.main.object(forInfoDictionaryKey:"EngramCloudPilotEnabled") as? Bool == true,
           let raw = Bundle.main.object(forInfoDictionaryKey:"EngramSupabaseURL") as? String,let url = URL(string:raw),
           let key = Bundle.main.object(forInfoDictionaryKey:"EngramSupabasePublishableKey") as? String {
            do { let client = try SupabaseCloudClient(url:url,publishableKey:key); self.client = client; engine = CloudSyncEngine(repository:repository,client:client,scheduler:FSRSScheduler()) }
            catch { self.error = error.localizedDescription }
        }
    }
    func signIn(_ provider: String) async {
        guard let client,!busy else { return }; busy = true; error = nil; defer { busy = false }
        do { confirmationUserID = try await client.signIn(provider:provider) }
        catch { self.error = error.localizedDescription }
    }
    func confirmInitialLibrary(upload: Bool,model: EngramModel) async {
        guard let id = confirmationUserID,let repository else { return }
        do {
            model.assistant.cancel(); model.voice.stop(); model.pdfLearning.cancel()
            try await repository.selectAccount(id.uuidString.lowercased(),uploadLocal:upload)
            userID = id; confirmationUserID = nil; await model.refresh(); await sync(model:model)
        } catch { self.error = error.localizedDescription }
    }
    func restore(model: EngramModel) async {
        guard let client,let repository,!busy else { return }
        do { let id = try await client.currentUserID(); try await repository.selectAccount(id.uuidString.lowercased()); userID = id; await model.refresh(); await sync(model:model) }
        catch { status = "Local library" }
    }
    func signOut(model: EngramModel) async {
        guard let client,let repository,!busy else { return }; busy = true; defer { busy = false }
        do { try await client.signOut(); model.assistant.cancel(); model.voice.stop(); model.pdfLearning.cancel(); try await repository.selectAccount(nil); userID = nil; conflicts = []; status = "Local library"; await model.refresh() }
        catch { self.error = error.localizedDescription }
    }
    func sync(model: EngramModel) async {
        guard let engine,userID != nil,!busy else { return }; busy = true; status = "Syncing…"; defer { busy = false }
        do {
            let report = try await engine.synchronize(); conflicts = report.conflicts
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
}
