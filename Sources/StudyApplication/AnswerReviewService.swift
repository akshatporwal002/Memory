import Foundation
import LearningCore

extension StudyService {
    /// Marks and schedules the first answer atomically, retaining the result until Next.
    public func submitAnswer(sessionID: String, presentationID: String, choiceID: String? = nil,
                             assessment supplied: AnswerAssessment? = nil, now: Date = Date()) async throws {
        var library = try await repository.read()
        let mutationID = "answer-" + presentationID
        if library.reviews.contains(where: { $0.id == mutationID && $0.sessionID == sessionID }) { return }
        guard var session = library.session, session.id == sessionID,
              var item = session.current, item.presentationID == presentationID, item.revealedAt == nil,
              let cardIndex = library.cards.firstIndex(where: { $0.id == item.card.id && !$0.retired && !$0.suspended }),
              library.cards[cardIndex].version == item.card.version,
              let note = library.liveNotes.first(where: { $0.id == item.card.noteID }) else { throw EngramError.conflict }
        let assessment: AnswerAssessment
        if let question = note.mcq {
            guard let choiceID, question.choices.contains(where: { $0.id == choiceID }) else { throw EngramError.invalid("Choose an answer before confirming.") }
            assessment = AnswerAssessment(outcome: choiceID == question.correctID ? .correct : .incorrect,
                reason: question.explanation, choiceID: choiceID, method: "mcq-local")
        } else {
            guard let supplied, supplied.method == "ai" || supplied.method == "local-exact",
                  supplied.reason.count <= 1500 else { throw EngramError.invalid("The assessment could not be validated.") }
            assessment = supplied
        }
        guard let rating = assessment.rating else { throw EngramError.invalid("Please clarify your answer; no grade was saved.") }
        let outcomes = try scheduler.outcomes(state: item.card.schedule,
            history: library.activeReviews.filter { $0.cardID == item.card.id }, now: now, settings: library.settings)
        guard let outcome = outcomes[rating] else { throw EngramError.invalid("The scheduler could not grade this answer.") }
        library.cards[cardIndex].schedule = outcome; library.cards[cardIndex].version += 1
        var event = ReviewEvent(id: mutationID, cardID: item.card.id, deckID: item.card.deckID, sessionID: sessionID,
            rating: rating, reviewedAt: now, committedAt: now, before: item.card.schedule, after: outcome)
        event.settingsSnapshot = library.settings
        event.assessment = assessment; library.reviews.append(event)
        item.revealedAt = now; item.outcomes = outcomes; item.assessment = assessment
        session.current = item; session.completed += 1; library.session = session
        try Task.checkCancellation()
        try await repository.commit(library, expectedRevision: library.revision)
    }

    public func nextAssessedAnswer(sessionID: String, presentationID: String, now: Date = Date()) async throws {
        var library = try await repository.read()
        guard var session = library.session, session.id == sessionID,
              session.current?.presentationID == presentationID,
              session.current?.assessment != nil else { throw EngramError.conflict }
        let queue = QueuePolicy.dueCards(in: library, deckID: session.deckID, now: now).filter { !(session.skippedCardIDs ?? []).contains($0.id) }
        session.queue = queue.map(\.id); session.current = queue.first.map(ReviewPresentation.init)
        library.session = session
        try await repository.commit(library, expectedRevision: library.revision)
    }
    public func skipAnswer(sessionID: String, presentationID: String, now: Date = Date()) async throws {
        var library = try await repository.read()
        guard var session = library.session, session.id == sessionID, let item = session.current, item.presentationID == presentationID else { throw EngramError.conflict }
        session.skippedCardIDs = (session.skippedCardIDs ?? []) + [item.card.id]
        let queue = QueuePolicy.dueCards(in: library, deckID: session.deckID, now: now).filter { !(session.skippedCardIDs ?? []).contains($0.id) }
        session.queue = queue.map(\.id); session.current = queue.first.map(ReviewPresentation.init); library.session = session
        try await repository.commit(library, expectedRevision: library.revision)
    }
}
