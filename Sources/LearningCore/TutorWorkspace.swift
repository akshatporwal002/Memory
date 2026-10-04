import Foundation

/// Only these projections cross the learner/tutor boundary. Raw attempts never belong here.
public struct TutorProgressSummary: Codable, Equatable, Sendable {
    public var reviewedQuestionIDs: Set<UUID>
    public var correctCount: Int
    public var lastActivity: Date?
    public var sharedMisconceptions: [String]
    public init(reviewedQuestionIDs: Set<UUID> = [], correctCount: Int = 0,
                lastActivity: Date? = nil, sharedMisconceptions: [String] = []) {
        self.reviewedQuestionIDs = reviewedQuestionIDs; self.correctCount = correctCount
        self.lastActivity = lastActivity; self.sharedMisconceptions = sharedMisconceptions
    }
}

public enum TutorSharingConsent: String, Codable, Sendable {
    case pending, granted, guardianRequired, revoked
}

public struct TutorStudentMembership: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let studentID: UUID
    public var consent: TutorSharingConsent
    public var displayName: String?
    public init(id: UUID = UUID(), studentID: UUID, consent: TutorSharingConsent = .pending) {
        self.id = id; self.studentID = studentID; self.consent = consent
    }
}

public struct TutorAssignment: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let studentID: UUID
    public let revision: Int
    public let title: String
    public let questionIDs: Set<UUID>
    public let dueAt: Date?
    public var withdrawn: Bool
    public var subject: String?
    public var sourceDeckID: String?
    public init(id: UUID = UUID(), studentID: UUID, revision: Int = 1, title: String,
                questionIDs: Set<UUID>, dueAt: Date? = nil, withdrawn: Bool = false) {
        self.id = id; self.studentID = studentID; self.revision = revision
        self.title = title; self.questionIDs = questionIDs; self.dueAt = dueAt; self.withdrawn = withdrawn
    }
}

public struct TutorWorkspace: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let ownerID: UUID
    public var title: String
    public var version: Int
    public var memberships: [TutorStudentMembership]
    public var assignments: [TutorAssignment]
    public var progress: [UUID: TutorProgressSummary]
    public var drafts: [TutorDeckDraft]?
    public init(id: UUID = UUID(), ownerID: UUID, title: String) {
        self.id = id; self.ownerID = ownerID; self.title = title; version = 1
        memberships = []; assignments = []; progress = [:]
    }
}

public struct TutorDeckDraft: Codable, Equatable, Identifiable, Sendable {
    public var id: String { sourceDeckID }
    public let sourceDeckID: String
    public var title: String
    public var subject: String
    public init(sourceDeckID: String, title: String, subject: String) {
        self.sourceDeckID = sourceDeckID; self.title = title; self.subject = subject
    }
}
