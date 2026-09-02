import Foundation
import LearningCore

public actor MemoryRepository: LibraryRepository {
    private var value: LibrarySnapshot
    private var shouldFail = false
    public init(initial: LibrarySnapshot = LibrarySnapshot()) { value = initial }
    public func read() throws -> LibrarySnapshot { value }
    public func failNextCommit() { shouldFail = true }
    public func commit(_ snapshot: LibrarySnapshot, expectedRevision: Int) throws {
        if shouldFail { shouldFail = false; throw EngramError.storage("Injected transaction failure") }
        guard value.revision == expectedRevision else { throw EngramError.conflict }
        try LibraryValidation.validate(snapshot)
        var next = snapshot; next.revision = expectedRevision + 1; value = next
    }
}

/// One shared instance per application process. The platform shell permits one library window.
/// Copy-on-write snapshot transactions favour recovery and portability over huge-library throughput.
public actor AtomicFileRepository: LibraryRepository {
    private let url: URL
    private var value: LibrarySnapshot
    /// Exact last-read/written bytes let commits detect all sequential external edits
    /// without repeatedly decoding the entire library and its base64 media.
    private var persistedBytes: Data?
    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(LibrarySnapshot.self, from: data)
            try LibraryValidation.validate(decoded)
            value = decoded
            persistedBytes = data
        } else { value = LibrarySnapshot(); persistedBytes = nil }
    }
    public func read() throws -> LibrarySnapshot { value }
    public func commit(_ snapshot: LibrarySnapshot, expectedRevision: Int) throws {
        guard value.revision == expectedRevision else { throw EngramError.conflict }
        let diskBytes = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        guard diskBytes == persistedBytes else { throw EngramError.conflict }
        try LibraryValidation.validate(snapshot)
        var next = snapshot; next.revision = expectedRevision + 1
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(next)
        // Foundation writes a sibling temporary file and atomically renames it. Failure leaves value unchanged.
        try data.write(to: url, options: .atomic)
        value = next; persistedBytes = data
    }
}
