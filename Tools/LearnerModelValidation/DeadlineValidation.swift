import Foundation

func validateDeadlinePrototype() throws {
    func require(_ condition: @autoclosure () -> Bool, _ label: String) throws {
        if !condition() { throw NSError(domain: "DeadlineValidation", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
    }
    let now = Date(timeIntervalSince1970: 2_000_000)
    let item = DeadlineGoal.Item(id: "deadline-card", prompt: "Question", answer: "Answer", questionType: "short-answer", questionVersion: 1)
    let goal = DeadlineGoal(deckID: "deadline-deck", createdAt: now, deadline: now.addingTimeInterval(7 * 86400), target: 0.8, dailyMinutes: 1, items: [item])
    let plan = try DeadlinePlanner.make(goal: goal, evidence: [], evidenceRevision: 0, now: now)
    try require(plan.actions.allSatisfy { $0.date >= now && $0.date < goal.deadline }, "Actions stay in planning window")
    for date in Set(plan.actions.map(\.date)) {
        try require(plan.actions.filter { $0.date == date }.reduce(0) { $0 + $1.seconds } <= 60, "Daily time budget")
    }
    try require(plan.forecast >= plan.baseline && plan.forecast <= 1, "Bounded forecast")
    let recent = try DeadlinePlanner.make(goal: goal, evidence: [], evidenceRevision: 0, recentlyPractisedIDs: [item.id], now: now)
    try require(!recent.actions.contains { $0.date == now }, "Recent manual review is not immediately repeated")
    let stale = try DeadlinePlanner.make(goal: goal, evidence: [], evidenceRevision: 0, staleItems: 1, now: now)
    try require(stale.actions.isEmpty && stale.baseline == stale.forecast, "Stale blueprint cannot plan")
    func row(_ revision: Int, acceptance: LearnerEvidence.Acceptance = .accepted, correct: Bool? = true, assisted: Bool? = false, date: Date = now) -> LearnerEvidence {
        LearnerEvidence(attemptID: "deadline-attempt", revision: revision, questionID: item.id, questionVersion: 1,
                        occurredAt: date, kind: .recall, assisted: assisted, acceptance: acceptance, correct: correct, gradingMethod: "local-exact", delaySeconds: 86400, studySeconds: 20)
    }
    let corrected = try DeadlinePlanner.make(goal: goal, evidence: [row(1), row(2, acceptance: .retracted, correct: nil)], evidenceRevision: 2, now: now)
    try require(corrected.observations == 0, "Retraction supersedes accepted attempt")
    let future = try DeadlinePlanner.make(goal: goal, evidence: [row(1, date: now.addingTimeInterval(100))], evidenceRevision: 1, now: now)
    try require(future.observations == 0, "Future outcome never leaks")
    let assisted = try DeadlinePlanner.make(goal: goal, evidence: [row(1, assisted: true)], evidenceRevision: 1, now: now)
    try require(assisted.observations == 0, "Assisted answer excluded")
    let accepted = try DeadlinePlanner.make(goal: goal, evidence: [row(1), row(1)], evidenceRevision: 1, now: now)
    try require(accepted.observations == 1 && accepted.timedSeconds == 20, "Attempts deduplicated")
    try require(!accepted.actions.contains { $0.date == now }, "Do not immediately repeat today's accepted answer")
    let expired = try DeadlinePlanner.make(goal: goal, evidence: [], evidenceRevision: 0, now: goal.deadline)
    try require(expired.actions.isEmpty, "No actions after deadline")
    var invalid = goal; invalid.dailyMinutes = 0
    do { try invalid.validate(); throw NSError(domain: "DeadlineValidation", code: 2) } catch is EngramError { }
    let old = try JSONDecoder().decode(LearnerWorkspace.self, from: Data("{\"schemaVersion\":1,\"revision\":0,\"recordingEnabled\":false,\"questions\":[],\"captures\":[],\"candidates\":[],\"artifactReviews\":[]}".utf8))
    try require(old.deadlineRecords == nil, "Old workspaces decode")
    var workspace = LearnerWorkspace(); workspace.deadlineRecords = [DeadlineRecord(goal: goal, forecasts: [plan])]
    let restored = try JSONDecoder().decode(LearnerWorkspace.self, from: JSONEncoder().encode(workspace))
    try restored.validate()
    try require(restored.deadlineRecords == workspace.deadlineRecords, "Goal and forecast survive restart")
    print("Deadline prototype: budget, bounds, evidence, stale content and persistence checks passed")
}

private actor DeadlineLibraryFixture: LibraryRepository {
    var snapshot: LibrarySnapshot
    init(_ snapshot: LibrarySnapshot) { self.snapshot = snapshot }
    func read() -> LibrarySnapshot { snapshot }
    func commit(_ next: LibrarySnapshot, expectedRevision: Int) throws {
        guard snapshot.revision == expectedRevision else { throw EngramError.conflict }
        snapshot = next; snapshot.revision += 1
    }
}

func validateDeadlineIntegration() async throws {
    func require(_ condition: Bool, _ label: String) throws {
        if !condition { throw NSError(domain: "DeadlineIntegration", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
    }
    let now = Date(timeIntervalSince1970: 3_000_000), scheduler = FSRSScheduler()
    let deck = Deck(id: "deadline-integration", name: "Deadline integration")
    let note = Note(id: "deadline-note", deckID: deck.id, kind: .basic, front: "What?", back: "Answer")
    // Future FSRS due date proves explicit planned practice can run independently.
    let card = StudyCard(id: "deadline-integration-card", noteID: note.id, deckID: deck.id,
                         schedule: try scheduler.initialState(now: now.addingTimeInterval(30 * 86400), settings: StudySettings()))
    var library = LibrarySnapshot(); library.decks = [deck]; library.notes = [note]; library.cards = [card]
    let base = DeadlineLibraryFixture(library)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("deadline-integration-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LearnerModelRepository(directory: directory), account = UUID()
    let service = StudyService(repository: base, scheduler: scheduler, learnerStore: store, learnerAccount: { account })
    try await service.saveDeadlineGoal(deckID: deck.id, deadline: now.addingTimeInterval(7 * 86400), target: 0.8, dailyMinutes: 1, now: now)
    let saved = try await service.deadlineRecord(deckID: deck.id)
    try require(saved?.goal.items.count == 1 && saved?.forecasts.count == 1, "Goal persisted with initial forecast")
    let before = try await service.snapshot()
    let session = try await service.startDeadlineSession(deckID: deck.id, now: now)
    try require(session.current?.card.id == card.id, "Plan presents a card not due under FSRS")
    let after = try await service.snapshot()
    try require(before.cards == after.cards, "Planning and session start preserve FSRS state")
    try await service.skipAnswer(sessionID: session.id, presentationID: session.current!.presentationID, now: now)
    let skipped = try await service.snapshot()
    try require(skipped.session?.current == nil && skipped.session?.queue.isEmpty == true, "Skip preserves finite planned queue")
    let otherAccount = UUID()
    let other = StudyService(repository: base, scheduler: scheduler, learnerStore: store, learnerAccount: { otherAccount })
    let isolated = try await other.deadlineRecord(deckID: deck.id)
    try require(isolated == nil, "Another account cannot see deadline goals")
    var edited = try await base.read(); edited.notes[0].back = "Changed answer"
    try await base.commit(edited, expectedRevision: edited.revision)
    let stale = try await service.deadlinePlan(deckID: deck.id, now: now)
    try require(stale.staleItems == 1 && stale.actions.isEmpty, "Changed content blocks planning")
    try await service.removeDeadlineGoal(deckID: deck.id)
    let removed = try await service.deadlineRecord(deckID: deck.id)
    try require(removed == nil, "Explicit goal removal persists")
    print("Deadline integration: persistence, account scope, independent practice, finite queue and stale blueprint passed")
}
