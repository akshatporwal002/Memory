import XCTest
import TutorFoundation

final class TutorFoundationTests: XCTestCase {
    func testAnswerContainsOnlySuppliedInspectableCitation() async throws {
        let source = try TutorSource(id: "book-1", title: "Biology", locator: "p. 12", version: "1", excerpt: "Cells have membranes.")
        let question = try TutorQuestion(text: "What surrounds a cell?", sources: [source])
        let outcome = await GroundedTutor(provider: StubTutor(draft: TutorDraft(text: "A membrane.", citedSourceIDs: ["book-1"]))).answer(question)
        guard case .answer(let text, let citations) = outcome else { return XCTFail("Expected cited answer") }
        XCTAssertEqual(text, "A membrane.")
        XCTAssertEqual(citations, [source])
    }

    func testUnknownCitationBecomesInsufficientEvidence() async throws {
        let source = try TutorSource(id: "book-1", title: "Biology", locator: "p. 12", excerpt: "Cells have membranes.")
        let question = try TutorQuestion(text: "What surrounds a cell?", sources: [source])
        let outcome = await GroundedTutor(provider: StubTutor(draft: TutorDraft(text: "A membrane.", citedSourceIDs: ["invented"]))).answer(question)
        guard case .insufficientEvidence = outcome else { return XCTFail("Expected abstention") }
    }

    func testMissingSourcesAndProviderFailureRemainDistinct() async throws {
        let withoutSources = try TutorQuestion(text: "Explain this", sources: [])
        let abstention = await GroundedTutor(provider: StubTutor(draft: TutorDraft(text: "unused", citedSourceIDs: []))).answer(withoutSources)
        guard case .insufficientEvidence = abstention else { return XCTFail("Expected evidence abstention") }

        let source = try TutorSource(id: "source", title: "Source", locator: "section", excerpt: "Evidence")
        let unavailable = await GroundedTutor(provider: FailingTutor()).answer(try TutorQuestion(text: "Explain", sources: [source]))
        guard case .unavailable = unavailable else { return XCTFail("Expected service unavailability") }
    }
}

private struct StubTutor: TutorProvider {
    let draft: TutorDraft
    func answer(question: TutorQuestion) async throws -> TutorDraft { draft }
}
private struct FailingTutor: TutorProvider {
    func answer(question: TutorQuestion) async throws -> TutorDraft { throw TestError.failed }
}
private enum TestError: Error { case failed }
