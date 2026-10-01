import XCTest
import LearningCore
import StudyApplication
import PersistenceAdapters
import SchedulingAdapters

final class PDFLearningTests: XCTestCase {
    private var source: PDFLearningSource {
        PDFLearningSource(filename: "Cloud.pdf", pages: [
            PDFPageText(number: 1, text: "Amazon S3 stores objects in buckets. Access policies protect customer data."),
            PDFPageText(number: 2, text: "CloudFront caches content at edge locations close to users, reducing latency."),
            PDFPageText(number: 3, text: "CloudFront also reduces origin load. AWS protects cloud infrastructure.")
        ])
    }
    private var brief: PDFLearningBrief { var value = PDFLearningBrief(); value.lastPage = 3; return value }
    private func item(kind: String = "mcq") -> PDFLearningItem {
        PDFLearningItem(id: "supported", kind: kind, topic: "Storage", prompt: "Which service stores objects?",
            answer: "S3 stores objects in buckets.", options: kind == "mcq" ? ["S3", "CloudFront", "EC2"] : [],
            correctIndex: kind == "mcq" ? 0 : -1,
            citations: [PDFCitation(passageID: "p1-0", quote: "Amazon S3 stores objects in buckets.")], verified: true)
    }
    func testRetrievalRespectsPageScopeAndRanksRelevantEvidence() {
        var scoped = brief; scoped.firstPage = 2
        let passages = PDFRetrieval.retrieve(source: source, brief: scoped, query: "CloudFront latency", limit: 2)
        XCTAssertEqual(passages.first?.page, 2)
        XCTAssertEqual(Set(passages.map(\.page)), [2, 3])
        XCTAssertFalse(passages.contains { $0.page == 1 })
    }
    func testEmptyQueryDiversifiesAcrossDocumentRatherThanOnlyBeginning() {
        let passages = PDFRetrieval.retrieve(source: source, brief: brief, query: "", limit: 3)
        XCTAssertEqual(passages.map(\.page), [1, 2, 3])
    }
    func testCitationMustBeAnExactSubstringOfSuppliedPassage() throws {
        try PDFRetrieval.validate([item()], against: source.chunks)
        var invented = item(); invented.citations[0].quote = "Amazon S3 is a relational database."
        XCTAssertThrowsError(try PDFRetrieval.validate([invented], against: source.chunks))
        var wrongPage = item(); wrongPage.citations[0].passageID = "p2-0"
        XCTAssertThrowsError(try PDFRetrieval.validate([wrongPage], against: source.chunks))
        XCTAssertThrowsError(try PDFRetrieval.validate([item()], against: Array(source.chunks.dropFirst())))
    }
    func testRejectsUnshufflableAmbiguousAndInvalidChoices() {
        var invalid = item(); invalid.options[1] = "S3"
        XCTAssertThrowsError(try PDFRetrieval.validate([invalid], against: source.chunks))
        invalid = item(); invalid.correctIndex = 99
        XCTAssertThrowsError(try PDFRetrieval.validate([invalid], against: source.chunks))
        invalid = item(); invalid.options[1] = "All of the above"
        XCTAssertThrowsError(try PDFRetrieval.validate([invalid], against: source.chunks))
    }
    func testBadScopeAndTextlessDocumentsAreRejected() {
        var invalid = brief; invalid.firstPage = 3; invalid.lastPage = 1
        XCTAssertThrowsError(try invalid.validate(source: source))
        XCTAssertThrowsError(try PDFLearningSource(filename: "scan.pdf", pages: [PDFPageText(number: 1, text: "")]).validate())
    }
    func testShuffledLettersKeepCanonicalAnswerAndStableResume() throws {
        let question = try XCTUnwrap(MultipleChoiceQuestion.parse(front: item().front, back: item().back))
        let ordered = question.ordered(for: "presentation-1")
        XCTAssertEqual(ordered, question.ordered(for: "presentation-1"))
        XCTAssertEqual(Set(ordered.choices.map(\.id)), Set(question.choices.map(\.id)))
        let displayedCorrect = ordered.displayLetter(for: question.correctID)
        XCTAssertEqual(ordered.resolvePresented("option " + displayedCorrect), question.correctID)
        XCTAssertEqual(ordered.resolvePresented("S3"), question.correctID)
        XCTAssertTrue(ordered.displayedExplanation.hasPrefix(displayedCorrect + ")"))
        XCTAssertGreaterThan(Set((0..<20).map { question.ordered(for: "presentation-\($0)").choices.map(\.id).joined() }).count, 1)
    }
    func testPDFDeckCommitsAtomicallyAndRetriesWithoutDuplicates() async throws {
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let id = UUID().uuidString
        var notes = item(kind: "note"); notes.id = "notes"; notes.prompt = "Object storage"
        let record = PDFLearningRecord(source: source, brief: brief, items: [item(), notes])
        let deck = try await service.createPDFDeck(id: id, title: "Cloud", record: record)
        _ = try await service.createPDFDeck(id: id, title: "Cloud", record: record)
        let saved = try await service.snapshot()
        XCTAssertEqual(saved.liveDecks.count, 1); XCTAssertEqual(saved.liveCards.count, 1)
        XCTAssertEqual(saved.revision, 1); XCTAssertEqual(deck.pdfLearning, record)
        XCTAssertEqual(deck.notebookBlocks?.filter { $0.kind == .text }.count, 1)
        XCTAssertTrue(saved.liveNotes[0].source.contains("p. 1"))
        let decoded = try JSONDecoder().decode(LibrarySnapshot.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(decoded, saved)
    }
    func testUnverifiedContentCannotCreateDeckAndInvalidBatchLeavesNoPartialData() async throws {
        let service = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        var unchecked = item(); unchecked.verified = false
        do {
            _ = try await service.createPDFDeck(id: UUID().uuidString, title: "Unsafe", record: PDFLearningRecord(source: source, brief: brief, items: [unchecked]))
            XCTFail("Accepted unchecked content")
        } catch {}
        let saved = try await service.snapshot()
        XCTAssertTrue(saved.decks.isEmpty); XCTAssertTrue(saved.cards.isEmpty)
    }
    func testOldDeckStillDecodesWithoutPDFMetadata() throws {
        let deck = Deck(name: "Legacy")
        let decoded = try JSONDecoder().decode(Deck.self, from: JSONEncoder().encode(deck))
        XCTAssertNil(decoded.pdfLearning)
    }
}
