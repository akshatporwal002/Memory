import Foundation

public struct LearningChatMessage: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var role: String
    public var text: String
    public var modelID: String?
    public var createdAt = Date()
    public init(role: String, text: String, modelID: String? = nil) { self.role = role; self.text = text; self.modelID = modelID }
}
public struct LearningConversation: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var modelID: String?
    public var messages: [LearningChatMessage] = []
    /// Complete normalized provider input, including function calls and results, for safe continuation.
    public var toolHistoryJSON: Data?
    public init(id: String) { self.id = id }
}
public struct AIContentChange: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var deckID: String?
    public var noteID: String?
    public var beforeDeck: Deck?
    public var afterDeck: Deck?
    public var beforeNote: Note?
    public var afterNote: Note?
    public var beforeSettings: StudySettings?
    public var afterSettings: StudySettings?
    public var beforeCard: StudyCard?
    public var afterCard: StudyCard?
    public var beforeMemory: LearningMemory?
    public var afterMemory: LearningMemory?
    public var beforePreferences: [String:String]?
    public var afterPreferences: [String:String]?
    public var undoneAt: Date?
    public init(deckID: String? = nil, noteID: String? = nil) { self.deckID = deckID; self.noteID = noteID }
}
public struct AIActionRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var arguments: String
    public var status: String
    public var summary: String
    public var changes: [AIContentChange]
    public var createdAt: Date
    public init(id: String, name: String, arguments: String, status: String, summary: String, changes: [AIContentChange] = [], createdAt: Date = Date()) {
        self.id = id; self.name = name; self.arguments = arguments; self.status = status; self.summary = summary; self.changes = changes; self.createdAt = createdAt
    }
}
public struct AIActionRun: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var conversationID: String
    public var status = "running"
    public var actions: [AIActionRecord] = []
    public var createdAt = Date()
    public init(id: String, conversationID: String) { self.id = id; self.conversationID = conversationID }
}
public struct LearningMemory: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var noteID: String
    public var text: String
    public var evidenceIDs: [String]
    public var createdAt: Date
    public init(id: String = UUID().uuidString, noteID: String, text: String, evidenceIDs: [String] = [], createdAt: Date = Date()) {
        self.id = id; self.noteID = noteID; self.text = text; self.evidenceIDs = evidenceIDs; self.createdAt = createdAt
    }
}
public struct LearningAssistantState: Codable, Equatable, Sendable {
    public var preferences: [String:String]?
    public var conversations: [LearningConversation] = []
    public var runs: [AIActionRun] = []
    public var memory: [LearningMemory] = []
    public init() {}
}
