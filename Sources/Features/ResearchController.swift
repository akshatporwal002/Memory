import Foundation
import Observation
import CryptoKit
import LearningCore
import PersistenceAdapters

@MainActor @Observable final class ResearchController {
    private(set) var consent = ResearchConsent()
    private(set) var pendingCount = 0
    var error: String?
    private var owner: UUID?
    private var scope = ""
    private var activeQuestion: (id: String, card: String, type: String, subject: String?, subtype: String?)?
    private var activeSeconds = 0.0
    private var lastTick: Date?
    private let repository: ResearchEventRepository
    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        repository = ResearchEventRepository(directory: root.appendingPathComponent("Engram/Research", isDirectory: true))
    }
    func configure(_ model: EngramModel) async {
        let key = model.testingScope ?? model.cloud.userID?.uuidString.lowercased() ?? model.cloud.localProfileID ?? "local"
        guard scope != key else { return }
        scope = key; owner = nil; consent = ResearchConsent(); pendingCount = 0; error = nil
        activeQuestion = nil; activeSeconds = 0; lastTick = nil
        let idKey = "engram.research.owner." + key
        let id = (model.testingScope == nil ? model.cloud.userID : nil) ?? UserDefaults.standard.string(forKey: idKey).flatMap(UUID.init(uuidString:)) ?? UUID()
        UserDefaults.standard.set(id.uuidString, forKey: idKey)
        do {
            let state = try await repository.load(account: id)
            guard scope == key else { return }
            owner = id; consent = state.consent; pendingCount = state.events.count
        } catch { if scope == key { self.error = error.localizedDescription } }
    }
    func update(metrics: Bool? = nil, content: Bool? = nil) async {
        guard let owner else { return }
        var next = consent
        if let metrics { next.metrics = metrics; if !metrics { next.answerContent = false } }
        if let content { next.answerContent = content && next.metrics }
        next.revision += 1; next.updatedAt = Date()
        do { try await repository.setConsent(next, account: owner); consent = next; pendingCount = try await repository.load(account: owner).events.count }
        catch { self.error = error.localizedDescription }
    }
    func record(_ event: ResearchEvent, key: String) async {
        guard let owner, consent.metrics else { return }
        do { try await repository.append(event, deduplicationKey: key, account: owner); pendingCount = try await repository.load(account: owner).events.count }
        catch { self.error = "Research metrics could not be saved. Studying is unaffected." }
    }
    func pseudonym(_ value: String) -> String {
        let salt = owner?.uuidString ?? ""
        return SHA256.hash(data: Data((salt + ":" + value).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    /// Foreground question exposure sampled every two seconds. This measures
    /// visible time, not attention; revealed answers and other pages are excluded.
    func observeActivity(_ model: EngramModel, active: Bool) async {
        await configure(model)
        let now = Date()
        let current = active && model.reviewPresented && !model.deferredReview.referenceVisible ? model.library.session?.current : nil
        let next = current?.revealedAt == nil ? current : nil
        if let tick = lastTick, activeQuestion != nil, active { activeSeconds += min(2.5, max(0, now.timeIntervalSince(tick))) }
        if activeQuestion?.id != next?.presentationID || !active {
            if let previous = activeQuestion, activeSeconds > 0 {
                var event = ResearchEvent(kind: "question_activity", occurredAt: now)
                event.questionID = pseudonym(previous.card); event.attemptID = pseudonym(previous.id)
                event.questionType = previous.type; event.questionSchemaVersion = 1
                event.subject = previous.subject; event.questionSubtype = previous.subtype
                event.durationMS = activeSeconds * 1000
                await record(event, key: event.id.uuidString)
            }
            activeQuestion = next.flatMap { item in
                model.library.liveNotes.first { $0.id == item.card.noteID }.map { (item.presentationID, item.card.id, $0.canonicalQuestionType, $0.declaredSubject, $0.declaredQuestionSubtype) }
            }
            activeSeconds = 0
        }
        lastTick = active ? now : nil
    }
    func observeReviews(_ model: EngramModel) async {
        await configure(model)
        guard consent.metrics else { return }
        let identity = scope
        for correction in model.library.corrections where correction.createdAt >= consent.updatedAt {
            var event = ResearchEvent(kind: "review_corrected", occurredAt: correction.createdAt)
            event.correctedReviewID = pseudonym(correction.reviewID)
            await record(event, key: "correction:" + correction.id)
        }
        for review in model.library.activeReviews where review.committedAt >= consent.updatedAt {
            guard identity == scope else { return }
            let attempt = model.library.answerAttempts?.last { $0.cardID == review.cardID && $0.sessionID == review.sessionID && $0.createdAt == review.reviewedAt }
            var event = ResearchEvent(kind: "review", occurredAt: review.committedAt)
            event.answeredAt = review.reviewedAt; event.reviewID = pseudonym(review.id)
            event.questionID = pseudonym(review.cardID); event.attemptID = attempt.map { pseudonym($0.id) }
            event.questionType = review.questionType ?? attempt?.questionType ?? "unknown"
            event.subject = review.subject ?? attempt?.subject
            event.questionSubtype = review.questionSubtype ?? attempt?.questionSubtype
            event.questionSchemaVersion = review.questionSchemaVersion ?? attempt?.questionSchemaVersion
            event.inputModality = review.inputModality ?? attempt?.inputModality ?? (review.assessment?.method == "mcq-local" ? "choice" : "manual")
            event.gradingMethod = review.gradingMethod ?? review.assessment?.method ?? "manual"
            event.rating = review.rating.rawValue; event.outcome = review.assessment?.outcome.rawValue
            event.estimatedRecall = await model.service.estimatedRecallBefore(review, settings: model.library.settings)
            if let attempt, attempt.createdAt >= consent.updatedAt { event.answerText = attempt.originalAnswer }
            await record(event, key: "review:" + review.id)
        }
    }
    func deleteLocal() async {
        guard let owner else { return }
        do {
            var next = consent; next.metrics = false; next.answerContent = false; next.revision += 1; next.updatedAt = Date()
            try await repository.setConsent(next, account: owner); consent = next; pendingCount = 0
        }
        catch { self.error = error.localizedDescription }
    }
    func upload(_ model: EngramModel) async {
        guard model.testingScope == nil, let owner, model.cloud.userID == owner,
              Bundle.main.object(forInfoDictionaryKey: "EngramResearchUploadEnabled") as? Bool == true else { return }
        let identity = scope
        do {
            let state = try await repository.load(account: owner)
            let events = Array(state.events.prefix(100))
            try await model.cloud.uploadResearch(consent: state.consent, events: events)
            guard identity == scope else { return }
            try await repository.acknowledge(Set(events.map(\.id)), account: owner)
            pendingCount = try await repository.load(account: owner).events.count
        } catch { self.error = "Research upload is pending; study remains available." }
    }
}
