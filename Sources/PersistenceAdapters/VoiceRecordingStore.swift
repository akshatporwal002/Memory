import Foundation
import LearningCore

/// One instance per app-account recording directory. Raw recordings never enter
/// the library database, outbox, exports or cloud Storage.
public actor VoiceRecordingStore: VoiceAudioStorage {
    private let directory: URL
    public init(directory: URL) throws {
        let requested = directory.standardizedFileURL
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: true)
        self.directory = requested.resolvingSymlinksInPath()
        #if os(iOS) || os(macOS)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var folder = self.directory; try folder.setResourceValues(values)
        #endif
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: self.directory.path)
        #endif
    }
    public func save(_ audio: Data, id: UUID, now: Date = Date()) throws {
        guard !audio.isEmpty, audio.count <= 25_000_000, now.timeIntervalSince1970.isFinite else { throw EngramError.invalid("Keep recordings under 25 MB.") }
        let url = try location(id)
        if FileManager.default.fileExists(atPath: url.path) {
            guard try Data(contentsOf: url) == audio else { throw EngramError.conflict }
            return
        }
        #if os(iOS)
        try audio.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try audio.write(to: url, options: .atomic)
        #endif
        #if os(iOS) || os(macOS)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var file = url; try file.setResourceValues(values)
        #endif
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
    }
    public func read(_ id: UUID) throws -> Data {
        let url = try location(id)
        guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, (1...25_000_000).contains(size) else { throw EngramError.invalid("This recording is unavailable or too large.") }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty, data.count <= 25_000_000 else { throw EngramError.invalid("This recording is unavailable or too large.") }
        return data
    }
    public func remove(_ id: UUID) throws {
        let url = try location(id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    /// Captured-but-unclaimed and failed audio expire too. The worker must treat a
    /// missing recording as needs-attention, never invent a transcript or grade.
    @discardableResult public func removeExpired(now: Date = Date()) throws -> [UUID] {
        guard now.timeIntervalSince1970.isFinite else { throw EngramError.invalid("Invalid expiry date.") }
        var removed: [UUID] = []
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]) {
            guard file.pathExtension == "wav", let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  let date = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  now.timeIntervalSince(date) >= 7 * 24 * 60 * 60 else { continue }
            try remove(id); removed.append(id)
        }
        return removed
    }
    private func location(_ id: UUID) throws -> URL {
        let url = directory.appendingPathComponent(id.uuidString.lowercased()).appendingPathExtension("wav")
        guard url.resolvingSymlinksInPath().deletingLastPathComponent().path == directory.path else { throw EngramError.invalid("Unsafe recording path.") }
        return url
    }
}
