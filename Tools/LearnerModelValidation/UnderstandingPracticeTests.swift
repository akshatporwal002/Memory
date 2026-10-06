import Foundation

extension LearnerAdvancedValidation {
    static func understandingPractice() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("understanding-validation-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let account = UUID(), scheduler = FSRSScheduler(), store = LearnerModelRepository(directory: directory)
        var source = LibrarySnapshot()
        source.decks = [Deck(id: "deck", name: "AWS"), Deck(id: "empty", name: "Empty notebook")]
        var note = Note(id: "q", deckID: "deck", kind: .basic, front: "What does CloudFront do?", back: "Deliver cached content closer to users.", modifiedAt: date)
        source.notes = [note]
        source.cards = [StudyCard(id: "c", noteID: note.id, deckID: "deck", schedule: try scheduler.initialState(now: date, settings: source.settings))]
        var retired = source.cards[0]; retired.id = "retired"; retired.retired = true
        var suspended = source.cards[0]; suspended.id = "suspended"; suspended.suspended = true
        source.cards += [retired, suspended]
        let evidence = EvidenceRetrieval.retrieve(query: note.front, deckID: note.deckID, library: source, preferredNoteID: note.id, limit: 8).map { AttemptEvidence(id: $0.id, text: $0.text, version: $0.version) }
        var variants: [QuestionVariant] = []
        for (i, approach) in [QuestionApproach.explain, .apply, .compare].enumerated() {
            var variant = QuestionVariant(id: "v\(i)", approach: approach, front: "CloudFront approach \(i)", back: "Cached content closer to users.", objective: "Same source knowledge", rubric: "Cache and proximity; bounded response", evidence: evidence)
            let mapping = try ReviewedSkillMapping(questionID: "q:variant:" + variant.id, questionVersion: 1, revision: "ai-test", skillIDs: ["aws.cloudfront.delivery"], reviewedBy: "synthetic AI checks")
            variant.validation = VariantValidation(mapping: mapping, modelID: "test-checker", checkedAt: date, sourceSupported: true, samePrerequisites: true, comparableReasoning: i != 2, rubricSupported: true, harder: i == 2, front: variant.front, back: variant.back, rubric: variant.rubric)
            variants.append(variant)
        }
        note.questionFamily = QuestionFamily(originalFront: note.front, originalBack: note.back, variants: variants, reviewedAt: date)
        source.notes = [note]
        let base = MemoryRepository(initial: source), service = StudyService(repository: base, scheduler: scheduler, learnerStore: store, learnerAccount: { account })
        try await service.setLearnerRecordingEnabled(true)
        var defaults = UnderstandingSettings(); defaults.batchSize = 1; defaults.quickFeedback = true
        let session = try await service.startUnderstandingSession(deckID: "deck", defaults: defaults, providerIdentity: "provider", gradingModel: "model", now: date)
        try require(session.current?.variant.id == "v0", "Predictive Off fallback rotates deterministically and excludes harder")
        try await rejectsAsync { try await service.switchLearnerModel(to: .bkt, mode: .observe) }
        let first = session.current!
        try await service.saveUnderstandingDraft(sessionID: session.id, attemptID: first.id, answer: "Saved draft", assisted: false, activeSeconds: 3, now: date.addingTimeInterval(3))
        try await service.saveUnderstandingDraft(sessionID: session.id, attemptID: first.id, answer: "Older draft", assisted: false, activeSeconds: 2, now: date.addingTimeInterval(2))
        let drafts = try await service.understandingSessions()
        try require(drafts[0].current?.answer == "Saved draft", "Draft recovery and stale edit rejection")
        let following = try await service.submitUnderstandingAnswer(sessionID: session.id, attemptID: first.id, answer: "Cached content nearby", assisted: false, activeSeconds: 12, provisional: .good, now: date.addingTimeInterval(12))
        let batch = try await service.understandingBatch(providerIdentity: "provider")
        try require(batch.count == 1 && batch[0].provisional == .good && following.current?.variant.id == "v1", "Provisional queue does not block next approach")
        let beforeGrade = try await store.load(account: account, library: "default")
        try require(beforeGrade.evidence.isEmpty, "Provisional grading is not accepted training evidence")
        let eid = first.variant.evidence[0].id
        func json(_ id: String, _ correct: Bool) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: ["attempt_id": id, "outcome": correct ? "correct" : "incorrect", "reason": "Supported assessment", "evidence_ids": [eid]]), as: UTF8.self)
        }
        try await service.acceptUnderstandingAssessment(attemptID: first.id, json: json(first.id, true), providerIdentity: "provider")
        try await service.acceptUnderstandingAssessment(attemptID: first.id, json: json(first.id, true), providerIdentity: "provider")
        var learned = try await store.load(account: account, library: "default")
        try require(learned.latest.count == 1 && learned.latest[0].correct == true && learned.latest[0].studySeconds == 12, "Accepted same attempt ingested once")
        try await service.acceptUnderstandingAssessment(attemptID: first.id, json: json(first.id, false), providerIdentity: "provider")
        learned = try await store.load(account: account, library: "default")
        try require(learned.latest.count == 1 && learned.latest[0].revision == 2 && learned.latest[0].correct == false, "Grade correction revises one logical attempt")
        try await rejectsAsync { try await service.acceptUnderstandingAssessment(attemptID: first.id, json: json(first.id, true), providerIdentity: "other-account") }
        let last = following.current!
        let ended = try await service.submitUnderstandingAnswer(sessionID: session.id, attemptID: last.id, answer: "I viewed the answer", assisted: true, activeSeconds: 7, now: date.addingTimeInterval(25))
        try require(ended.endedAt != nil, "Ends after eligible approaches without padding")
        try await service.acceptUnderstandingAssessment(attemptID: last.id, json: json(last.id, true), providerIdentity: "provider")
        let status = try await service.learnerStatus(), untouched = try await base.read()
        try require(status.state.latest.count == 2 && status.state.latest.last?.assisted == true && status.dashboard.unfamiliarQuestions.attempts == 0,
            "Assistance preserved and unfamiliarity not fabricated")
        try require(untouched.cards == source.cards && untouched.reviews == source.reviews && untouched.session == nil, "Understanding never resets or creates FSRS reviews")
        let analytics = try await service.notebookAnalytics(deckID: "deck", now: date.addingTimeInterval(30))
        let emptyAnalytics = try await service.notebookAnalytics(deckID: "empty", now: date.addingTimeInterval(30))
        try require(analytics.observed.acceptedAttempts == 2 && analytics.observed.measuredStudySeconds == 19 && emptyAnalytics.observed.acceptedAttempts == 0, "Notebook analytics isolate observed outcomes and measured duration")
        try require(analytics.recallTotalCards == 1 && analytics.recallEstimatedCards == 0 && analytics.predictedRecall == nil, "FSRS analytics exclude retired/suspended cards and unknown new-card recall")
        try require(analytics.components.count == 4 && analytics.components.allSatisfy { $0.mode == .off && $0.questions.allSatisfy { $0.prediction == nil && $0.calibratedDifficulty == nil } }, "Off analytics never invent predictions or difficulty")
        let afterAnalytics = try await service.learnerStatus()
        try require(afterAnalytics.state == status.state, "Opening analytics does not switch, prepare or change evidence")
        let reopened = StudyService(repository: base, scheduler: scheduler, learnerStore: LearnerModelRepository(directory: directory), learnerAccount: { account })
        let restored = try await reopened.understandingSessions()
        try require(restored[0].attempts[0].assessmentRevisions.count == 1 && restored[0].attempts[0].provisional == .good, "Cold restart retains provisional/final revisions")
        var override = defaults; override.reviewTiming = .sessionEnd
        try await reopened.setUnderstandingSettings(deckID: "deck", settings: override, expectedRevision: untouched.revision)
        let second = try await reopened.startUnderstandingSession(deckID: "deck", defaults: defaults, providerIdentity: "provider", gradingModel: "model", now: date.addingTimeInterval(100))
        _ = try await reopened.submitUnderstandingAnswer(sessionID: second.id, attemptID: second.current!.id, answer: "Pending", assisted: false, activeSeconds: 5)
        let deferred = try await reopened.understandingBatch(providerIdentity: "provider")
        try require(deferred.isEmpty, "Notebook override waits for session end")
        try await reopened.setLearnerRecordingEnabled(false)
        try await reopened.endUnderstandingSession(id: second.id)
        let finalBatch = try await reopened.understandingBatch(providerIdentity: "provider")
        try require(finalBatch.count == 1 && !finalBatch[0].recordingEnabled, "Session-end flush and revoked recording permission")
        try await reopened.acceptUnderstandingAssessment(attemptID: finalBatch[0].id, json: json(finalBatch[0].id, true), providerIdentity: "provider")
        try await reopened.setLearnerRecordingEnabled(true)
        _ = try await reopened.understandingSessions()
        let noBackfill = try await store.load(account: account, library: "default")
        try require(noBackfill.latest.count == 2, "Re-enabling consent does not backfill an opted-out attempt")
        let other = StudyService(repository: base, scheduler: scheduler, learnerStore: store, learnerAccount: { UUID(uuidString: "00000000-0000-0000-0000-000000000001")! })
        let isolated = try await other.understandingSessions()
        try require(isolated.isEmpty, "Understanding attempts isolated by account")
        let isolatedAnalytics = try await other.notebookAnalytics(deckID: "deck")
        try require(isolatedAnalytics.observed.acceptedAttempts == 0, "Notebook analytics isolated by account")
        print("PASS: understanding sessions, rotation, queued batches, provisional/final correction, consent, restart, isolation and FSRS preservation")
    }
}
