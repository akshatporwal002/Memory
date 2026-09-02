import Foundation
import CSQLite
import LearningCore

final class PackageDatabase {
    private var handle: OpaquePointer?
    init(url: URL, create: Bool) throws {
        let flags = create ? SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE : SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            if let handle { sqlite3_close(handle) }; handle = nil
            throw EngramError.invalid("The package collection is not a readable SQLite database.")
        }
        sqlite3_limit(handle, SQLITE_LIMIT_LENGTH, 16 * 1_024 * 1_024)
        sqlite3_limit(handle, SQLITE_LIMIT_SQL_LENGTH, 1_000_000)
        try execute("PRAGMA trusted_schema=OFF")
        if !create { try execute("PRAGMA query_only=ON") }
    }
    deinit { close() }
    func close() { if let handle { sqlite3_close(handle); self.handle = nil } }
    func execute(_ sql: String, _ values: [String] = []) throws {
        let statement = try prepare(sql, values); defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }
    func rows(_ sql: String) throws -> [[String: String]] {
        let statement = try prepare(sql, []); defer { sqlite3_finalize(statement) }
        var result: [[String: String]] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW, result.count < 1_000_000 else { throw failure() }
            var row: [String: String] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                guard let name = sqlite3_column_name(statement, index) else { continue }
                if let value = sqlite3_column_text(statement, index) {
                    let count = Int(sqlite3_column_bytes(statement, index))
                    guard let text = String(bytes: UnsafeBufferPointer(start: value, count: count), encoding: .utf8) else { throw EngramError.invalid("Anki database contains invalid UTF-8 text.") }
                    row[String(cString: name)] = text
                }
                else { row[String(cString: name)] = "" }
            }
            result.append(row)
        }
        return result
    }
    private func prepare(_ sql: String, _ values: [String]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        for (index, value) in values.enumerated() {
            let result = value.withCString { sqlite3_bind_text(statement, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            if result != SQLITE_OK { sqlite3_finalize(statement); throw failure() }
        }
        return statement
    }
    private func failure() -> EngramError { .invalid("Package database validation failed: \(handle.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown error")") }
}

func withTemporaryDatabase<T>(_ data: Data?, _ body: (PackageDatabase, URL) throws -> T) throws -> T {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("engram-package-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("collection.sqlite")
    if let data { try data.write(to: url) }
    let db = try PackageDatabase(url: url, create: data == nil)
    defer { db.close() }
    return try body(db, url)
}
