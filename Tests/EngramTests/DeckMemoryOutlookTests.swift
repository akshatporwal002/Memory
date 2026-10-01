import Foundation
import XCTest
import LearningCore
import StudyApplication
import PersistenceAdapters
import SchedulingAdapters

final class DeckMemoryOutlookTests: XCTestCase {
    private struct ConstantEstimator: MemoryEstimating {
        func recallProbability(state: ScheduleState, now: Date, settings: StudySettings) -> Double? { 0.91 }
    }

    func testOlderDeckWithoutTargetStillDecodes() throws {
        let data = Data(#"{"id":"deck","name":"Cloud","deleted":false}"#.utf8)
        let deck = try JSONDecoder().decode(Deck.self, from: data)
        XCTAssertNil(deck.desiredRetention)
    }

    func testOutlookUsesDeckTargetAndAccountsForAllCards() throws {
        let now = Date(timeIntervalSince1970: 1_788_393_600)
        var library = LibrarySnapshot()
        var deck = Deck(id: "deck", name: "Cloud")
        deck.desiredRetention = 0.95
        library.decks = [deck]
        library.notes = [Note(id: "one", deckID: deck.id, kind: .basic, front: "What is S3?", back: "Object storage"),
                         Note(id: "two", deckID: deck.id, kind: .basic, front: "What is EC2?", back: "Compute")]
        let initial = try FSRSScheduler().initialState(now: now, settings: library.settings)
        var reviewed = initial
        reviewed.phase = .review
        library.cards = [StudyCard(id: "studied", noteID: "one", deckID: deck.id, schedule: reviewed),
                         StudyCard(id: "new", noteID: "two", deckID: deck.id, schedule: initial)]
        let outlook = DeckMemoryOutlook.make(deck: deck, library: library, now: now, estimator: ConstantEstimator())
        XCTAssertEqual(outlook.target, 0.95)
        XCTAssertFalse(outlook.inheritsTarget)
        XCTAssertEqual(outlook.aboveTarget, 0)
        XCTAssertEqual(outlook.belowTarget, 1)
        XCTAssertEqual(outlook.newCount, 1)
        XCTAssertEqual(outlook.average.count, 8)
        XCTAssertEqual(outlook.cards.first?.prompt, "What is S3?")
        let activity = ActivitySummary.make(in: library, period: .all, now: now, estimator: ConstantEstimator())
        XCTAssertEqual(activity.decks.first?.counts[.belowTarget], 1)
    }

    func testDeckRetentionPersistsAndCanReturnToDefault() async throws {
        let app = StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())
        let deck = try await app.createDeck(name: "Cloud")
        try await app.setDeckRetention(id: deck.id, desiredRetention: 0.94)
        var snapshot = try await app.snapshot()
        XCTAssertEqual(snapshot.decks.first?.desiredRetention, 0.94)
        try await app.setDeckRetention(id: deck.id, desiredRetention: nil)
        snapshot = try await app.snapshot()
        XCTAssertNil(snapshot.decks.first?.desiredRetention)
        do { try await app.setDeckRetention(id: deck.id, desiredRetention: 1.0); XCTFail("Expected invalid target") }
        catch {
            snapshot = try await app.snapshot()
            XCTAssertNil(snapshot.decks.first?.desiredRetention)
        }
    }
}
