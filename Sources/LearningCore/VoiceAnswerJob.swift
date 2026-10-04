import Foundation

public enum VoiceAnswerState: String, Codable, Sendable {
    case captured, transcribing, awaitingConfirmation, awaitingMarking, marking, completed, needsAttention, cancelled
    public var unresolved: Bool { self != .completed && self != .cancelled }
}
public enum VoiceReviewMode: String, Codable, Sendable { case continueProcessing, waitForFeedback }
public enum VoiceBillingPath: String, Codable, Sendable { case local, personalKey, managedCredits }

/// Device-local work metadata. No audio, keys or filesystem paths enter this value.
/// Cloud projection deliberately does not export jobs; accepted attempts/reviews sync normally.
public struct VoiceAnswerJob: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "voice-" + attempt.presentationID }
    public let deviceID: String
    public let ownerID: String
    public let recordingID: UUID
    public let provider: String
    public let transcriptionModel: String
    public let billingPath: VoiceBillingPath
    public let mode: VoiceReviewMode
    public let note: Note
    public let card: StudyCard
    public let settings: StudySettings
    public var attempt: AnswerAttempt
    public var state: VoiceAnswerState = .captured
    public var generation = 0
    public var error: String?
    public var usageJSON: Data?
    public var transcriptRevisions: [String]?
    /// Device-private ownership for cleanup after the grading connection changes.
    /// Optional for backups written before account-scoped capture was connected.
    public var appAccountID: String?
    public var recordingCleanupPending: Bool?
    /// Optional for pre-correction jobs/backups. Content remains frozen; this
    /// version authorizes only the reconciled scheduling projection.
    public var reconciliationCardVersion: Int?
    public var reviewRevision: Int?
    public var requiresConfirmation: Bool?
    public var confirmedAt: Date?
    public var movedToDeferred: Bool?
    public var reviewID: String {
        let base = "answer-" + attempt.presentationID
        return (reviewRevision ?? 0) == 0 ? base : base + "-voice-revision-" + String(reviewRevision ?? 0)
    }
    public func belongsToAppAccount(_ account: String, deviceID requestedDevice: String, currentGradingIdentity: String) -> Bool {
        guard !account.isEmpty, deviceID == requestedDevice else { return false }
        if let appAccountID { return appAccountID == account }
        if ownerID == currentGradingIdentity { return true }
        let pieces = ownerID.split(separator: ":", omittingEmptySubsequences: false)
        guard pieces.count >= 3, pieces[0] == account, let revision = Int(pieces[1]), revision >= 0 else { return false }
        return true
    }
    public init(deviceID: String, ownerID: String, recordingID: UUID, provider: String, transcriptionModel: String,
                billingPath: VoiceBillingPath, mode: VoiceReviewMode, note: Note, card: StudyCard,
                settings: StudySettings, attempt: AnswerAttempt) {
        self.deviceID = deviceID; self.ownerID = ownerID; self.recordingID = recordingID
        self.provider = provider; self.transcriptionModel = transcriptionModel; self.billingPath = billingPath
        self.mode = mode; self.note = note; self.card = card; self.settings = settings; self.attempt = attempt
    }
    public func validate() throws {
        guard !deviceID.isEmpty, !ownerID.isEmpty, deviceID.utf8.count <= 200, ownerID.utf8.count <= 500,
              !provider.isEmpty, provider.utf8.count <= 100, transcriptionModel.utf8.count <= 200,
              appAccountID.map({ !$0.isEmpty && $0.utf8.count <= 200 }) ?? true,
              generation >= 0, (reviewRevision ?? 0) >= 0, (reviewRevision ?? 0) <= 100,
              reconciliationCardVersion.map({ $0 >= card.version }) ?? true,
              attempt.noteID == note.id, attempt.cardID == card.id, card.noteID == note.id, card.deckID == note.deckID,
              attempt.modelID.utf8.count <= 300,
              attempt.cardVersion == card.version, attempt.originalAnswer.utf8.count <= 16_000,
              attempt.evidence.count <= 20, attempt.createdAt.timeIntervalSince1970.isFinite,
              (error?.utf8.count ?? 0) <= 2000, (usageJSON?.count ?? 0) <= 32_000,
              (transcriptRevisions?.count ?? 0) <= 100, transcriptRevisions?.allSatisfy({ $0.utf8.count <= 16_000 }) ?? true,
              recordingCleanupPending != true || state == .cancelled || !attempt.originalAnswer.isEmpty,
              state != .completed || attempt.committedAt != nil else { throw EngramError.invalid("Invalid pending voice answer.") }
    }
}
