import Foundation
import XCTest
@testable import CloudAdapters

final class PendingIdentityLinkTests: XCTestCase {
    func testPersistedCallbackOwnershipExpiresAndCannotCrossAccounts() throws {
        let user = UUID(), now = Date(timeIntervalSince1970: 2000)
        let original = PendingIdentityLink(userID: user, startedAt: now)
        let restored = try JSONDecoder().decode(PendingIdentityLink.self, from: JSONEncoder().encode(original))
        XCTAssertTrue(restored.isValid(for: user, at: now.addingTimeInterval(899)))
        XCTAssertFalse(restored.isValid(for: UUID(), at: now))
        XCTAssertFalse(restored.isValid(for: user, at: now.addingTimeInterval(901)))
        XCTAssertFalse(restored.isValid(for: user, at: now.addingTimeInterval(-1)))
    }
}
