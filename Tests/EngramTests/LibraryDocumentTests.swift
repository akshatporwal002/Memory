import Foundation
import XCTest
import LearningCore
import StudyApplication
import PersistenceAdapters
import SchedulingAdapters

final class LibraryDocumentTests: XCTestCase {
    func testMarkdownSourceIsRetrievedAndRemovedWithNotebook() async throws {
        let app = StudyService(repository:MemoryRepository(),scheduler:FSRSScheduler())
        let deck = try await app.createDeck(name:"Cloud")
        let text = "# Edge caching\nCloudFront keeps content close to readers."
        let document = LibraryDocument(name:"cloudfront.md",kind:.markdown,
            pages:[PDFPageText(number:1,text:text)],originalData:Data(text.utf8))
        try await app.addDocument(document,to:deck.id)
        var snapshot = try await app.snapshot()
        XCTAssertEqual(snapshot.liveDecks.first?.documents?.first?.originalData,Data(text.utf8))
        let evidence = try XCTUnwrap(EvidenceRetrieval.retrieve(query:"CloudFront content",deckID:deck.id,library:snapshot).first)
        XCTAssertEqual(evidence.documentID,document.id)
        XCTAssertEqual(evidence.title,"cloudfront.md · page 1")
        XCTAssertTrue(EvidenceRetrieval.isCurrent(AttemptEvidence(id:evidence.id,text:evidence.text,version:evidence.version),in:snapshot))
        try await app.removeDocument(id:document.id,from:deck.id)
        snapshot = try await app.snapshot()
        XCTAssertFalse(EvidenceRetrieval.isCurrent(AttemptEvidence(id:evidence.id,text:evidence.text,version:evidence.version),in:snapshot))
    }
}
