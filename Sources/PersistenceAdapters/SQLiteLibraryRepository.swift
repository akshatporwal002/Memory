import Foundation
import LearningCore
import CSQLite

public struct PendingSyncOperation: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var revision: Int
    public var payload: Data
}

/// Snapshot, outgoing work, account partitions and cursor are one SQLite transaction boundary.
public actor SQLiteLibraryRepository: LibraryRepository {
    private let db: SQLiteConnection
    private var partition = "local"
    private var lease = UUID().uuidString
    public init(url: URL, migrating legacy: URL? = nil) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        db = try SQLiteConnection(url: url)
        try db.execute("PRAGMA journal_mode=WAL")
        try db.execute("PRAGMA synchronous=FULL")
        try db.execute("CREATE TABLE IF NOT EXISTS libraries(account TEXT PRIMARY KEY, revision INTEGER NOT NULL, payload TEXT NOT NULL, upload_enabled INTEGER NOT NULL DEFAULT 0, cursor INTEGER NOT NULL DEFAULT 0)")
        try db.execute("CREATE TABLE IF NOT EXISTS outbox(id TEXT PRIMARY KEY, account TEXT NOT NULL, revision INTEGER NOT NULL, payload TEXT NOT NULL)")
        try db.execute("CREATE TABLE IF NOT EXISTS cloud_state(account TEXT PRIMARY KEY, payload TEXT NOT NULL)")
        try db.execute("CREATE TABLE IF NOT EXISTS cloud_permissions(account TEXT NOT NULL, deck TEXT NOT NULL, role TEXT NOT NULL, PRIMARY KEY(account,deck))")
        if try db.rows("SELECT account FROM libraries WHERE account='local'").isEmpty {
            var snapshot = LibrarySnapshot()
            if let legacy, FileManager.default.fileExists(atPath: legacy.path) {
                let bytes = try Data(contentsOf: legacy)
                snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: bytes)
                try LibraryValidation.validate(snapshot)
                let backup = legacy.appendingPathExtension("sqlite-migration-" + UUID().uuidString + ".backup")
                try FileManager.default.copyItem(at: legacy, to: backup)
                guard try Data(contentsOf: backup) == bytes else { throw EngramError.storage("Migration backup verification failed.") }
            }
            try db.execute("INSERT INTO libraries(account,revision,payload) VALUES(?,?,?)", ["local", String(snapshot.revision), try Self.encode(snapshot)])
            let saved = try db.rows("SELECT payload FROM libraries WHERE account='local'")[0]["payload"]!
            guard try JSONDecoder().decode(LibrarySnapshot.self, from: Data(saved.utf8)) == snapshot else { throw EngramError.storage("Migration verification failed.") }
        }
    }
    public func read() throws -> LibrarySnapshot {
        guard let row = try db.rows("SELECT payload FROM libraries WHERE account=?", [partition]).first, let payload = row["payload"] else { throw EngramError.storage("Account library missing.") }
        var snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(payload.utf8))
        snapshot.repositoryContext = lease; return snapshot
    }
    public func commit(_ snapshot: LibrarySnapshot, expectedRevision: Int) throws {
        guard snapshot.repositoryContext == lease else { throw EngramError.conflict }
        try LibraryValidation.validate(snapshot)
        try db.execute("BEGIN IMMEDIATE")
        do {
            let row = try db.rows("SELECT revision,upload_enabled FROM libraries WHERE account=?", [partition]).first
            guard row?["revision"] == String(expectedRevision) else { throw EngramError.conflict }
            let prior = try read()
            for permission in try db.rows("SELECT deck,role FROM cloud_permissions WHERE account=?",[partition]) {
                let id = permission["deck"]!, role = permission["role"]!
                if role == "viewer" || role == "revoked" {
                    guard snapshot.notes.filter({ $0.deckID == id }) == prior.notes.filter({ $0.deckID == id }) else { throw EngramError.invalid("This shared deck is read-only.") }
                    var before = prior.decks.first { $0.id == id }, after = snapshot.decks.first { $0.id == id }
                    before?.desiredRetention = nil; after?.desiredRetention = nil
                    before?.coverMediaName = nil; after?.coverMediaName = nil
                    before?.modifiedAt = nil; after?.modifiedAt = nil
                    guard before == after else { throw EngramError.invalid("This shared deck is read-only.") }
                } else if role == "editor", let after = snapshot.decks.first(where: { $0.id == id }), after.deleted, prior.decks.first(where: { $0.id == id })?.deleted == false {
                    throw EngramError.invalid("Only the deck owner can delete a shared deck.")
                }
            }
            var next = snapshot; next.revision = expectedRevision + 1
            let payload = try Self.encode(next)
            try db.execute("UPDATE libraries SET revision=?,payload=? WHERE account=?", [String(next.revision),payload,partition])
            if row?["upload_enabled"] == "1" {
                // The snapshot and this durable dirty-revision marker commit together.
                // Sync folds pending revisions into that saved snapshot, without copying
                // entire PDF extracts into every conversation/review queue entry.
                try db.execute("INSERT INTO outbox(id,account,revision,payload) VALUES(?,?,?,?)", [UUID().uuidString,partition,String(next.revision),"{}"])
            }
            try db.execute("COMMIT")
        } catch { try? db.execute("ROLLBACK"); throw error }
    }
    /// Caller confirms any initial local-library upload. Signing in alone never uploads it.
    public func hasAccount(_ userID: String) throws -> Bool {
        !(try db.rows("SELECT account FROM libraries WHERE account=?",["user:" + userID])).isEmpty
    }
    public func selectAccount(_ userID: String?, uploadLocal: Bool = false, syncEnabled: Bool = true, copyCurrentChatGPTProfile: Bool = false) throws {
        let next = userID.map { "user:" + $0 } ?? "local"
        guard !next.contains("\u{0}") else { throw EngramError.invalid("Invalid account.") }
        if copyCurrentChatGPTProfile {
            guard uploadLocal, userID != nil, partition.hasPrefix("user:chatgpt-"), partition != next else { throw EngramError.conflict }
            guard try db.rows("SELECT account FROM libraries WHERE account=?", [next]).isEmpty else {
                throw EngramError.invalid("This account already has a saved library. Use its existing library; your ChatGPT profile's library remains saved separately.")
            }
        }
        try db.execute("BEGIN IMMEDIATE")
        do {
            if try db.rows("SELECT account FROM libraries WHERE account=?", [next]).isEmpty {
                let source = copyCurrentChatGPTProfile ? partition : "local"
                let local = try db.rows("SELECT payload FROM libraries WHERE account=?", [source]).first?["payload"] ?? ""
                var snapshot = uploadLocal ? try JSONDecoder().decode(LibrarySnapshot.self,from:Data(local.utf8)) : LibrarySnapshot(); snapshot.session = nil
                try db.execute("INSERT INTO libraries(account,revision,payload,upload_enabled) VALUES(?,?,?,?)", [next,String(snapshot.revision),try Self.encode(snapshot),userID == nil || !syncEnabled ? "0" : "1"])
                if uploadLocal, userID != nil, syncEnabled { try db.execute("INSERT INTO outbox(id,account,revision,payload) VALUES(?,?,?,?)", [UUID().uuidString,next,String(snapshot.revision),"{}"]) }
            }
            try db.execute("COMMIT"); if partition != next { lease = UUID().uuidString }; partition = next
        } catch { try? db.execute("ROLLBACK"); throw error }
    }
    public func activeAccountID() -> String? { partition.hasPrefix("user:") ? String(partition.dropFirst(5)) : nil }
    public func pendingOperations() throws -> [PendingSyncOperation] {
        try db.rows("SELECT id,revision,payload FROM outbox WHERE account=? ORDER BY revision", [partition]).map { PendingSyncOperation(id:$0["id"]!,revision:Int($0["revision"]!)!,payload:Data($0["payload"]!.utf8)) }
    }
    public func acknowledge(_ operationID: String) throws { try db.execute("DELETE FROM outbox WHERE id=? AND account=?", [operationID,partition]) }
    public func cloudState() throws -> Data? { try db.rows("SELECT payload FROM cloud_state WHERE account=?",[partition]).first?["payload"].flatMap { Data(base64Encoded:$0) } }
    public func saveCloudState(_ data: Data) throws {
        try db.execute("INSERT INTO cloud_state(account,payload) VALUES(?,?) ON CONFLICT(account) DO UPDATE SET payload=excluded.payload",[partition,data.base64EncodedString()])
    }
    /// Incoming projection, change cursor, permissions and acknowledgements advance together.
    public func adoptCloudSnapshot(_ snapshot: LibrarySnapshot,expectedRevision: Int,state: Data,acknowledging: [String],permissions: [String:String]) throws {
        guard snapshot.repositoryContext == lease else { throw EngramError.conflict }
        try LibraryValidation.validate(snapshot)
        try db.execute("BEGIN IMMEDIATE")
        do {
            guard try read().revision == expectedRevision else { throw EngramError.conflict }
            var next = snapshot; next.revision = expectedRevision + 1
            try db.execute("UPDATE libraries SET revision=?,payload=? WHERE account=?",[String(next.revision),try Self.encode(next),partition])
            try saveCloudState(state)
            for id in acknowledging { try acknowledge(id) }
            try db.execute("DELETE FROM cloud_permissions WHERE account=?",[partition])
            for (deck,role) in permissions { try db.execute("INSERT INTO cloud_permissions(account,deck,role) VALUES(?,?,?)",[partition,deck,role]) }
            try db.execute("COMMIT")
        } catch { try? db.execute("ROLLBACK"); throw error }
    }
    private static func encode(_ snapshot: LibrarySnapshot) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(decoding:try encoder.encode(snapshot),as:UTF8.self)
    }
}

private final class SQLiteConnection: @unchecked Sendable {
    private var handle: OpaquePointer?
    init(url: URL) throws {
        guard sqlite3_open_v2(url.path,&handle,SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,nil) == SQLITE_OK else { throw EngramError.storage("Cannot open library database.") }
        sqlite3_busy_timeout(handle,5000)
    }
    deinit { sqlite3_close(handle) }
    func execute(_ sql: String,_ values: [String] = []) throws {
        let statement = try prepare(sql,values); defer { sqlite3_finalize(statement) }
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW { result = sqlite3_step(statement) }
        guard result == SQLITE_DONE else { throw failure() }
    }
    func rows(_ sql: String,_ values: [String] = []) throws -> [[String:String]] {
        let statement = try prepare(sql,values); defer { sqlite3_finalize(statement) }
        var rows: [[String:String]] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return rows }
            guard status == SQLITE_ROW else { throw failure() }
            var row: [String:String] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                if let name = sqlite3_column_name(statement,index), let value = sqlite3_column_text(statement,index) { row[String(cString:name)] = String(cString:value) }
            }
            rows.append(row)
        }
    }
    private func prepare(_ sql: String,_ values: [String]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle,sql,-1,&statement,nil) == SQLITE_OK,let statement else { throw failure() }
        for (index,value) in values.enumerated() {
            let result = value.withCString { sqlite3_bind_text(statement,Int32(index+1),$0,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self)) }
            guard result == SQLITE_OK else { sqlite3_finalize(statement); throw failure() }
        }
        return statement
    }
    private func failure() -> EngramError { .storage("Library database error: " + String(cString:sqlite3_errmsg(handle))) }
}
