import Foundation
import XCTest
@testable import ChatGPTAuth

final class RegistrationLifecycleTests: XCTestCase {
    private func account(_ client: String, subject: String = "owner", email: String = "same@example.com", expiry: Double = 2000) -> ChatGPTRegistration {
        ChatGPTRegistration(clientID: client, subject: subject, email: email, credentials:
            ChatGPTCredentials(accessToken: "fixture", refreshToken: "fixture", idToken: "fixture",
                scopes: ["chatgpt.tokens.use.direct", "resource.invoke"], expiresAt: Date(timeIntervalSince1970: expiry)))
    }
    func testMigrationKeepsActiveIdentityAndRemovesDisconnectedHistory() {
        var vault = ChatGPTVault()
        var stale = account("stale"); stale.credentials = nil
        var older = account("older"); older.acknowledgedPlanUsage = true
        vault.registrations = [stale, older, account("active", expiry: 1000), account("other", subject: "other")]
        vault.activeClientID = "active"; vault.normalizeRegistrations()
        XCTAssertEqual(vault.registrations.map(\.clientID), ["active", "other"])
        XCTAssertTrue(vault.registrations[0].acknowledgedPlanUsage)
        XCTAssertEqual(vault.activeClientID, "active")
    }
    func testFreshSignInsReplaceSameSubjectWithoutStacking() throws {
        var vault = ChatGPTVault()
        for index in 0..<5 { try vault.accept(account("client-\(index)")) }
        XCTAssertEqual(vault.registrations.count, 1)
        XCTAssertEqual(vault.activeClientID, "client-4")
    }
    func testSameEmailDoesNotMergeDifferentSubjects() throws {
        var vault = ChatGPTVault()
        try vault.accept(account("one")); try vault.accept(account("two", subject: "different"))
        XCTAssertEqual(vault.registrations.count, 2)
    }
    func testReusingClientForAnotherIdentityIsRejected() throws {
        var vault = ChatGPTVault(); try vault.accept(account("one"))
        XCTAssertThrowsError(try vault.accept(account("one", subject: "different")))
        XCTAssertEqual(vault.registrations[0].subject, "owner")
    }
    func testMigrationDoesNotSelectAnotherAccountAfterSignOut() {
        var vault = ChatGPTVault(); var stale = account("stale"); stale.credentials = nil
        vault.registrations = [stale, account("other", subject: "other")]; vault.activeClientID = "stale"
        vault.normalizeRegistrations(); XCTAssertNil(vault.activeClientID)
        XCTAssertEqual(vault.registrations.count, 1)
    }
}
