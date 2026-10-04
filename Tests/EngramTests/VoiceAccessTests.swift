import XCTest
import LearningCore

final class VoiceAccessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_393_600)
    private func request(path: VoiceBillingPath = .personalKey, operation: String = "job", model: String = "mini") -> VoiceAccessRequest {
        VoiceAccessRequest(accountID: "account", operationID: operation, provider: path == .local ? "local" : "openai",
            model: model, billingPath: path)
    }
    private var disclosure: VoiceAudioDisclosure {
        VoiceAudioDisclosure(accountID: "account", provider: "openai", purpose: .transcription, revision: 1)
    }
    private func subscription(environment: VoiceBillingEnvironment = .sandbox, account: String = "account", revoked: Bool = false, expired: Bool = false) -> VoiceEntitlement {
        VoiceEntitlement(accountID: account, environment: environment,
            expiresAt: now.addingTimeInterval(expired ? -1 : 60), revoked: revoked)
    }
    private func reservation(environment: VoiceBillingEnvironment = .sandbox) -> VoiceUsageReservation {
        VoiceUsageReservation(id: "server-reservation", operationID: "job", accountID: "account", provider: "openai",
            model: "mini", purpose: .transcription, environment: environment, rateVersion: "verified-rate-v1", expiresAt: now.addingTimeInterval(60))
    }
    func testProductionRemainsDisabledEvenWithValidCredentialsAndSubscription() {
        let policy = VoiceAccessPolicy(environment: .production)
        XCTAssertThrowsError(try policy.authorize(request(), entitlement: subscription(environment: .production),
            disclosure: disclosure, keyAvailable: true, reservation: nil, now: now))
    }
    func testPersonalAndLocalRequireMatchingActiveSubscriptionWithoutManagedReservation() throws {
        let policy = VoiceAccessPolicy(environment: .sandbox)
        try policy.authorize(request(), entitlement: subscription(), disclosure: disclosure, keyAvailable: true, reservation: nil, now: now)
        try policy.authorize(request(path: .local), entitlement: subscription(), disclosure: nil, keyAvailable: false, reservation: nil, now: now)
        for entitlement in [nil, subscription(account: "other"), subscription(revoked: true), subscription(expired: true), subscription(environment: .production)] {
            XCTAssertThrowsError(try policy.authorize(request(), entitlement: entitlement,
                disclosure: disclosure, keyAvailable: true, reservation: reservation(), now: now))
        }
        XCTAssertThrowsError(try policy.authorize(request(), entitlement: subscription(),
            disclosure: disclosure, keyAvailable: false, reservation: reservation(), now: now))
    }
    func testDisclosureIsBoundToAccountProviderPurposeAndRevision() {
        let policy = VoiceAccessPolicy(environment: .sandbox)
        for value in [nil,
            VoiceAudioDisclosure(accountID: "other", provider: "openai", purpose: .transcription, revision: 1),
            VoiceAudioDisclosure(accountID: "account", provider: "gemini", purpose: .transcription, revision: 1),
            VoiceAudioDisclosure(accountID: "account", provider: "openai", purpose: .speechOutput, revision: 1),
            VoiceAudioDisclosure(accountID: "account", provider: "openai", purpose: .transcription, revision: 0)] {
            XCTAssertThrowsError(try policy.authorize(request(), entitlement: subscription(),
                disclosure: value, keyAvailable: true, reservation: nil, now: now))
        }
    }
    func testManagedNeedsConfiguredBackendAndOperationBoundReservationNotSubscription() throws {
        let policy = VoiceAccessPolicy(environment: .sandbox, managedConfigured: true)
        try policy.authorize(request(path: .managedCredits), entitlement: nil, disclosure: disclosure,
            keyAvailable: false, reservation: reservation(), now: now)
        XCTAssertThrowsError(try VoiceAccessPolicy(environment: .sandbox).authorize(request(path: .managedCredits),
            entitlement: subscription(), disclosure: disclosure, keyAvailable: true, reservation: reservation(), now: now))
        for value in [nil, reservation(environment: .production)] {
            XCTAssertThrowsError(try policy.authorize(request(path: .managedCredits), entitlement: subscription(),
                disclosure: disclosure, keyAvailable: true, reservation: value, now: now))
        }
        for selected in [request(path: .managedCredits, operation: "other-job"), request(path: .managedCredits, model: "full")] {
            XCTAssertThrowsError(try policy.authorize(selected, entitlement: nil, disclosure: disclosure,
                keyAvailable: false, reservation: reservation(), now: now))
        }
        XCTAssertThrowsError(try policy.authorize(request(path: .managedCredits), entitlement: nil, disclosure: disclosure,
            keyAvailable: false, reservation: reservation(), now: now.addingTimeInterval(120)))
    }
    func testCloudProviderCannotPretendToBeLocalAndAvoidDisclosure() {
        let selected = VoiceAccessRequest(accountID: "account", operationID: "job", provider: "openai", model: "mini", billingPath: .local)
        XCTAssertThrowsError(try VoiceAccessPolicy(environment: .sandbox).authorize(selected, entitlement: subscription(),
            disclosure: nil, keyAvailable: true, reservation: nil, now: now))
    }
    func testTranscriptionConsentCannotAuthorizeSpeechOutputOrSpendManagedCredits() throws {
        let selected = VoiceAccessRequest(accountID: "account", operationID: "speech", provider: "openai",
            model: "gpt-4o-mini-tts", purpose: .speechOutput, billingPath: .personalKey)
        let policy = VoiceAccessPolicy(environment: .sandbox)
        XCTAssertThrowsError(try policy.authorize(selected, entitlement: subscription(),
            disclosure: disclosure, keyAvailable: true, reservation: reservation(), now: now))
        let outputConsent = VoiceAudioDisclosure(accountID: "account", provider: "openai", purpose: .speechOutput, revision: 1)
        try policy.authorize(selected, entitlement: subscription(), disclosure: outputConsent,
            keyAvailable: true, reservation: nil, now: now)
        XCTAssertThrowsError(try policy.authorize(selected, entitlement: subscription(), disclosure: outputConsent,
            keyAvailable: false, reservation: reservation(), now: now))
        XCTAssertThrowsError(try VoiceAccessPolicy(environment: .production).authorize(selected,
            entitlement: subscription(environment: .production), disclosure: outputConsent,
            keyAvailable: true, reservation: nil, now: now))
    }
}
