import Foundation
import LearningCore

/// Uses the existing bounded ZIP writer; this is not a restorable library backup.
public enum ScreenshotArchive {
    public static func write(images: [String: Data], manifest: Data, to url: URL) throws {
        guard !images.isEmpty, images.count <= 100,
              images.values.reduce(0, { $0 + $1.count }) <= 100 * 1_024 * 1_024 else {
            throw EngramError.invalid("Screenshot export is empty or exceeds 100 images / 100 MB.")
        }
        for (name, data) in images {
            try LibraryValidation.validateMediaName(name)
            guard name.hasSuffix(".png"), data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else {
                throw EngramError.invalid("Screenshot exports must contain named PNG images.")
            }
        }
        var entries = images
        entries["screenshots.json"] = manifest
        try SafeArchive.write(entries, to: url)
    }
}
