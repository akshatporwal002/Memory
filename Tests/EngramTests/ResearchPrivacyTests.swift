import XCTest
import LearningCore
import PersistenceAdapters

final class ResearchPrivacyTests: XCTestCase {
    func testMathDomainIsSeparateFromChoiceFormat() {
        var note = Note(deckID: "d", kind: .basic, front: "Choose", back: "A", tags: ["math", "subtype:probability"])
        note.questionType = "mcq"
        XCTAssertEqual(note.canonicalQuestionType, "mcq")
        XCTAssertEqual(note.declaredSubject, "maths")
        XCTAssertEqual(note.declaredQuestionSubtype, "probability")
        XCTAssertFalse(note.acceptsMathInput)
    }
    func testSeparateContentConsentRevocationDeduplicationAndAccountIsolation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("research-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ResearchEventRepository(directory: directory), account = UUID()
        var event = ResearchEvent(kind: "review"); event.answerText = "Private answer"; event.questionType = "equation"
        try await repository.append(event, deduplicationKey: "review", account: account)
        let initial = try await repository.load(account: account)
        XCTAssertTrue(initial.events.isEmpty)
        var consent = ResearchConsent(); consent.metrics = true; consent.updatedAt = event.occurredAt.addingTimeInterval(-1)
        try await repository.setConsent(consent, account: account)
        try await repository.append(event, deduplicationKey: "review", account: account)
        try await repository.append(event, deduplicationKey: "review", account: account)
        let metrics = try await repository.load(account: account)
        XCTAssertEqual(metrics.events.count, 1); XCTAssertNil(metrics.events.first?.answerText)
        let other = try await repository.load(account: UUID()); XCTAssertTrue(other.events.isEmpty)
        consent.answerContent = true; try await repository.setConsent(consent, account: account)
        event.id = UUID(); try await repository.append(event, deduplicationKey: "second", account: account)
        let content = try await repository.load(account: account); XCTAssertEqual(content.events.last?.answerText, "Private answer")
        consent.answerContent = false; try await repository.setConsent(consent, account: account)
        let revoked = try await repository.load(account: account); XCTAssertTrue(revoked.events.allSatisfy { $0.answerText == nil })
        consent.metrics = false; try await repository.setConsent(consent, account: account)
        let off = try await repository.load(account: account); XCTAssertTrue(off.events.isEmpty)
    }
    func testInvalidFutureExpiredOrUnconsentedHistoryCannotBeCollected() {
        var consent = ResearchConsent(); consent.metrics = true
        let now = Date(); consent.updatedAt = now.addingTimeInterval(-10)
        var event = ResearchEvent(kind: "review", occurredAt: now)
        event.durationMS = .nan; XCTAssertNil(event.permitted(by: consent))
        event.durationMS = 0; event.occurredAt = now.addingTimeInterval(600); XCTAssertNil(event.permitted(by: consent))
        event.occurredAt = now.addingTimeInterval(-20); XCTAssertNil(event.permitted(by: consent))
        event.kind = "secret"; event.occurredAt = now; XCTAssertNil(event.permitted(by: consent))
    }
    func testTutorActivationReusesWorkspaceAndDoesNotCreateStudyDecks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tutor-activation-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = TutorWorkspaceRepository(directory: directory), owner = UUID()
        let first = try await repository.ensureWorkspace(ownerID: owner), second = try await repository.ensureWorkspace(ownerID: owner)
        XCTAssertEqual(first.id, second.id)
        let saved = try await repository.load(ownerID: owner); XCTAssertEqual(saved.count, 1)
        XCTAssertTrue(first.assignments.isEmpty)
    }
}
