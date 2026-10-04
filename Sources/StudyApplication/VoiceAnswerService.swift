import Foundation
import LearningCore

public enum VoiceWorkerStage: Equatable, Sendable { case transcription, marking }
extension StudyService {
    /// Caller saves protected audio first. This transaction journals the answer and
    /// advances Continue mode together; losing the visible card cannot lose its work.
    @discardableResult public func captureVoiceAnswer(recordingID: UUID, deviceID: String, ownerID: String,
        provider: String, transcriptionModel: String, gradingModel: String, billingPath: VoiceBillingPath,
        mode: VoiceReviewMode, sessionID: String, presentationID: String, evidence: [AttemptEvidence],
        localTranscript: String? = nil, now: Date = Date()) async throws -> VoiceAnswerJob {
        if let localTranscript {
            guard provider == "local", billingPath == .local, !localTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  localTranscript.utf8.count <= 16_000 else { throw EngramError.invalid("Check the on-device transcript before submitting.") }
        }
        var library = try await repository.read()
        if let existing = library.voiceJobs?.first(where: { $0.id == "voice-" + presentationID }) {
            guard existing.deviceID == deviceID, existing.ownerID == ownerID, existing.recordingID == recordingID else { throw EngramError.conflict }
            return existing
        }
        guard var session = library.session, session.id == sessionID, let item = session.current,
              item.presentationID == presentationID, item.revealedAt == nil,
              let note = library.liveNotes.first(where: { $0.id == item.card.noteID }),
              library.liveCards.contains(where: { $0.id == item.card.id && $0.version == item.card.version && !$0.suspended }),
              !library.isDeckSuspended(item.card.deckID),
              !(library.answerAttempts?.contains(where: { $0.presentationID == presentationID }) ?? false),
              evidence.count <= 20, evidence.allSatisfy({ EvidenceRetrieval.isCurrent($0, in: library) }) else { throw EngramError.conflict }
        guard (library.voiceJobs ?? []).filter({ $0.state.unresolved }).count < 10 else { throw EngramError.invalid("Review pending answers before submitting more. Ten answers are still unresolved.") }
        let prompt = try CardRenderer.render(note: note, card: item.card, revealed: false)
        let answer = try CardRenderer.render(note: note, card: item.card, revealed: true)
        var attempt = AnswerAttempt(sessionID: session.id, item: item, noteID: note.id, answer: "", prompt: prompt.prompt,
            expected: answer.answer ?? note.back, modelID: gradingModel, evidence: evidence, now: now)
        attempt.providerAccountID = ownerID
        var settings = library.settings
        if let retention = library.liveDecks.first(where: { $0.id == item.card.deckID })?.desiredRetention { settings.desiredRetention = retention }
        var job = VoiceAnswerJob(deviceID: deviceID, ownerID: ownerID, recordingID: recordingID, provider: provider,
            transcriptionModel: transcriptionModel, billingPath: billingPath, mode: mode, note: note,
            card: item.card, settings: settings, attempt: attempt)
        if let localTranscript { job.attempt.originalAnswer = localTranscript; job.state = .awaitingMarking }
        try job.validate()
        library.voiceJobs = (library.voiceJobs ?? []) + [job]
        if mode == .continueProcessing {
            session.queue = QueuePolicy.dueCards(in: library, deckID: session.deckID, now: now)
                .filter { !(session.skippedCardIDs ?? []).contains($0.id) }.map(\.id)
            session.current = session.queue.first.flatMap { id in library.liveCards.first { $0.id == id }.map(ReviewPresentation.init) }
            library.session = session
        }
        try Task.checkCancellation(); try await repository.commit(library, expectedRevision: library.revision)
        return job
    }

    /// Durable worker claims enforce capacity before dispatch. Generation is the
    /// lease: old responses cannot mutate corrected, retried or cancelled jobs.
    public func claimVoiceAnswer(stage: VoiceWorkerStage, deviceID: String, ownerID: String) async throws -> VoiceAnswerJob? {
        var library = try await repository.read()
        var jobs = library.voiceJobs ?? []
        let from: VoiceAnswerState = stage == .transcription ? .captured : .awaitingMarking
        let active: VoiceAnswerState = stage == .transcription ? .transcribing : .marking
        let limit = stage == .transcription ? 2 : 1
        guard jobs.filter({ $0.deviceID == deviceID && $0.ownerID == ownerID && $0.state == active }).count < limit,
              let index = jobs.indices.filter({ jobs[$0].deviceID == deviceID && jobs[$0].ownerID == ownerID && jobs[$0].state == from })
                .min(by: { jobs[$0].attempt.createdAt < jobs[$1].attempt.createdAt }) else { return nil }
        jobs[index].generation += 1; jobs[index].state = active; jobs[index].error = nil
        library.voiceJobs = jobs
        try Task.checkCancellation(); try await repository.commit(library, expectedRevision: library.revision)
        return jobs[index]
    }
    public func storeVoiceTranscript(id: String, generation: Int, deviceID: String, ownerID: String,
        text: String, usageJSON: Data? = nil) async throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 16_000,
              (usageJSON?.count ?? 0) <= 32_000 else { throw EngramError.invalid("Check the transcript before marking this answer.") }
        var library = try await repository.read()
        var jobs = library.voiceJobs ?? []
        let index = try voiceIndex(jobs, id: id, generation: generation, deviceID: deviceID, ownerID: ownerID)
        guard jobs[index].state == .transcribing else { throw EngramError.conflict }
        jobs[index].attempt.originalAnswer = text; jobs[index].usageJSON = usageJSON
        jobs[index].state = .awaitingMarking; jobs[index].generation += 1
        library.voiceJobs = jobs
        try Task.checkCancellation(); try await repository.commit(library, expectedRevision: library.revision)
    }
    public func failVoiceAnswer(id: String, generation: Int, deviceID: String, ownerID: String, reason: String) async throws {
        var library = try await repository.read(); var jobs = library.voiceJobs ?? []
        let index = try voiceIndex(jobs, id: id, generation: generation, deviceID: deviceID, ownerID: ownerID)
        guard jobs[index].state.unresolved else { throw EngramError.conflict }
        jobs[index].state = .needsAttention; jobs[index].error = String(decoding: reason.utf8.prefix(1900), as: UTF8.self); jobs[index].generation += 1
        library.voiceJobs = jobs; try await repository.commit(library, expectedRevision: library.revision)
    }
    public func cancelVoiceAnswer(id: String, deviceID: String, ownerID: String) async throws {
        var library = try await repository.read(); var jobs = library.voiceJobs ?? []
        guard let index = jobs.firstIndex(where: { $0.id == id && $0.deviceID == deviceID && $0.ownerID == ownerID }),
              jobs[index].state.unresolved else { throw EngramError.conflict }
        jobs[index].state = .cancelled; jobs[index].generation += 1
        library.voiceJobs = jobs; try await repository.commit(library, expectedRevision: library.revision)
    }
    public func retryVoiceAnswer(id: String, deviceID: String, ownerID: String) async throws {
        var library = try await repository.read(); var jobs = library.voiceJobs ?? []
        guard let index = jobs.firstIndex(where: { $0.id == id && $0.deviceID == deviceID && $0.ownerID == ownerID }),
              jobs[index].state == .needsAttention else { throw EngramError.conflict }
        jobs[index].state = jobs[index].attempt.originalAnswer.isEmpty ? .captured : .awaitingMarking
        jobs[index].generation += 1; jobs[index].error = nil
        library.voiceJobs = jobs; try await repository.commit(library, expectedRevision: library.revision)
    }
    /// Correcting pending recognition supersedes the marking lease. Completed
    /// attempts require review reconciliation rather than another scheduling event.
    public func correctPendingVoiceTranscript(id: String, deviceID: String, ownerID: String, text: String) async throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 16_000 else { throw EngramError.invalid("Enter a transcript under 16 KB.") }
        var library = try await repository.read(); var jobs = library.voiceJobs ?? []
        guard let index = jobs.firstIndex(where: { $0.id == id && $0.deviceID == deviceID && $0.ownerID == ownerID }),
              jobs[index].state.unresolved, jobs[index].attempt.committedAt == nil,
              (jobs[index].transcriptRevisions?.count ?? 0) < 100 else { throw EngramError.conflict }
        jobs[index].transcriptRevisions = (jobs[index].transcriptRevisions ?? []) + [jobs[index].attempt.originalAnswer]
        if let assessment = jobs[index].attempt.assessment { jobs[index].attempt.revisions.append(assessment) }
        jobs[index].attempt.originalAnswer = text; jobs[index].attempt.assessment = nil
        jobs[index].attempt.annotations = []; jobs[index].attempt.additions = []
        jobs[index].state = .awaitingMarking; jobs[index].generation += 1; jobs[index].error = nil
        library.voiceJobs = jobs; try await repository.commit(library, expectedRevision: library.revision)
    }
    public func advanceCompletedVoiceAnswer(id: String, deviceID: String, ownerID: String, now: Date = Date()) async throws {
        var library = try await repository.read()
        guard let job = library.voiceJobs?.first(where: { $0.id == id && $0.deviceID == deviceID && $0.ownerID == ownerID && $0.state == .completed }),
              var session = library.session, session.id == job.attempt.sessionID,
              session.current?.presentationID == job.attempt.presentationID else { throw EngramError.conflict }
        let queue = QueuePolicy.dueCards(in: library, deckID: session.deckID, now: now)
            .filter { !(session.skippedCardIDs ?? []).contains($0.id) }
        session.queue = queue.map(\.id); session.current = queue.first.map(ReviewPresentation.init)
        library.session = session; try await repository.commit(library, expectedRevision: library.revision)
    }
    /// Restart never silently resends a potentially billed audio upload. Marking
    /// can resume from a durable transcript without retranscribing/recharging.
    public func recoverVoiceAnswers(deviceID: String, ownerID: String) async throws {
        var library = try await repository.read(); var jobs = library.voiceJobs ?? []; var changed = false
        for index in jobs.indices where jobs[index].deviceID == deviceID && jobs[index].ownerID == ownerID {
            if jobs[index].state == .transcribing {
                jobs[index].state = .needsAttention
                jobs[index].error = "Transcription interrupted. Check provider usage before retrying this recording."
            } else if jobs[index].state == .marking { jobs[index].state = .awaitingMarking }
            else { continue }
            jobs[index].generation += 1; changed = true
        }
        guard changed else { return }; library.voiceJobs = jobs
        try await repository.commit(library, expectedRevision: library.revision)
    }
    /// Schedule independently of the visible presentation, once at submission time.
    public func commitVoiceAnswer(id: String, generation: Int, deviceID: String, ownerID: String,
        assessment supplied: AnswerAssessment? = nil, choiceID: String? = nil, now: Date = Date()) async throws {
        var library = try await repository.read(); var jobs = library.voiceJobs ?? []
        guard let index = jobs.firstIndex(where: { $0.id == id && $0.deviceID == deviceID && $0.ownerID == ownerID }) else { throw EngramError.conflict }
        if jobs[index].state == .completed { return }
        let job = jobs[index]
        guard job.generation == generation, job.state == .marking, !job.attempt.assisted,
              let cardIndex = library.cards.firstIndex(where: { $0.id == job.card.id && !$0.retired && !$0.suspended }),
              library.cards[cardIndex].version == job.card.version, !library.isDeckSuspended(job.card.deckID),
              library.liveNotes.first(where: { $0.id == job.note.id }) == job.note,
              library.settings.version == job.settings.version,
              job.attempt.evidence.allSatisfy({ EvidenceRetrieval.isCurrent($0, in: library) }) else { throw EngramError.conflict }
        let assessment: AnswerAssessment
        if let mcq = job.note.mcq {
            guard let choiceID, mcq.choices.contains(where: { $0.id == choiceID }) else { throw EngramError.invalid("Check which option was spoken. No grade was saved.") }
            assessment = AnswerAssessment(outcome: choiceID == mcq.correctID ? .correct : .incorrect, reason: mcq.explanation, choiceID: choiceID, method: "mcq-local")
        } else {
            guard let supplied, ["ai", "local-exact"].contains(supplied.method), supplied.reason.count <= 1500 else { throw EngramError.invalid("The voice assessment could not be validated.") }
            if supplied.method == "local-exact" {
                let clean: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                guard supplied.outcome == .correct, !clean(job.attempt.expectedAnswer).isEmpty,
                      clean(job.attempt.originalAnswer) == clean(job.attempt.expectedAnswer) else { throw EngramError.conflict }
            } else {
                let allowed = Set(job.attempt.evidence.map(\.id))
                let cited = supplied.evidenceIDs ?? []
                guard supplied.outcome == .unclear || (!cited.isEmpty && Set(cited).isSubset(of: allowed)) else { throw EngramError.invalid("The grade needs supporting evidence.") }
            }
            assessment = supplied
        }
        jobs[index].attempt.assessment = assessment
        jobs[index].attempt.annotations = jobs[index].attempt.validatedAnnotations(assessment.annotations ?? [])
        jobs[index].attempt.additions = assessment.additions ?? []
        guard let rating = assessment.rating else {
            jobs[index].state = .needsAttention; jobs[index].error = String(decoding: assessment.reason.utf8.prefix(1900), as: UTF8.self); jobs[index].generation += 1
            library.voiceJobs = jobs; try await repository.commit(library, expectedRevision: library.revision); return
        }
        let outcomes = try scheduler.outcomes(state: job.card.schedule, history: library.activeReviews.filter { $0.cardID == job.card.id }, now: job.attempt.createdAt, settings: job.settings)
        guard let outcome = outcomes[rating], now >= job.attempt.createdAt else { throw EngramError.conflict }
        let reviewID = "answer-" + job.attempt.presentationID
        guard !library.reviews.contains(where: { $0.id == reviewID }) else { throw EngramError.conflict }
        library.cards[cardIndex].schedule = outcome; library.cards[cardIndex].version += 1
        var review = ReviewEvent(id: reviewID, cardID: job.card.id, deckID: job.card.deckID, sessionID: job.attempt.sessionID,
            rating: rating, reviewedAt: job.attempt.createdAt, committedAt: now, before: job.card.schedule, after: outcome)
        review.settingsSnapshot = job.settings; review.assessment = assessment; library.reviews.append(review)
        jobs[index].attempt.committedAt = now; jobs[index].state = .completed; jobs[index].generation += 1
        library.voiceJobs = jobs
        var attempts = library.answerAttempts ?? []; attempts.removeAll { $0.id == job.attempt.id }; attempts.append(jobs[index].attempt); library.answerAttempts = attempts
        if var session = library.session, session.id == job.attempt.sessionID {
            session.completed += 1
            if var current = session.current, current.presentationID == job.attempt.presentationID {
                current.assessment = assessment; current.revealedAt = now; current.outcomes = outcomes; session.current = current
            }
            library.session = session
        }
        try Task.checkCancellation(); try await repository.commit(library, expectedRevision: library.revision)
    }
    private func voiceIndex(_ jobs: [VoiceAnswerJob], id: String, generation: Int, deviceID: String, ownerID: String) throws -> Int {
        guard let index = jobs.firstIndex(where: { $0.id == id && $0.generation == generation && $0.deviceID == deviceID && $0.ownerID == ownerID }) else { throw EngramError.conflict }
        return index
    }
}
