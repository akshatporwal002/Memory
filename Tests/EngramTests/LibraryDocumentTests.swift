import Foundation
import XCTest
import LearningCore
import StudyApplication
import PersistenceAdapters
import SchedulingAdapters
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Features

final class LibraryDocumentTests: XCTestCase {
    func testPhotoImportNormalizesToReadableJPEG() throws {
        let context = try XCTUnwrap(CGContext(data:nil,width:32,height:32,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray:1,alpha:1))
        context.fill(CGRect(x:0,y:0,width:32,height:32))
        let sourceImage = try XCTUnwrap(context.makeImage())
        let bytes = NSMutableData()
        let writer = try XCTUnwrap(CGImageDestinationCreateWithData(bytes,UTType.png.identifier as CFString,1,nil))
        CGImageDestinationAddImage(writer,sourceImage,nil)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        let image = try LibraryDocumentImport.image(data:bytes as Data,name:"notes.jpg")
        XCTAssertEqual(image.kind,.image)
        XCTAssertTrue(image.originalData.starts(with:[0xFF,0xD8,0xFF]))
        XCTAssertNotNil(CGImageSourceCreateWithData(image.originalData as CFData,nil))
    }

    func testImageWithoutRecognizedTextIsSavedButNotUsedAsEvidence() async throws {
        let app = StudyService(repository:MemoryRepository(),scheduler:FSRSScheduler())
        let deck = try await app.createDeck(name:"Illustrations")
        let image = LibraryDocument(name:"diagram.jpg",kind:.image,pages:[],originalData:Data([0xFF,0xD8,0xFF,0xD9]))
        try await app.addDocument(image,to:deck.id)
        let snapshot = try await app.snapshot()
        XCTAssertEqual(snapshot.liveDecks.first?.documents?.first?.kind,.image)
        XCTAssertTrue(EvidenceRetrieval.retrieve(query:"diagram",deckID:deck.id,library:snapshot).isEmpty)
    }

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
