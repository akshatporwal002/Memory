import Foundation
import CryptoKit
import LearningCore
import PersistenceAdapters

public struct CloudConflict: Codable, Identifiable, Sendable {
    public var id: String
    public var entity: CloudProjectionEntity
    public var base: JSONValue
    public var yours: JSONValue
    public var theirs: JSONValue
    public var remoteVersion: Int64
    public var paths: [String]
}
private struct CloudBaseline: Codable { var entity: CloudProjectionEntity; var version: Int64 }
private struct CloudSyncState: Codable {
    var cursor: Int64 = 0
    var baselines: [String:CloudBaseline] = [:]
    var conflicts: [CloudConflict] = []
    var permissions: [String:String] = [:]
}
public struct CloudSyncReport: Sendable { public var pending: Int; public var conflicts: [CloudConflict]; public var removedDecks: [String]; public var adjustedDueDates: Int }

public actor CloudSyncEngine {
    private let repository: SQLiteLibraryRepository
    private let client: SupabaseCloudClient
    private let scheduler: any Scheduler
    public init(repository: SQLiteLibraryRepository,client: SupabaseCloudClient,scheduler: any Scheduler) { self.repository = repository; self.client = client; self.scheduler = scheduler }
    public func synchronize() async throws -> CloudSyncReport {
        let user = try await client.currentUserID()
        guard try await client.currentUserID().uuidString.lowercased() == repository.activeAccountID() else { throw EngramError.conflict }
        let original = try await repository.read()
        guard original.session?.current == nil else { return CloudSyncReport(pending:try await repository.pendingOperations().count,conflicts:[],removedDecks:[],adjustedDueDates:0) }
        var library = original
        var state = try await loadState()
        let decks = try await client.decks(), memberships = try await client.memberships()
        var permissions: [String:String] = [:]
        for deck in decks where !deck.deleted {
            permissions[deck.id] = deck.owner_id == user ? "owner" : memberships.first(where: { $0.deck_id == deck.id && $0.user_id == user })?.role ?? "viewer"
        }
        let removed = state.permissions.keys.filter { permissions[$0] == nil }
        for id in removed {
            let noteIDs = Set(library.notes.filter { $0.deckID == id }.map(\.id)), cardIDs = Set(library.cards.filter { $0.deckID == id }.map(\.id))
            library.decks.removeAll { $0.id == id }; library.notes.removeAll { $0.deckID == id }; library.cards.removeAll { $0.deckID == id }
            library.reviews.removeAll { $0.deckID == id }; library.importedReviews.removeAll { cardIDs.contains($0.cardID) }
            library.corrections.removeAll { correction in !library.reviews.contains { $0.id == correction.reviewID } }
            library.answerAttempts?.removeAll { noteIDs.contains($0.noteID) }
            library.assistantState?.memory.removeAll { noteIDs.contains($0.noteID) }
            state.baselines = state.baselines.filter { $0.value.entity.deckID != id }
            state.conflicts.removeAll { $0.entity.deckID == id }
        }
        if permissions.keys.contains(where: { state.permissions[$0] == nil }) { state.cursor = 0 }
        let owned = Set(permissions.filter { $0.value == "owner" }.keys).union(library.decks.filter { state.permissions[$0.id] == nil && permissions[$0.id] == nil }.map(\.id))
        var latest = Dictionary(uniqueKeysWithValues:try CloudProjection.entities(library,userID:user,ownedDecks:owned).map { ($0.key,$0) })
        while true {
            let changes = try await client.changes(after:state.cursor)
            for change in changes {
                let entity = CloudProjectionEntity(kind:change.kind,id:change.entity_id,deckID:change.deck_id,payload:change.payload,deleted:change.deleted)
                let key = entity.key
                state.cursor = max(state.cursor,change.sequence)
                if let baseline = state.baselines[key],baseline.version >= change.version { continue }
                if let local = latest[key],let base = state.baselines[key], local.payload != base.entity.payload,local.payload != entity.payload {
                    // Card schedules are derived from immutable review events below, not field-merged.
                    if key.contains(":card:") { try CloudProjection.apply(entity,to:&library) }
                    else {
                        let merge = try ContentMerge.merge(base:JSONEncoder().encode(base.entity.payload),yours:JSONEncoder().encode(local.payload),theirs:JSONEncoder().encode(entity.payload))
                        if let data = merge.merged {
                            var merged = entity; merged.payload = try JSONDecoder().decode(JSONValue.self,from:data); latest[key] = merged
                            try CloudProjection.apply(merged,to:&library)
                        } else {
                            state.conflicts.removeAll { $0.id == key }
                            state.conflicts.append(CloudConflict(id:key,entity:entity,base:base.entity.payload,yours:local.payload,theirs:entity.payload,remoteVersion:change.version,paths:merge.conflictingPaths))
                        }
                    }
                } else { try CloudProjection.apply(entity,to:&library); latest[key] = entity }
                state.baselines[key] = CloudBaseline(entity:entity,version:change.version)
            }
            if changes.count < 500 { break }
        }
        // Build cards for newly shared notes; progress never comes from the owner's schedules.
        for note in library.liveNotes {
            for ordinal in try CardRenderer.ordinals(for:NoteDraft(note:note)) where !library.cards.contains(where: { $0.noteID == note.id && $0.ordinal == ordinal }) {
                library.cards.append(StudyCard(id:"shared-" + note.id + "-" + String(ordinal),noteID:note.id,deckID:note.deckID,ordinal:ordinal,schedule:try scheduler.initialState(now:Date(),settings:library.settings)))
            }
        }
        var adjustments = 0
        for index in library.cards.indices {
            let card = library.cards[index]
            let state = try ReviewReconciliation.replay(card:card,events:library.activeReviews,settings:library.settings,scheduler:scheduler)
            if state != card.schedule { library.cards[index].schedule = state; library.cards[index].version += 1; adjustments += 1 }
        }
        let pending = try await repository.pendingOperations().filter { $0.revision <= original.revision }
        var acknowledgements: [String] = []
        if let operation = pending.first {
            let entities = try CloudProjection.entities(library,userID:user,ownedDecks:owned)
            for entity in entities.sorted(by: { $0.kind == "deck" && $1.kind != "deck" }) {
                try Task.checkCancellation()
                if entity.deckID.map({ permissions[$0] == "viewer" || removed.contains($0) }) == true { continue }
                if state.conflicts.contains(where: { $0.id == entity.key }) { continue }
                let baseline = state.baselines[entity.key]
                if baseline?.entity.payload == entity.payload,baseline?.entity.deleted == entity.deleted { continue }
                let result = try await client.apply(CloudApply(operationID:Self.operationID(operation.id + entity.key + String(baseline?.version ?? 0) + (try Self.canonical(entity.payload))),kind:entity.kind,id:entity.id,deckID:entity.deckID,version:baseline?.version ?? 0,content:entity.payload,deleted:entity.deleted))
                if result.status == "saved",let version = result.version { state.baselines[entity.key] = CloudBaseline(entity:entity,version:version) }
                else if let theirs = result.payload {
                    state.conflicts.append(CloudConflict(id:entity.key,entity:entity,base:baseline?.entity.payload ?? .null,yours:entity.payload,theirs:theirs,remoteVersion:result.version ?? 0,paths:["/"]))
                } else { throw EngramError.storage("The server did not acknowledge this operation.") }
                guard try await client.currentUserID() == user, await repository.activeAccountID() == user.uuidString.lowercased() else { throw EngramError.conflict }
                try await repository.saveCloudState(JSONEncoder().encode(state))
            }
            if state.conflicts.isEmpty { acknowledgements = pending.map(\.id) }
        }
        guard try await client.currentUserID() == user, await repository.activeAccountID() == user.uuidString.lowercased() else { throw EngramError.conflict }
        state.permissions = permissions
        try await repository.adoptCloudSnapshot(library,expectedRevision:original.revision,state:JSONEncoder().encode(state),acknowledging:acknowledgements,permissions:permissions)
        return CloudSyncReport(pending:pending.count-acknowledgements.count,conflicts:state.conflicts,removedDecks:removed,adjustedDueDates:adjustments)
    }
    public func resolve(_ conflictID: String,using choice: String) async throws {
        var state = try await loadState()
        guard let conflict = state.conflicts.first(where: { $0.id == conflictID }) else { throw EngramError.missing("conflict") }
        let payload: JSONValue
        switch choice { case "base": payload = conflict.base; case "yours": payload = conflict.yours; case "theirs": payload = conflict.theirs; default: throw EngramError.invalid("Choose Base, Yours, or Theirs.") }
        var entity = conflict.entity; entity.payload = payload
        var library = try await repository.read(); try CloudProjection.apply(entity,to:&library)
        try await repository.commit(library,expectedRevision:library.revision)
        state.baselines[conflict.id] = CloudBaseline(entity:CloudProjectionEntity(kind:entity.kind,id:entity.id,deckID:entity.deckID,payload:conflict.theirs,deleted:entity.deleted),version:conflict.remoteVersion)
        state.conflicts.removeAll { $0.id == conflictID }; try await repository.saveCloudState(JSONEncoder().encode(state))
    }
    private func loadState() async throws -> CloudSyncState { try await repository.cloudState().map { try JSONDecoder().decode(CloudSyncState.self,from:$0) } ?? CloudSyncState() }
    private static func canonical(_ value: JSONValue) throws -> String { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return String(decoding:try encoder.encode(value),as:UTF8.self) }
    private static func operationID(_ text: String) -> UUID {
        var bytes = Array(SHA256.hash(data:Data(text.utf8)).prefix(16)); bytes[6] = (bytes[6] & 0x0f) | 0x50; bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid:(bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
    }
}

