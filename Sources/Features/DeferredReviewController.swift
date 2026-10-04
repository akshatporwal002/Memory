import Foundation
import Observation
import LearningCore

@MainActor @Observable final class DeferredReviewController {
    var batchSize = 5 { didSet { persist() } }
    var revealAfterAnswer = true { didSet { persist() } }
    var summaryPresented = false
    var summaryIncludesViewed = false
    var notificationVisible = false
    private(set) var processing = false
    private(set) var submitting = false
    var error: String?
    private var account = ""
    private var dismissedSignature = ""
    private var forceFlush = false
    var foreground = true
    var referenceVisible = false
    private let defaults: UserDefaults = .standard

    func configure(_ model: EngramModel) {
        let next = model.testingScope ?? model.aiMarker.personal.accountID
        guard account != next else { return }
        account = ""
        batchSize = max(1, min(10, defaults.object(forKey: "engram.batchSize." + next) as? Int ?? 5))
        revealAfterAnswer = defaults.object(forKey: "engram.revealSubmitted." + next) as? Bool ?? true
        account = next; dismissedSignature = ""; notificationVisible = false; summaryPresented = false
    }
    private func persist() {
        guard !account.isEmpty else { return }
        defaults.set(max(1, min(10, batchSize)), forKey: "engram.batchSize." + account)
        defaults.set(revealAfterAnswer, forKey: "engram.revealSubmitted." + account)
    }
    func unseen(_ model: EngramModel) -> [AnswerAttempt] {
        (model.library.answerAttempts ?? []).filter { $0.deferredCard != nil && $0.summaryViewedAt == nil && ["finished", "attention", "failed"].contains($0.processingState ?? "") }
            .sorted { $0.createdAt < $1.createdAt }
    }
    var busy: Bool { submitting }
    func dismissNotification() { notificationVisible = false }
    func openSummary(_ model: EngramModel, includeViewed: Bool = false) {
        guard !(model.library.answerAttempts ?? []).contains(where: { $0.processingState == "queued" }), !processing else { return }
        notificationVisible = false; summaryIncludesViewed = includeViewed; summaryPresented = true
    }
    func requestFlush() { forceFlush = true }
    func submit(_ answer: String, model: EngramModel, modality: String = "typed") async -> AnswerAttempt? {
        guard !submitting, let session = model.library.session, let item = session.current, item.revealedAt == nil,
              let note = model.library.liveNotes.first(where: { $0.id == item.card.noteID }), note.mcq == nil else { return nil }
        submitting = true; error = nil; defer { submitting = false }
        do {
            let prompt = try CardRenderer.render(note: note, card: item.card, revealed: false).prompt
            let expected = try CardRenderer.render(note: note, card: item.card, revealed: true).answer ?? note.back
            let evidence = LocalAnswerEvidence.retrieve(note: note, prompt: prompt, library: model.library).map { AttemptEvidence(id: $0.id, text: $0.text, version: $0.version) }
            var attempt = AnswerAttempt(sessionID: session.id, item: item, noteID: note.id, answer: answer, prompt: prompt, expected: expected, modelID: model.aiMarker.selectedModel, evidence: evidence)
            attempt.providerAccountID = model.aiMarker.gradingIdentity(model.chatGPT); attempt.inputModality = modality
            try await model.service.enqueueAnswer(attempt); await model.refresh()
            await model.research.configure(model)
            var metric = ResearchEvent(kind: "answer_submitted", occurredAt: attempt.createdAt)
            metric.questionID = model.research.pseudonym(attempt.cardID); metric.attemptID = model.research.pseudonym(attempt.id)
            metric.questionType = note.canonicalQuestionType; metric.questionSchemaVersion = 1
            metric.subject = note.declaredSubject; metric.questionSubtype = note.declaredQuestionSubtype
            metric.inputModality = modality; metric.answerText = answer
            await model.research.record(metric, key: "answer:" + attempt.id)
            return attempt
        } catch { self.error = error.localizedDescription; return nil }
    }
    func processReady(_ model: EngramModel) async {
        configure(model)
        guard foreground, !Task.isCancelled, !processing, !submitting, !model.busy else { return }
        let waiting = (model.library.answerAttempts ?? []).filter { $0.processingState == "queued" }.sorted { $0.createdAt < $1.createdAt }
        if !waiting.isEmpty {
            guard forceFlush || !model.reviewPresented || model.library.session?.current == nil || waiting.count >= max(1, min(10, batchSize)) else { return }
            processing = true; defer { processing = false }
            let libraryID = model.activeLibraryID, identity = model.aiMarker.gradingIdentity(model.chatGPT)
            let first = waiting[0]
            let batch = Array(waiting.filter { $0.modelID == first.modelID && $0.providerAccountID == first.providerAccountID }.prefix(max(1, min(10, batchSize))))
            do {
                guard first.providerAccountID == identity else { throw EngramError.invalid("The grading account changed. Restore that connection or rate these answers manually.") }
                let started = Date()
                let results = try await model.aiMarker.assessBatch(batch, connection: model.chatGPT)
                try Task.checkCancellation()
                guard foreground, model.activeLibraryID == libraryID, identity == model.aiMarker.gradingIdentity(model.chatGPT) else { return }
                var metric = ResearchEvent(kind: "batch_completed")
                metric.durationMS = Date().timeIntervalSince(started) * 1000
                metric.queueMS = max(0, started.timeIntervalSince(first.createdAt) * 1000)
                metric.batchSize = batch.count; metric.model = first.modelID
                await model.research.record(metric, key: "ai-batch:" + batch.map(\.id).joined(separator: ":"))
                for attempt in batch {
                    do {
                        if let result = results[attempt.id] { try await persist { try await model.service.finishDeferredAnswer(id: attempt.id, assessment: result, providerAccountID: identity) } }
                        else { try await persist { try await model.service.finishDeferredAnswer(id: attempt.id, assessment: nil, providerAccountID: identity, failure: "This answer was missing or invalid in the marking response. Retry or rate manually.") } }
                    } catch {
                        try? await persist { try await model.service.finishDeferredAnswer(id: attempt.id, assessment: nil, providerAccountID: identity, failure: error.localizedDescription) }
                    }
                }
            } catch is CancellationError { return }
            catch {
                guard model.activeLibraryID == libraryID else { return }
                for attempt in batch {
                    try? await persist { try await model.service.finishDeferredAnswer(id: attempt.id, assessment: nil, providerAccountID: identity, failure: error.localizedDescription) }
                    var metric = ResearchEvent(kind: "ai_failed")
                    metric.questionID = model.research.pseudonym(attempt.cardID); metric.attemptID = model.research.pseudonym(attempt.id)
                    metric.questionType = attempt.questionType; metric.questionSchemaVersion = attempt.questionSchemaVersion; metric.model = attempt.modelID
                    metric.subject = attempt.subject; metric.questionSubtype = attempt.questionSubtype
                    await model.research.record(metric, key: metric.id.uuidString)
                }
            }
            await model.refresh()
            if !(model.library.answerAttempts ?? []).contains(where: { $0.processingState == "queued" }) { forceFlush = false }
        }
        let ready = unseen(model)
        guard !(model.library.answerAttempts ?? []).contains(where: { $0.processingState == "queued" }), !ready.isEmpty else { return }
        let signature = ready.map(\.id).joined(separator: ":")
        if signature != dismissedSignature { dismissedSignature = signature; notificationVisible = true }
    }
    /// Retry repository races using the result already returned by the provider.
    /// Never repeat an AI request merely because another local write won first.
    private func persist(_ operation: () async throws -> Void) async throws {
        for retry in 0..<4 {
            do { try await operation(); return }
            catch EngramError.conflict { if retry == 3 { throw EngramError.conflict } }
        }
    }
}
