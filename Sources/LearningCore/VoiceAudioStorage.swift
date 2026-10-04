import Foundation

public protocol VoiceAudioStorage: Sendable {
    func read(_ id: UUID) async throws -> Data
    func remove(_ id: UUID) async throws
}
public struct VoiceTranscriptResult: Sendable {
    public let text: String
    public let usageJSON: Data?
    public init(text: String, usageJSON: Data? = nil) { self.text = text; self.usageJSON = usageJSON }
}
