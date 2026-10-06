import Foundation

extension LearnerAdvancedValidation {
    static func questionFamilies() async throws {
        let scheduler = FSRSScheduler()
        var snapshot = LibrarySnapshot()
        snapshot.decks = [Deck(id: "deck", name: "AWS")]
        let note = Note(id: "q", deckID: "deck", kind: .basic, front: "What does CloudFront do?", back: "Deliver cached content closer to users.", modifiedAt: date)
        snapshot.notes = [note]
        snapshot.cards = [StudyCard(id: "c", noteID: note.id, deckID: "deck", schedule: try scheduler.initialState(now: date, settings: snapshot.settings))]
        let repository = MemoryRepository(initial: snapshot)
        let service = StudyService(repository: repository, scheduler: scheduler)
        let sources = EvidenceRetrieval.retrieve(query: note.front, deckID: note.deckID, library: snapshot, preferredNoteID: note.id, limit: 8)
        let evidence = sources.map { AttemptEvidence(id: $0.id, text: $0.text, version: $0.version) }
        let variant = QuestionVariant(id: "explain", approach: .explain, front: "Complete: CloudFront reduces latency because…", back: "It serves cached content closer to users.", objective: "Explain the same content-delivery mechanism.", rubric: "Mention cached content and proximity; one sentence.", evidence: evidence)
        try await service.saveQuestionVariants(noteID: "q", originalFront: note.front, originalBack: note.back, variants: [variant], expectedRevision: 0, now: date)
        let saved = try await repository.read()
        try require(saved.cards == snapshot.cards && saved.reviews == snapshot.reviews && saved.notes[0].front == note.front, "Variant save does not alter FSRS/original")
        let roundTrip = try JSONDecoder().decode(LibrarySnapshot.self, from: JSONEncoder().encode(saved))
        try require(roundTrip.notes[0].questionFamily?.available(in: roundTrip, note: roundTrip.notes[0]) == [variant], "Offline persisted family")
        try await service.recordQuestionVariantExposure(noteID: "q", variantID: variant.id, now: date)
        let exposed = try await repository.read()
        try require(exposed.notes[0].questionFamily?.exposedVariantIDs[variant.id] == date && exposed.cards == snapshot.cards && exposed.reviews.isEmpty, "Exposure is not a scored attempt or scheduler reset")
        do {
            try await service.saveQuestionVariants(noteID: "q", originalFront: note.front, originalBack: note.back, variants: [variant, variant], expectedRevision: exposed.revision)
            throw NSError(domain: "Expected duplicate rejection", code: 1)
        } catch is EngramError {}
        var stale = variant; stale.evidence[0].version = "invented"
        do {
            try await service.saveQuestionVariants(noteID: "q", originalFront: note.front, originalBack: note.back, variants: [stale], expectedRevision: exposed.revision)
            throw NSError(domain: "Expected stale evidence rejection", code: 1)
        } catch is EngramError {}
        var objectiveEdit = variant
        objectiveEdit.objective = "Explain the latency implication without adding prerequisites."
        objectiveEdit.validation = VariantValidation(mapping: try ReviewedSkillMapping(questionID: "q:variant:explain", questionVersion: 1, revision: "q-v1", skillIDs: ["aws:content-delivery"], reviewedBy: "test"), modelID: "fixture", checkedAt: date, sourceSupported: true, samePrerequisites: true, comparableReasoning: true, rubricSupported: true, harder: false, front: variant.front, back: variant.back, rubric: variant.rubric)
        try await service.saveQuestionVariants(noteID: "q", originalFront: note.front, originalBack: note.back, variants: [objectiveEdit], expectedRevision: exposed.revision)
        let objectiveChanged = try await repository.read()
        try require(objectiveChanged.notes[0].questionFamily?.variants[0].revision == 2 && objectiveChanged.notes[0].questionFamily?.variants[0].validation == nil, "Task objective changes invalidate old validation and content identity")
        try require(objectiveChanged.cards == snapshot.cards, "Task revision preserves FSRS")
        var draft = NoteDraft(note: objectiveChanged.notes[0]); draft.front = "Changed prerequisite knowledge"
        _ = try await service.saveNote(draft, now: date.addingTimeInterval(1))
        let changed = try await repository.read()
        try require(changed.notes[0].questionFamily == nil, "Original content edit invalidates old variants")
        let legacy = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(note))
        try require(legacy.questionFamily == nil, "Old notes remain compatible")
        print("PASS: question-family persistence, exposure, source validation, edit invalidation and unchanged FSRS")
    }
}
