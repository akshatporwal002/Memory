import Foundation
import CArchive
import LearningCore

/// Bounded in-memory ZIP codec. No archive member is ever extracted to its named path.
enum SafeArchive {
    static let maximumBytes = 768 * 1_024 * 1_024
    static func digest(_ data: Data) -> String {
        var output = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { eg_sha256($0.baseAddress, $0.count, &output) }
        return output.map { String(format: "%02x", $0) }.joined()
    }
    static func read(_ url: URL) throws -> [String: Data] {
        try decode(loadBytes(url))
    }
    static func loadBytes(_ url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= maximumBytes else { throw EngramError.invalid("The archive is empty or exceeds the 768 MB limit.") }
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= maximumBytes else { throw EngramError.invalid("Archive exceeds the 768 MB limit.") }
        return bytes
    }
    static func decode(_ bytes: Data) throws -> [String: Data] {
        guard bytes.count <= maximumBytes else { throw EngramError.invalid("Archive exceeds the 768 MB limit.") }
        return try bytes.withUnsafeBytes { buffer in
            guard let reader = eg_zip_open(buffer.baseAddress, buffer.count) else { throw EngramError.invalid("This is not a readable ZIP package.") }
            defer { eg_zip_close(reader) }
            let count = eg_zip_count(reader)
            guard count <= 100_000 else { throw EngramError.invalid("Archive has more than 100,000 entries.") }
            var entries: [(UInt32, String, UInt64)] = [], names = Set<String>(), total: UInt64 = 0
            for index in 0..<count {
                var name = [CChar](repeating: 0, count: 1024), expanded: UInt64 = 0, compressed: UInt64 = 0
                guard eg_zip_stat(reader, index, &name, name.count, &expanded, &compressed) != 0,
                      let filename = String(validatingUTF8: name) else { throw EngramError.unsupported("Encrypted, directory, invalid-name or unsupported ZIP entry.") }
                try LibraryValidation.validateMediaName(filename)
                guard names.insert(filename.lowercased()).inserted else { throw EngramError.invalid("Duplicate archive filename: \(filename)") }
                guard expanded <= 256 * 1_024 * 1_024 else { throw EngramError.invalid("An archive entry exceeds 256 MB.") }
                total += expanded
                guard total <= maximumBytes, expanded <= max(compressed, 1) * 10_000 else { throw EngramError.invalid("The archive expands beyond safe limits.") }
                entries.append((index, filename, expanded))
            }
            var result: [String: Data] = [:]
            for (index, name, expanded) in entries {
                var length = 0
                guard let data = eg_zip_extract(reader, index, &length) else { throw EngramError.invalid("Archive entry is corrupt or failed its checksum: \(name)") }
                defer { eg_zip_free(data) }
                guard length == Int(expanded) else { throw EngramError.invalid("Archive entry length mismatch.") }
                result[name] = Data(bytes: data, count: length)
            }
            return result
        }
    }
    static func write(_ entries: [String: Data], to url: URL) throws {
        guard entries.count <= 100_000, entries.values.reduce(0, { $0 + $1.count }) <= maximumBytes else { throw EngramError.invalid("Export exceeds the archive limit.") }
        guard let writer = eg_zip_writer() else { throw EngramError.storage("Could not allocate export archive.") }
        var active = true
        defer { if active { eg_zip_abort(writer) } }
        for name in entries.keys.sorted() {
            try LibraryValidation.validateMediaName(name)
            let ok = entries[name]!.withUnsafeBytes { bytes in name.withCString { eg_zip_add(writer, $0, bytes.baseAddress, bytes.count) } }
            guard ok != 0 else { throw EngramError.storage("Could not write archive entry \(name).") }
        }
        var length = 0
        let result = eg_zip_finish(writer, &length); active = false
        guard let result else { throw EngramError.storage("Could not finish export archive.") }
        defer { eg_zip_free(result) }
        try Data(bytes: result, count: length).write(to: url, options: .atomic)
    }
}

public enum NativeBackupAdapter {
    private struct Manifest: Codable {
        var format = "engram-native-backup"
        var version = 1
        var library: LibrarySnapshot
        var media: [MediaEntry]
    }
    private struct MediaEntry: Codable { var name: String; var member: String; var size: Int }
    public static func write(_ snapshot: LibrarySnapshot, to url: URL) throws {
        try LibraryValidation.validate(snapshot)
        var library = snapshot; library.media = []
        var entries: [String: Data] = [:]
        let media = snapshot.media.enumerated().map { index, item -> MediaEntry in
            let key = "media-\(index)"; entries[key] = item.data
            return MediaEntry(name: item.name, member: key, size: item.data.count)
        }
        entries["manifest.json"] = try JSONEncoder().encode(Manifest(library: library, media: media))
        try SafeArchive.write(entries, to: url)
    }
    public static func read(from url: URL) throws -> LibrarySnapshot {
        let entries = try SafeArchive.read(url)
        guard let json = entries["manifest.json"] else { throw EngramError.invalid("Native backup manifest is missing.") }
        let manifest = try JSONDecoder().decode(Manifest.self, from: json)
        guard manifest.format == "engram-native-backup", manifest.version == 1 else { throw EngramError.unsupported("This native backup version is not supported. Nothing was restored.") }
        guard manifest.library.media.isEmpty, Set(manifest.media.map(\.member)).count == manifest.media.count,
              entries.count == manifest.media.count + 1 else { throw EngramError.invalid("Native backup media manifest is inconsistent.") }
        var snapshot = manifest.library
        for item in manifest.media {
            try LibraryValidation.validateMediaName(item.member)
            guard item.member != "manifest.json", let data = entries[item.member], data.count == item.size else { throw EngramError.invalid("Backup media is missing or corrupt: \(item.name)") }
            snapshot.media.append(MediaFile(name: item.name, data: data))
        }
        try LibraryValidation.validate(snapshot)
        return snapshot
    }
}
