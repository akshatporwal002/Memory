import Foundation
import LearningCore

extension StudyService {
    public func saveAnswerAttempt(_ attempt: AnswerAttempt) async throws {
        var library = try await repository.read()
        guard attempt.originalAnswer.utf8.count <= 16_000,attempt.evidence.count <= 20,
              library.session?.id == attempt.sessionID,library.session?.current?.presentationID == attempt.presentationID,
              library.session?.current?.card.version == attempt.cardVersion,
              library.liveCards.contains(where: { $0.id == attempt.cardID && $0.version == attempt.cardVersion }),
              attempt.evidence.allSatisfy({ EvidenceRetrieval.isCurrent($0,in:library) }) else { throw EngramError.conflict }
        var attempts = library.answerAttempts ?? []
        if let index = attempts.firstIndex(where: { $0.id == attempt.id }) {
            let prior = attempts[index]
            guard prior.committedAt == nil,prior.originalAnswer == attempt.originalAnswer,prior.prompt == attempt.prompt,
                  prior.cardVersion == attempt.cardVersion,prior.assisted == attempt.assisted else { throw EngramError.conflict }
            attempts[index] = attempt
        } else { attempts.append(attempt) }
        library.answerAttempts = attempts
        try await repository.commit(library,expectedRevision:library.revision)
    }
    public func markAttemptAssisted(presentationID: String) async throws {
        var library = try await repository.read()
        guard let session = library.session,let item = session.current,item.presentationID == presentationID else { throw EngramError.conflict }
        var attempts = library.answerAttempts ?? []
        if let index = attempts.firstIndex(where: { $0.presentationID == presentationID }) { attempts[index].assisted = true }
        else {
            guard let note = library.liveNotes.first(where: { $0.id == item.card.noteID }) else { throw EngramError.missing("note") }
            let rendered = try CardRenderer.render(note:note,card:item.card,revealed:false)
            var attempt = AnswerAttempt(sessionID:session.id,item:item,noteID:note.id,answer:"",prompt:rendered.prompt,expected:"",modelID:"",evidence:[])
            attempt.assisted = true; attempts.append(attempt)
        }
        library.answerAttempts = attempts; try await repository.commit(library,expectedRevision:library.revision)
    }
    public func commitAnswerAttempt(id: String,manualGrade: Grade? = nil,providerAccountID: String? = nil,now: Date = Date()) async throws {
        var library = try await repository.read()
        guard var attempts = library.answerAttempts,let index = attempts.firstIndex(where: { $0.id == id }) else { throw EngramError.missing("answer attempt") }
        if attempts[index].committedAt != nil { return }
        let attempt = attempts[index]
        if manualGrade == nil,let account = attempt.providerAccountID { guard account == providerAccountID else { throw EngramError.conflict } }
        guard var session = library.session,session.id == attempt.sessionID,var item = session.current,
              item.presentationID == attempt.presentationID,
              let ci = library.cards.firstIndex(where: { $0.id == attempt.cardID && !$0.retired && !$0.suspended }),
              library.cards[ci].version == attempt.cardVersion else { throw EngramError.conflict }
        guard !attempt.assisted || manualGrade != nil else { throw EngramError.invalid("This answer was assisted. Choose a manual grade.") }
        guard manualGrade != nil || attempt.evidence.allSatisfy({ EvidenceRetrieval.isCurrent($0,in:library) }) else { throw EngramError.conflict }
        guard let grade = manualGrade ?? attempt.assessment?.rating else { throw EngramError.invalid("Unclear feedback cannot save an automatic grade. Choose a manual rating or discuss the feedback.") }
        let outcomes = try scheduler.outcomes(state:item.card.schedule,history:library.activeReviews.filter { $0.cardID == item.card.id },now:attempt.createdAt,settings:library.settings)
        guard let outcome = outcomes[grade] else { throw EngramError.invalid("The scheduler could not grade this answer.") }
        library.cards[ci].schedule = outcome; library.cards[ci].version += 1
        var review = ReviewEvent(id:"answer-" + item.presentationID,cardID:item.card.id,deckID:item.card.deckID,sessionID:session.id,
            rating:grade,reviewedAt:attempt.createdAt,committedAt:now,before:item.card.schedule,after:outcome)
        review.settingsSnapshot = library.settings
        review.assessment = attempt.assessment
        review.questionType = library.liveNotes.first { $0.id == attempt.noteID }?.canonicalQuestionType
        review.subject = library.liveNotes.first { $0.id == attempt.noteID }?.declaredSubject
        review.questionSubtype = library.liveNotes.first { $0.id == attempt.noteID }?.declaredQuestionSubtype
        review.questionSchemaVersion = 1; review.inputModality = attempt.inputModality ?? "typed"
        guard !library.reviews.contains(where: { $0.id == review.id }) else { throw EngramError.conflict }
        library.reviews.append(review); attempts[index].committedAt = now; library.answerAttempts = attempts
        if let improvement = attempt.acceptedImprovement {
            guard let ni = library.notes.firstIndex(where: { $0.id == attempt.noteID && !$0.deleted }) else { throw EngramError.conflict }
            let before = library.notes[ni]
            var draft = NoteDraft(note:before)
            if before.kind == .reversed && item.card.ordinal == 1 { draft.front = improvement }
            else if before.kind == .cloze {
                let markers = try Cloze.parse(before.front).filter { $0.ordinal == item.card.ordinal }
                guard Set(markers.map(\.answer)).count == 1 else { throw EngramError.invalid("This cloze has several distinct answers. Use the editor to update each deletion separately.") }
                for marker in markers.reversed() {
                    guard let range = Range(marker.range,in:draft.front), !improvement.contains("::"), !improvement.contains("{{"), !improvement.contains("}}") else { throw EngramError.invalid("Invalid cloze improvement.") }
                    draft.front.replaceSubrange(range,with:"{{c\(item.card.ordinal + 1)::\(improvement)\(marker.hint.map { "::" + $0 } ?? "")}}")
                }
            } else { draft.back = improvement }
            _ = try CardRenderer.ordinals(for:draft)
            library.notes[ni].front = draft.front; library.notes[ni].back = draft.back; library.notes[ni].modifiedAt = now
            for index in library.cards.indices where library.cards[index].noteID == before.id { library.cards[index].version += 1 }
            syncNotebooks(&library,deckIDs:[before.deckID])
            var change = AIContentChange(deckID:before.deckID,noteID:before.id)
            change.beforeNote = before; change.afterNote = library.notes[ni]
            Self.appendAIRecord(AIActionRecord(id:"improvement-" + attempt.id,name:"Accepted answer improvement",arguments:improvement,status:"completed",summary:"Updated card answer",changes:[change]),runID:"improvement-" + attempt.id,conversationID:"grading:" + attempt.id,to:&library)
            var state = library.assistantState ?? LearningAssistantState()
            state.memory.append(LearningMemory(id:"improvement-" + attempt.id,noteID:before.id,text:improvement,evidenceIDs:attempt.assessment?.evidenceIDs ?? []))
            library.assistantState = state
        }
        item.revealedAt = now; item.assessment = attempt.assessment; item.outcomes = outcomes; session.current = item; session.completed += 1
        library.session = session
        // Commit feedback and scheduling once; advancing is included in the same repository transaction.
        let queue = QueuePolicy.dueCards(in:library,deckID:session.deckID,now:now).filter { !(session.skippedCardIDs ?? []).contains($0.id) }
        session.queue = queue.map(\.id); session.current = queue.first.map(ReviewPresentation.init); library.session = session
        try Task.checkCancellation(); try await repository.commit(library,expectedRevision:library.revision)
    }
}
