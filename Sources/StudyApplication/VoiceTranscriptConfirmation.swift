import Foundation
import LearningCore

extension StudyService {
    /// Confirmation journals recognition edits before any grade is dispatched.
    public func confirmVoiceTranscript(id: String, deviceID: String, ownerID: String, text: String, now: Date = Date()) async throws -> AnswerAttempt {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 16_000 else { throw EngramError.invalid("Confirm an answer under 16 KB.") }
        var library = try await repository.read()
        guard var jobs = library.voiceJobs, let index = jobs.firstIndex(where: { $0.id == id && $0.deviceID == deviceID && $0.ownerID == ownerID }),
              jobs[index].state == .awaitingConfirmation, jobs[index].confirmedAt == nil,
              library.liveNotes.first(where: { $0.id == jobs[index].note.id }) == jobs[index].note,
              library.liveCards.contains(where: { $0.id == jobs[index].card.id && $0.version == jobs[index].card.version && !$0.suspended }),
              !library.isDeckSuspended(jobs[index].card.deckID),
              jobs[index].attempt.evidence.allSatisfy({ EvidenceRetrieval.isCurrent($0, in: library) }),
              var session = library.session, session.id == jobs[index].attempt.sessionID,
              session.current?.presentationID == jobs[index].attempt.presentationID else { throw EngramError.conflict }
        if text != jobs[index].attempt.originalAnswer {
            jobs[index].transcriptRevisions = (jobs[index].transcriptRevisions ?? []) + [jobs[index].attempt.originalAnswer]
            jobs[index].attempt.originalAnswer = text
        }
        jobs[index].confirmedAt = now; jobs[index].generation += 1
        var attempt = jobs[index].attempt
        attempt.inputModality = "voice"; attempt.questionType = jobs[index].note.canonicalQuestionType; attempt.questionSchemaVersion = 1
        attempt.subject = jobs[index].note.declaredSubject; attempt.questionSubtype = jobs[index].note.declaredQuestionSubtype
        if jobs[index].note.mcq == nil {
            guard (library.answerAttempts ?? []).filter({ $0.deferredCard != nil && $0.committedAt == nil && $0.processingState != "cancelled" }).count < 10 else { throw EngramError.invalid("Finish pending feedback before submitting more answers.") }
            attempt.deferredCard = jobs[index].card; attempt.deferredNote = jobs[index].note; attempt.deferredSettings = jobs[index].settings
            attempt.processingState = "queued"
            library.answerAttempts = (library.answerAttempts ?? []) + [attempt]
            jobs[index].movedToDeferred = true; jobs[index].state = .cancelled
        } else { jobs[index].state = .awaitingMarking; jobs[index].attempt = attempt }
        library.voiceJobs = jobs
        session.skippedCardIDs = (session.skippedCardIDs ?? []) + [attempt.cardID]
        session.queue = QueuePolicy.dueCards(in: library, deckID: session.deckID, now: now).filter { !(session.skippedCardIDs ?? []).contains($0.id) }.map(\.id)
        session.current = session.queue.first.flatMap { id in library.liveCards.first { $0.id == id }.map(ReviewPresentation.init) }
        library.session = session
        try await repository.commit(library, expectedRevision: library.revision)
        return attempt
    }
}
