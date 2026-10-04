import Foundation
import LearningCore

extension StudyService {
    public func setMathInputMode(deckID: String, mode: MathInputMode) async throws {
        var library = try await repository.read()
        guard let index = library.decks.firstIndex(where: { $0.id == deckID && !$0.deleted }) else { throw EngramError.missing("notebook") }
        library.decks[index].mathInputMode = mode
        library.decks[index].modifiedAt = Date()
        try await repository.commit(library, expectedRevision: library.revision)
    }

    /// Persist first and advance in the same transaction. A pending answer never
    /// disappears with a view or competes with the next presentation.
    public func enqueueAnswer(_ supplied: AnswerAttempt) async throws {
        var library = try await repository.read()
        if library.answerAttempts?.contains(where: { $0.id == supplied.id }) == true { return }
        guard var session = library.session, let item = session.current,
              item.presentationID == supplied.presentationID, session.id == supplied.sessionID,
              item.revealedAt == nil, item.card.version == supplied.cardVersion,
              let note = library.liveNotes.first(where: { $0.id == supplied.noteID }),
              !supplied.assisted, !supplied.originalAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              supplied.originalAnswer.utf8.count <= 16_000, supplied.evidence.count <= 20,
              supplied.evidence.allSatisfy({ EvidenceRetrieval.isCurrent($0, in: library) }) else { throw EngramError.conflict }
        guard (library.answerAttempts ?? []).filter({ $0.deferredCard != nil && $0.committedAt == nil && $0.processingState != "cancelled" }).count < 10 else {
            throw EngramError.invalid("Ten answers need marking or manual review. Resolve them before submitting more.")
        }
        var attempt = supplied
        attempt.deferredCard = item.card; attempt.deferredNote = note
        var settings = library.settings
        settings.desiredRetention = library.liveDecks.first { $0.id == item.card.deckID }?.desiredRetention ?? settings.desiredRetention
        attempt.deferredSettings = settings; attempt.processingState = "queued"
        attempt.questionType = note.canonicalQuestionType; attempt.questionSchemaVersion = 1
        attempt.subject = note.declaredSubject; attempt.questionSubtype = note.declaredQuestionSubtype
        attempt.inputModality = supplied.inputModality ?? "typed"
        library.answerAttempts = (library.answerAttempts ?? []) + [attempt]
        session.skippedCardIDs = (session.skippedCardIDs ?? []) + [item.card.id]
        session.queue = QueuePolicy.dueCards(in: library, deckID: session.deckID, now: supplied.createdAt)
            .filter { !(session.skippedCardIDs ?? []).contains($0.id) }.map(\.id)
        session.current = session.queue.first.flatMap { id in library.liveCards.first { $0.id == id }.map(ReviewPresentation.init) }
        library.session = session
        try await repository.commit(library, expectedRevision: library.revision)
    }

    public func finishDeferredAnswer(id: String, assessment: AnswerAssessment?, providerAccountID: String?, manualGrade: Grade? = nil, failure: String? = nil, now: Date = Date()) async throws {
        var library = try await repository.read()
        guard var attempts = library.answerAttempts, let index = attempts.firstIndex(where: { $0.id == id }),
              let card = attempts[index].deferredCard, let settings = attempts[index].deferredSettings else { throw EngramError.missing("pending answer") }
        if attempts[index].committedAt != nil { return }
        if !attempts[index].revisions.isEmpty, library.reviews.contains(where: { $0.id == "answer-" + attempts[index].presentationID }), manualGrade != nil || assessment != nil {
            let manual = assessment ?? attempts[index].assessment ?? AnswerAssessment(outcome: .unclear, reason: "Manually reviewed", method: "manual")
            try await reviseDeferredAssessment(id: id, assessment: manual, providerAccountID: providerAccountID, manualGrade: manualGrade, now: now)
            return
        }
        guard attempts[index].processingState != "cancelled" else { throw EngramError.conflict }
        if let failure {
            attempts[index].processingState = "failed"; attempts[index].processingError = String(failure.prefix(500))
            library.answerAttempts = attempts; try await repository.commit(library, expectedRevision: library.revision); return
        }
        let attempt = attempts[index]
        guard manualGrade != nil || attempt.providerAccountID == providerAccountID else { throw EngramError.conflict }
        if let assessment {
            let ids = Set(attempt.evidence.map(\.id))
            guard assessment.method == "local-exact" || assessment.outcome == .unclear ||
                    (!(assessment.evidenceIDs ?? []).isEmpty && Set(assessment.evidenceIDs ?? []).isSubset(of: ids)) else { throw EngramError.invalid("Supporting evidence is missing.") }
            if assessment.method == "local-exact" {
                guard assessment.outcome == .correct, !attempt.expectedAnswer.isEmpty,
                      attempt.originalAnswer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == attempt.expectedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { throw EngramError.conflict }
            }
            attempts[index].assessment = assessment
            attempts[index].annotations = attempt.validatedAnnotations(assessment.annotations ?? [])
            attempts[index].additions = assessment.additions ?? []
        }
        guard let grade = manualGrade ?? assessment?.rating else {
            attempts[index].processingState = "attention"; library.answerAttempts = attempts
            try await repository.commit(library, expectedRevision: library.revision); return
        }
        guard !attempt.assisted || manualGrade != nil,
              let ci = library.cards.firstIndex(where: { $0.id == card.id && !$0.retired && !$0.suspended }),
              library.cards[ci].version == card.version, !library.isDeckSuspended(card.deckID),
              library.liveNotes.first(where: { $0.id == attempt.noteID }) == attempt.deferredNote,
              manualGrade != nil || (library.settings.version == settings.version && attempt.evidence.allSatisfy { EvidenceRetrieval.isCurrent($0, in: library) }) else { throw EngramError.conflict }
        let outcomes = try scheduler.outcomes(state: card.schedule, history: library.activeReviews.filter { $0.cardID == card.id }, now: attempt.createdAt, settings: settings)
        guard let outcome = outcomes[grade] else { throw EngramError.conflict }
        let reviewID = "answer-" + attempt.presentationID
        guard !library.reviews.contains(where: { $0.id == reviewID }) else { throw EngramError.conflict }
        var event = ReviewEvent(id: reviewID, cardID: card.id, deckID: card.deckID, sessionID: attempt.sessionID, rating: grade, reviewedAt: attempt.createdAt, committedAt: now, before: card.schedule, after: outcome)
        event.settingsSnapshot = settings; event.assessment = assessment
        event.gradingMethod = manualGrade == nil ? assessment?.method : "manual"
        event.questionType = attempt.questionType; event.questionSchemaVersion = attempt.questionSchemaVersion; event.inputModality = attempt.inputModality
        event.subject = attempt.subject; event.questionSubtype = attempt.questionSubtype
        library.reviews.append(event); library.cards[ci].schedule = outcome; library.cards[ci].version += 1
        attempts[index].committedAt = now; attempts[index].processingState = "finished"; attempts[index].processingError = nil
        library.answerAttempts = attempts
        if library.session?.id == attempt.sessionID { library.session?.completed += 1 }
        try await repository.commit(library, expectedRevision: library.revision)
    }

    public func retryDeferredAnswer(id: String, providerAccountID: String?) async throws {
        var library = try await repository.read()
        guard let index = library.answerAttempts?.firstIndex(where: { $0.id == id }),
              let attempt = library.answerAttempts?[index], attempt.processingState == "failed", attempt.committedAt == nil,
              attempt.providerAccountID == providerAccountID,
              library.liveNotes.first(where: { $0.id == attempt.noteID }) == attempt.deferredNote,
              attempt.evidence.allSatisfy({ EvidenceRetrieval.isCurrent($0, in: library) }) else { throw EngramError.conflict }
        library.answerAttempts?[index].processingState = "queued"
        library.answerAttempts?[index].processingError = nil
        try await repository.commit(library, expectedRevision: library.revision)
    }

    public func markFeedbackViewed(ids: Set<String>, now: Date = Date()) async throws {
        var library = try await repository.read()
        for i in (library.answerAttempts ?? []).indices where ids.contains(library.answerAttempts![i].id) {
            if library.answerAttempts![i].processingState == "finished" { library.answerAttempts![i].summaryViewedAt = now }
        }
        try await repository.commit(library, expectedRevision: library.revision)
    }

    /// Disputes append a correction and a replacement review, replaying later
    /// events. Learning the solution never changes the original response.
    public func reviseDeferredAssessment(id: String, assessment: AnswerAssessment, providerAccountID: String?, manualGrade: Grade? = nil, now: Date = Date()) async throws {
        var library = try await repository.read()
        guard var attempts = library.answerAttempts, let index = attempts.firstIndex(where: { $0.id == id }),
              let card = attempts[index].deferredCard, manualGrade != nil || attempts[index].providerAccountID == providerAccountID,
              let ci = library.cards.firstIndex(where: { $0.id == card.id && !$0.retired }),
              library.liveNotes.first(where: { $0.id == attempts[index].noteID }) == attempts[index].deferredNote,
              attempts[index].evidence.allSatisfy({ EvidenceRetrieval.isCurrent($0, in: library) }),
              manualGrade != nil || assessment.outcome == .unclear || (!(assessment.evidenceIDs ?? []).isEmpty && Set(assessment.evidenceIDs ?? []).isSubset(of: Set(attempts[index].evidence.map(\.id)))) else { throw EngramError.conflict }
        let attempt = attempts[index]
        if let previous = attempt.assessment { attempts[index].revisions.append(previous) }
        attempts[index].assessment = assessment; attempts[index].annotations = attempt.validatedAnnotations(assessment.annotations ?? [])
        attempts[index].additions = assessment.additions ?? []; attempts[index].summaryViewedAt = nil
        if attempt.committedAt != nil || library.reviews.contains(where: { $0.id == "answer-" + attempt.presentationID }) {
            let prior = library.activeReviews.last { $0.cardID == card.id && $0.sessionID == attempt.sessionID && $0.reviewedAt == attempt.createdAt }
            if let prior { library.corrections.append(ReviewCorrection(reviewID: prior.id, createdAt: now)) }
            if let grade = manualGrade ?? assessment.rating {
                let settings = attempt.deferredSettings ?? library.settings
                let earlier = library.activeReviews.filter { $0.cardID == card.id && $0.reviewedAt < attempt.createdAt }
                let before = try ReviewReconciliation.replay(card: card, events: earlier, settings: settings, scheduler: scheduler, baseline: library.reviews.first { $0.cardID == card.id }?.before ?? card.schedule)
                let outcomes = try scheduler.outcomes(state: before, history: earlier, now: attempt.createdAt, settings: settings)
                guard let after = outcomes[grade] else { throw EngramError.conflict }
                var event = ReviewEvent(id: "dispute-" + UUID().uuidString, cardID: card.id, deckID: card.deckID, sessionID: attempt.sessionID, rating: grade, reviewedAt: attempt.createdAt, committedAt: now, before: before, after: after)
                event.settingsSnapshot = settings; event.assessment = assessment; library.reviews.append(event)
                library.reviews[library.reviews.count - 1].gradingMethod = manualGrade == nil ? assessment.method : "manual"
                library.reviews[library.reviews.count - 1].questionType = attempt.questionType
                library.reviews[library.reviews.count - 1].subject = attempt.subject
                library.reviews[library.reviews.count - 1].questionSubtype = attempt.questionSubtype
                library.reviews[library.reviews.count - 1].questionSchemaVersion = attempt.questionSchemaVersion
                library.reviews[library.reviews.count - 1].inputModality = attempt.inputModality
            }
            library.cards[ci].schedule = try ReviewReconciliation.replay(card: card, allEvents: library.reviews, corrections: library.corrections, settings: library.settings, scheduler: scheduler)
            library.cards[ci].version += 1
        }
        let needsInitialCommit = attempt.committedAt == nil && !library.reviews.contains(where: { $0.id == "answer-" + attempt.presentationID }) && (manualGrade != nil || assessment.rating != nil)
        attempts[index].processingState = needsInitialCommit || (manualGrade == nil && assessment.rating == nil) ? "attention" : "finished"
        attempts[index].committedAt = attempts[index].processingState == "finished" ? now : nil
        library.answerAttempts = attempts
        try await repository.commit(library, expectedRevision: library.revision)
        if needsInitialCommit {
            // A dispute can resolve an ungraded answer too. Commit its original
            // scheduling event rather than merely labelling the attempt finished.
            try await finishDeferredAnswer(id: id, assessment: assessment, providerAccountID: providerAccountID, manualGrade: manualGrade, now: now)
        }
    }
}
