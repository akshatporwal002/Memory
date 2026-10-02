import XCTest
@testable import CloudAdapters
import LearningCore
import StudyApplication
import PersistenceAdapters
import SchedulingAdapters

final class CloudSyncTests: XCTestCase {
    func testMovingSharedQuestionHidesDestinationFromOldOnlyMember() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let owner = UUID(),viewer = UUID(),server = FakeCloud(user:owner)
        let a = try SQLiteLibraryRepository(url:directory.appendingPathComponent("a.sqlite")),b = try SQLiteLibraryRepository(url:directory.appendingPathComponent("b.sqlite"))
        try await a.selectAccount(owner.uuidString.lowercased()); try await b.selectAccount(viewer.uuidString.lowercased())
        let app = StudyService(repository:a,scheduler:FSRSScheduler())
        let source = try await app.createDeck(name:"Shared"),destination = try await app.createDeck(name:"Private destination")
        let note = try await app.saveNote(NoteDraft(deckID:source.id,front:"Energy?",back:"ATP"),now:Date())
        let ea = CloudSyncEngine(repository:a,client:server,scheduler:FSRSScheduler()),eb = CloudSyncEngine(repository:b,client:server,scheduler:FSRSScheduler())
        _ = try await ea.synchronize(); await server.grant(source.id,to:viewer); await server.setUser(viewer); _ = try await eb.synchronize()
        let before = try await b.read(); XCTAssertEqual(before.liveNotes.first?.id,note.id); XCTAssertFalse(before.liveDecks.contains(where: { $0.id == destination.id }))
        await server.setUser(owner)
        var draft = NoteDraft(note:note); draft.deckID = destination.id; draft.front = "Private destination question"
        _ = try await app.saveNote(draft,now:Date())
        let report = try await ea.synchronize(); XCTAssertTrue(report.conflicts.isEmpty)
        await server.setUser(viewer); _ = try await eb.synchronize()
        let after = try await b.read()
        XCTAssertFalse(after.liveNotes.contains(where: { $0.id == note.id }))
        XCTAssertFalse(after.liveDecks.contains(where: { $0.id == destination.id }))
        XCTAssertTrue(after.cards.filter { $0.noteID == note.id }.allSatisfy(\.retired))
    }
    func testPrivateDocumentSyncPreservesOriginalAndRejectsForeignScope() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let user = UUID(),server = FakeCloud(user:user)
        let a = try SQLiteLibraryRepository(url:directory.appendingPathComponent("a.sqlite")),b = try SQLiteLibraryRepository(url:directory.appendingPathComponent("b.sqlite"))
        try await a.selectAccount(user.uuidString.lowercased()); try await b.selectAccount(user.uuidString.lowercased())
        var library = try await a.read(),deck = Deck(id:"pdf-deck",name:"PDF")
        let original = Data("%PDF-1.7 fixture".utf8),source = PDFLearningSource(filename:"source.pdf",pages:[PDFPageText(number:1,text:"ATP stores energy")],originalPDFData:original)
        deck.pdfLearning = PDFLearningRecord(source:source,brief:PDFLearningBrief(),items:[])
        let markdown = Data("# Energy\nATP stores energy".utf8)
        deck.documents = [LibraryDocument(name:"energy.md",kind:.markdown,pages:[PDFPageText(number:1,text:String(decoding:markdown,as:UTF8.self))],originalData:markdown)]
        library.decks = [deck]
        let projection = try CloudProjection.entities(library,userID:user,ownedDecks:[deck.id])
        XCTAssertNil(try projection.first(where: { $0.kind == "deck" })?.payload.decode(Deck.self).documents)
        try await a.commit(library,expectedRevision:library.revision)
        let ea = CloudSyncEngine(repository:a,client:server,scheduler:FSRSScheduler()),eb = CloudSyncEngine(repository:b,client:server,scheduler:FSRSScheduler())
        _ = try await ea.synchronize(); _ = try await eb.synchronize()
        let received = try await b.read(); XCTAssertEqual(received.liveDecks.first?.pdfLearning?.source.originalPDFData,original)
        XCTAssertEqual(received.liveDecks.first?.documents?.first?.originalData,markdown)
        let data = try PrivateCloudDocument.encode(try XCTUnwrap(deck.pdfLearning)),path = PrivateCloudDocument.path(data:data,userID:user)
        XCTAssertThrowsError(try PrivateCloudDocument.validate(path:path,data:Data("corrupt".utf8),userID:user))
        XCTAssertThrowsError(try PrivateCloudDocument.validate(path:path,data:data,userID:UUID()))
        let projected = try CloudProjection.entities(library,userID:user,ownedDecks:[deck.id])
        XCTAssertFalse(String(decoding:try JSONEncoder().encode(projected),as:UTF8.self).contains("originalPDFData"))
    }
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
        let session = try await viewerApp.startSession(deckID:deck.id,now:Date())
        XCTAssertNotNil(session.current)
        await server.revoke(deck.id,from:viewer)
        let report = try await eb.synchronize(); XCTAssertEqual(report.removedDecks,[deck.id])
        _ = try await eb.synchronize()
        let revoked = try await b.read(); XCTAssertTrue(revoked.notes.isEmpty); XCTAssertTrue(revoked.cards.isEmpty); XCTAssertTrue(revoked.assistantState?.memory.isEmpty ?? true); XCTAssertNil(revoked.session)
    }
    func testOrdinaryChangesWaitUntilQuestionBoundary() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let user = UUID(),server = FakeCloud(user:user)
        let a = try SQLiteLibraryRepository(url:directory.appendingPathComponent("a.sqlite")),b = try SQLiteLibraryRepository(url:directory.appendingPathComponent("b.sqlite"))
        try await a.selectAccount(user.uuidString.lowercased()); try await b.selectAccount(user.uuidString.lowercased())
        let app = StudyService(repository:a,scheduler:FSRSScheduler()),appB = StudyService(repository:b,scheduler:FSRSScheduler())
        let deck = try await app.createDeck(name:"Science")
        let note = try await app.saveNote(NoteDraft(deckID:deck.id,front:"Energy?",back:"ATP"),now:Date())
        let ea = CloudSyncEngine(repository:a,client:server,scheduler:FSRSScheduler()),eb = CloudSyncEngine(repository:b,client:server,scheduler:FSRSScheduler())
        _ = try await ea.synchronize(); _ = try await eb.synchronize()
        let session = try await appB.startSession(deckID:deck.id,now:Date())
        var draft = NoteDraft(note:note); draft.back = "Adenosine triphosphate"
        _ = try await app.saveNote(draft,now:Date()); _ = try await ea.synchronize()
        _ = try await eb.synchronize()
        let held = try await b.read(); XCTAssertEqual(held.liveNotes.first?.back,"ATP"); XCTAssertEqual(held.session?.current?.presentationID,session.current?.presentationID)
        _ = try await eb.synchronize(allowStudyBoundary:true)
        let updated = try await b.read(); XCTAssertEqual(updated.liveNotes.first?.back,"Adenosine triphosphate"); XCTAssertNotEqual(updated.session?.current?.presentationID,session.current?.presentationID)
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
    private var documents: [String:Data] = [:]
    init(user: UUID) { self.user = user }
    func setUser(_ id: UUID) { user = id }
    func currentUserID() -> UUID { user }
    func uploadPrivateDocument(path: String,data: Data) throws { try PrivateCloudDocument.validate(path:path,data:data,userID:user); documents[path] = data }
    func downloadPrivateDocument(path: String) throws -> Data { try PrivateCloudDocument.validatePath(path,userID:user); guard let data = documents[path] else { throw EngramError.missing("document") }; return data }
    func grant(_ deck: String,to member: UUID) { access[deck,default:[]].insert(member) }
    func revoke(_ deck: String,from member: UUID) { access[deck]?.remove(member) }
    func apply(_ op: CloudApply) throws -> CloudApplyResult {
        if let prior = operations[op.operation_id] { return prior }
        let key = op.entity_kind + ":" + op.entity_id
        let version = rows[key]?.version ?? 0
        guard version == op.base_version else { return CloudApplyResult(status:"conflict",version:version,payload:rows[key]?.payload,deleted:false) }
        let moved = op.entity_kind == "note" && rows[key] != nil && rows[key]?.deck_id != op.target_deck
        if moved,let previous = rows[key] {
            var tombstone = previous
            tombstone.sequence = Int64(log.count+1); tombstone.version = version+1; tombstone.deleted = true
            if case .object(var object) = tombstone.payload { object["deleted"] = .bool(true); tombstone.payload = .object(object) }
            log.append(tombstone)
        }
        let row = CloudChange(sequence:Int64(log.count+1),kind:op.entity_kind,entity_id:op.entity_id,deck_id:op.target_deck,learner_id:op.entity_kind == "private" ? user : nil,version:version+(moved ? 2 : 1),payload:op.content,deleted:op.is_deleted)
        rows[key] = row; log.append(row)
        if op.entity_kind == "deck",owners[op.entity_id] == nil { owners[op.entity_id] = user }
        let result = CloudApplyResult(status:"saved",version:row.version,payload:nil,deleted:nil); operations[op.operation_id] = result
        return result
    }
    func changes(after sequence: Int64) -> [CloudChange] { Array(log.filter { $0.sequence > sequence && ($0.kind == "private" ? $0.learner_id == user : $0.deck_id.map { owners[$0] == user || access[$0]?.contains(user) == true } == true) }.prefix(500)) }
    func decks() -> [CloudDeckAccess] { rows.values.filter { $0.kind == "deck" && (owners[$0.entity_id] == user || access[$0.entity_id]?.contains(user) == true) }.map { CloudDeckAccess(id:$0.entity_id,owner_id:owners[$0.entity_id]!,deleted:$0.deleted) } }
    func memberships() -> [CloudMembership] { access.flatMap { deck,members in members.map { CloudMembership(deck_id:deck,user_id:$0,role:"viewer") } } }
}
