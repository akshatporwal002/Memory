import Foundation
import LearningCore

/// Recovery for a library that cannot be opened by the normal repository. The caller
/// must inspect a backup, obtain explicit replacement confirmation, and supply the exact
/// original bytes observed during that inspection (nil means the file was absent).
/// This helper never deletes or truncates the old file before the atomic replacement.
public enum StartupLibraryRecovery {
    @discardableResult public static func restore(_ candidate: LibrarySnapshot, to libraryURL: URL,
        expectedOriginal: Data?, preservingOriginalIn recoveryDirectory: URL) throws -> URL? {
        guard libraryURL.isFileURL, recoveryDirectory.isFileURL else { throw EngramError.invalid("Recovery requires local library locations.") }
        try LibraryValidation.validate(candidate)
        var restored = candidate
        restored.session = nil
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(restored)
        let files = FileManager.default
        let current = files.fileExists(atPath: libraryURL.path) ? try Data(contentsOf: libraryURL) : nil
        guard current == expectedOriginal else { throw EngramError.conflict }
        var preserved: URL?
        if let current {
            try files.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
            let destination = recoveryDirectory.appendingPathComponent("Unreadable-library-\(UUID().uuidString).original")
            // copyItem refuses to overwrite; a failed copy cannot affect the source file.
            try files.copyItem(at: libraryURL, to: destination)
            guard try Data(contentsOf: destination) == current else { throw EngramError.storage("The original library could not be preserved exactly. Recovery stopped before replacement.") }
            preserved = destination
        }
        try files.createDirectory(at: libraryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let rechecked = files.fileExists(atPath: libraryURL.path) ? try Data(contentsOf: libraryURL) : nil
        guard rechecked == expectedOriginal else { throw EngramError.conflict }
        try encoded.write(to: libraryURL, options: .atomic)
        return preserved
    }
}
