import XCTest
@testable import CloudAdapters
import LearningCore
import StudyApplication
import PersistenceAdapters
import SchedulingAdapters

final class CloudSyncTests: XCTestCase {
    func testPrivateRPCIncludesNullDeckArgument() throws {
        let operation = CloudApply(operationID:UUID(),kind:"private",id:"learner:memory:id",deckID:nil,version:0,content:.null)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(operation)) as? [String:Any])
        XCTAssertTrue(object["target_deck"] is NSNull)
    }
    func testRevokedSharedCacheAndPrivateProjectionStayRemoved() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let owner = UUID(), viewer = UUID(), server = FakeCloud(user:owner)
        let a = try SQLiteLibraryRepository(url:directory.appendingPathComponent("owner.sqlite"))
        let b = try SQLiteLibraryRepository(url:directory.appendingPathComponent("viewer.sqlite"))
        try await a.selectAccount(owner.uuidString.lowercased()); try await b.selectAccount(viewer.uuidString.lowercased())
        let app = StudyService(repository:a,scheduler:FSRSScheduler())
        let deck = try await app.createDeck(name:"Shared")
        let note = try await app.saveNote(NoteDraft(deckID:deck.id,front:"Energy?",back:"ATP"),now:Date())
        try await app.saveLearningMemory(LearningMemory(noteID:note.id,text:"Owner-private misconception"))
        let ea = CloudSyncEngine(repository:a,client:server,scheduler:FSRSScheduler()),eb = CloudSyncEngine(repository:b,client:server,scheduler:FSRSScheduler())
        _ = try await ea.synchronize(); await server.grant(deck.id,to:viewer); await server.setUser(viewer)
        _ = try await eb.synchronize()
        let received = try await b.read(); XCTAssertEqual(received.liveNotes.count,1); XCTAssertTrue(received.assistantState?.memory.isEmpty ?? true)
        let viewerApp = StudyService(repository:b,scheduler:FSRSScheduler())
        try await viewerApp.saveLearningMemory(LearningMemory(noteID:note.id,text:"Viewer-private misconception"))
        _ = try await eb.synchronize()
        await server.revoke(deck.id,from:viewer)
        let report = try await eb.synchronize(); XCTAssertEqual(report.removedDecks,[deck.id])
        _ = try await eb.synchronize()
        let revoked = try await b.read(); XCTAssertTrue(revoked.notes.isEmpty); XCTAssertTrue(revoked.cards.isEmpty); XCTAssertTrue(revoked.assistantState?.memory.isEmpty ?? true)
    }
    func testTwoDevicesSynchronizeContentAndKeepStudyLocal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let user = UUID(), server = FakeCloud(user:UUID())
        await server.setUser(user)
        let a = try SQLiteLibraryRepository(url:directory.appendingPathComponent("a.sqlite"))
        let b = try SQLiteLibraryRepository(url:directory.appendingPathComponent("b.sqlite"))
        try await a.selectAccount(user.uuidString.lowercased()); try await b.selectAccount(user.uuidString.lowercased())
        let app = StudyService(repository:a,scheduler:FSRSScheduler())
        let deck = try await app.createDeck(name:"Science")
        _ = try await app.saveNote(NoteDraft(deckID:deck.id,front:"Energy?",back:"ATP"),now:Date())
        let ea = CloudSyncEngine(repository:a,client:server,scheduler:FSRSScheduler()), eb = CloudSyncEngine(repository:b,client:server,scheduler:FSRSScheduler())
        _ = try await ea.synchronize(); _ = try await eb.synchronize()
        let received = try await b.read()
        XCTAssertEqual(received.liveDecks.first?.name,"Science")
        XCTAssertEqual(received.liveNotes.first?.back,"ATP")
        XCTAssertNil(received.session)
        let pending = try await a.pendingOperations(); XCTAssertTrue(pending.isEmpty)
        // Independent content fields should merge rather than produce a last-writer overwrite.
        let appB = StudyService(repository:b,scheduler:FSRSScheduler())
        var da = NoteDraft(note:try XCTUnwrap(received.liveNotes.first)); da.front = "Cellular energy?"
        var db = da; db.front = "Energy?"; db.back = "Adenosine triphosphate"
        _ = try await app.saveNote(da,now:Date()); _ = try await appB.saveNote(db,now:Date())
        _ = try await ea.synchronize(); let report = try await eb.synchronize()
        XCTAssertTrue(report.conflicts.isEmpty)
        _ = try await ea.synchronize()
        let merged = try await a.read()
        XCTAssertEqual(merged.liveNotes.first?.front,"Cellular energy?")
        XCTAssertEqual(merged.liveNotes.first?.back,"Adenosine triphosphate")
    }
    func testSharedProjectionOmitsPDFAndPrivateLearning() throws {
        var library = LibrarySnapshot()
        let deck = Deck(id:"d",name:"Deck"); library.decks = [deck]
        library.assistantState = LearningAssistantState()
        library.assistantState?.memory = [LearningMemory(noteID:"n",text:"Private misconception")]
        let entities = try CloudProjection.entities(library,userID:UUID(),ownedDecks:["d"])
        let shared = entities.filter { $0.kind != "private" }
        let text = String(decoding:try JSONEncoder().encode(shared),as:UTF8.self)
        XCTAssertFalse(text.contains("Private misconception")); XCTAssertFalse(text.contains("pdfLearning"))
        XCTAssertTrue(entities.contains { $0.id.contains(":memory:") && $0.kind == "private" })
    }
}

private actor FakeCloud: CloudTransport {
    private var user: UUID
    private var rows: [String:CloudChange] = [:]
    private var log: [CloudChange] = []
    private var operations: [UUID:CloudApplyResult] = [:]
    private var owners: [String:UUID] = [:]
    private var access: [String:Set<UUID>] = [:]
    init(user: UUID) { self.user = user }
    func setUser(_ id: UUID) { user = id }
    func currentUserID() -> UUID { user }
    func grant(_ deck: String,to member: UUID) { access[deck,default:[]].insert(member) }
    func revoke(_ deck: String,from member: UUID) { access[deck]?.remove(member) }
    func apply(_ op: CloudApply) throws -> CloudApplyResult {
        if let prior = operations[op.operation_id] { return prior }
        let key = op.entity_kind + ":" + op.entity_id
        let version = rows[key]?.version ?? 0
        guard version == op.base_version else { return CloudApplyResult(status:"conflict",version:version,payload:rows[key]?.payload,deleted:false) }
        let row = CloudChange(sequence:Int64(log.count+1),kind:op.entity_kind,entity_id:op.entity_id,deck_id:op.target_deck,learner_id:op.entity_kind == "private" ? user : nil,version:version+1,payload:op.content,deleted:op.is_deleted)
        rows[key] = row; log.append(row)
        if op.entity_kind == "deck",owners[op.entity_id] == nil { owners[op.entity_id] = user }
        let result = CloudApplyResult(status:"saved",version:version+1,payload:nil,deleted:nil); operations[op.operation_id] = result
        return result
    }
    func changes(after sequence: Int64) -> [CloudChange] { Array(log.filter { $0.sequence > sequence && ($0.kind == "private" ? $0.learner_id == user : $0.deck_id.map { owners[$0] == user || access[$0]?.contains(user) == true } == true) }.prefix(500)) }
    func decks() -> [CloudDeckAccess] { rows.values.filter { $0.kind == "deck" && (owners[$0.entity_id] == user || access[$0.entity_id]?.contains(user) == true) }.map { CloudDeckAccess(id:$0.entity_id,owner_id:owners[$0.entity_id]!,deleted:$0.deleted) } }
    func memberships() -> [CloudMembership] { access.flatMap { deck,members in members.map { CloudMembership(deck_id:deck,user_id:$0,role:"viewer") } } }
}
