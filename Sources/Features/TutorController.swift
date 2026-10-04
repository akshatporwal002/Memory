import Foundation
import Observation
import LearningCore
import PersistenceAdapters

@MainActor @Observable final class TutorController {
    private(set) var activated = false
    private(set) var workspace: TutorWorkspace?
    var error: String?
    private var account = ""
    private var owner: UUID?
    private let repository: TutorWorkspaceRepository
    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        repository = TutorWorkspaceRepository(directory: root.appendingPathComponent("Engram/TutorDrafts", isDirectory: true))
    }
    func configure(_ model: EngramModel) async {
        let key = model.testingScope ?? model.cloud.userID?.uuidString.lowercased() ?? model.cloud.localProfileID ?? "local"
        guard key != account else { return }
        account = key; workspace = nil; error = nil
        let idKey = "engram.tutor.draftOwner." + key
        let id = (model.testingScope == nil ? model.cloud.userID : nil) ?? UserDefaults.standard.string(forKey: idKey).flatMap(UUID.init(uuidString:)) ?? UUID()
        UserDefaults.standard.set(id.uuidString, forKey: idKey); owner = id
        activated = UserDefaults.standard.bool(forKey: "engram.tutor.active." + key)
        if activated {
            do { let value = try await repository.ensureWorkspace(ownerID: id); if account == key { workspace = value } }
            catch { if account == key { self.error = error.localizedDescription } }
        }
    }
    func activate(_ model: EngramModel) async {
        await configure(model)
        guard let owner else { return }
        let key = account
        do {
            let value = try await repository.ensureWorkspace(ownerID: owner)
            guard account == key else { return }
            workspace = value; activated = true
            UserDefaults.standard.set(true, forKey: "engram.tutor.active." + key)
        } catch { self.error = error.localizedDescription }
    }
    func save(_ next: TutorWorkspace) async {
        guard let current = workspace, next.id == current.id, next.ownerID == owner else { return }
        let key = account
        do {
            var value = next; value.version = current.version + 1
            try await repository.save(value, expectedVersion: current.version)
            if account == key { workspace = value; error = nil }
        } catch { if account == key { self.error = error.localizedDescription } }
    }
}
