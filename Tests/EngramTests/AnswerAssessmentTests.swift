import XCTest
import LearningCore
import StudyApplication
import PersistenceAdapters
import SchedulingAdapters

final class AnswerAssessmentTests: XCTestCase {
    let front = "Which stores objects? A) EC2; B) Amazon S3; C) RDS; D) Lambda"
    let back = "B) Amazon S3. Object storage."
    func testChoiceRecognitionAndAmbiguity() throws {
        let question = try XCTUnwrap(MultipleChoiceQuestion.parse(front: front, back: back))
        XCTAssertEqual(question.choices.count, 4)
        for utterance in ["B", "option B", "bravo", "Amazon S3", "S3", "B actually C"] {
            XCTAssertEqual(question.resolve(utterance), utterance == "B actually C" ? "C" : "B")
        }
        XCTAssertNil(question.resolve("S3 is not object storage"))
        XCTAssertNil(question.resolve("B or C"))
        XCTAssertNil(MultipleChoiceQuestion.parse(front: front, back: "A guess without an explicit key"))
    }
    func testAtomicFirstAnswerAndFeedbackResumption() async throws {
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let deck = try await service.createDeck(from: DeckCreationDraft(title: "Quiz", document: front + " -> " + back))
        let session = try await service.startSession(deckID: deck.id, now: Date())
        let item = try XCTUnwrap(session.current)
        try await service.submitAnswer(sessionID: session.id, presentationID: item.presentationID, choiceID: "B")
        try await service.submitAnswer(sessionID: session.id, presentationID: item.presentationID, choiceID: "A")
        let snapshot = try await service.snapshot()
        XCTAssertEqual(snapshot.reviews.count, 1)
        XCTAssertEqual(snapshot.reviews.first?.rating, .good)
        XCTAssertEqual(snapshot.session?.current?.assessment?.choiceID, "B")
        let resumed = try await service.startSession(deckID: deck.id, now: Date())
        XCTAssertEqual(resumed.current?.presentationID, item.presentationID)
        try await service.nextAssessedAnswer(sessionID: session.id, presentationID: item.presentationID)
        let next = try await service.snapshot()
        XCTAssertNotEqual(next.session?.current?.presentationID, item.presentationID)
    }
    func testWrongAnswerAndSkip() async throws {
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let deck = try await service.createDeck(from: DeckCreationDraft(title: "Quiz", document: front + " -> " + back))
        let session = try await service.startSession(deckID: deck.id, now: Date())
        let item = try XCTUnwrap(session.current)
        try await service.skipAnswer(sessionID: session.id, presentationID: item.presentationID)
        let skipped = try await service.snapshot()
        XCTAssertTrue(skipped.reviews.isEmpty)
        let fresh = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let d = try await fresh.createDeck(from: DeckCreationDraft(title: "Wrong", document: front + " -> " + back))
        let s = try await fresh.startSession(deckID: d.id, now: Date())
        try await fresh.submitAnswer(sessionID: s.id, presentationID: s.current!.presentationID, choiceID: "A")
        let result = try await fresh.snapshot()
        XCTAssertEqual(result.reviews.first?.rating, .again)
        try await fresh.undo(sessionID: s.id, now: Date())
        let undone = try await fresh.snapshot()
        XCTAssertTrue(undone.activeReviews.isEmpty)
    }
    func testUnsupportedAIEvidenceNeverGrades() throws {
        let result = #"{"outcome":"correct","reason":"Matched","evidence_ids":["invented"]}"#
        XCTAssertThrowsError(try LocalAnswerEvidence.validate(result, allowedIDs: ["real"]))
        XCTAssertThrowsError(try LocalAnswerEvidence.validate("not JSON", allowedIDs: []))
        let unclear = try LocalAnswerEvidence.validate(#"{"outcome":"unclear","reason":"Please repeat","evidence_ids":[]}"#, allowedIDs: [])
        XCTAssertNil(unclear.rating)
    }
    func testLegacyModelsDecodeWithoutNewFields() throws {
        let note = Note(deckID: "d", kind: .basic, front: front, back: back)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(note)) as! [String: Any]
        object.removeValue(forKey: "multipleChoice")
        let legacy = try JSONDecoder().decode(Note.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNotNil(legacy.mcq)
    }
}
