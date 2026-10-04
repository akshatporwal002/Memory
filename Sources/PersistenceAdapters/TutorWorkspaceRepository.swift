import Foundation
import LearningCore

/// Device-local drafts. Hosted memberships and entitlements must not be inferred from these files.
public actor TutorWorkspaceRepository {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }

    public func load(ownerID: UUID) throws -> [TutorWorkspace] {
        let url = file(ownerID)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let result = try JSONDecoder().decode([TutorWorkspace].self, from: Data(contentsOf: url))
        guard result.allSatisfy({ $0.ownerID == ownerID }), Set(result.map(\.id)).count == result.count else {
            throw EngramError.storage("Tutor drafts belong to a different account or contain duplicate workspaces.")
        }
        return result
    }

    public func save(_ workspace: TutorWorkspace, expectedVersion: Int?) throws {
        var items = try load(ownerID: workspace.ownerID)
        if let index = items.firstIndex(where: { $0.id == workspace.id }) {
            guard let expectedVersion, items[index].version == expectedVersion,
                  workspace.version == expectedVersion + 1 else { throw EngramError.conflict }
            items[index] = workspace
        } else {
            guard expectedVersion == nil, workspace.version == 1 else { throw EngramError.conflict }
            items.append(workspace)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(items).write(to: file(workspace.ownerID), options: .atomic)
    }

    private func file(_ ownerID: UUID) -> URL {
        directory.appendingPathComponent(ownerID.uuidString.lowercased()).appendingPathExtension("json")
    }
}
