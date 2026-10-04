import Foundation

public enum VoiceBillingEnvironment: String, Codable, Sendable { case sandbox, production }
public enum VoiceAudioPurpose: String, Codable, Sendable { case transcription, speechOutput }

/// Supplied by verified StoreKit transactions or an authenticated backend, never
/// loaded from a library backup or editable application preferences.
public struct VoiceEntitlement: Sendable {
    public let accountID: String
    public let environment: VoiceBillingEnvironment
    public let expiresAt: Date
    public let revoked: Bool
    public init(accountID: String, environment: VoiceBillingEnvironment, expiresAt: Date, revoked: Bool = false) {
        self.accountID = accountID; self.environment = environment; self.expiresAt = expiresAt; self.revoked = revoked
    }
}
public struct VoiceAudioDisclosure: Codable, Equatable, Sendable {
    public let accountID: String
    public let provider: String
    public let purpose: VoiceAudioPurpose
    public let revision: Int
    public init(accountID: String, provider: String, purpose: VoiceAudioPurpose, revision: Int) {
        self.accountID = accountID; self.provider = provider; self.purpose = purpose; self.revision = revision
    }
}

/// An authenticated server response, bound to one operation and rate version.
/// This is an authorization reference, not a client-maintained credit balance.
public struct VoiceUsageReservation: Codable, Equatable, Sendable {
    public let id: String
    public let operationID: String
    public let accountID: String
    public let provider: String
    public let model: String
    public let purpose: VoiceAudioPurpose
    public let environment: VoiceBillingEnvironment
    public let rateVersion: String
    public let expiresAt: Date
    public init(id: String, operationID: String, accountID: String, provider: String, model: String,
                purpose: VoiceAudioPurpose, environment: VoiceBillingEnvironment, rateVersion: String, expiresAt: Date) {
        self.id = id; self.operationID = operationID; self.accountID = accountID; self.provider = provider
        self.model = model; self.purpose = purpose; self.environment = environment
        self.rateVersion = rateVersion; self.expiresAt = expiresAt
    }
}

public struct VoiceAccessRequest: Sendable {
    public let accountID: String
    public let operationID: String
    public let provider: String
    public let model: String
    public let purpose: VoiceAudioPurpose
    public let billingPath: VoiceBillingPath
    public init(accountID: String, operationID: String, provider: String, model: String,
                purpose: VoiceAudioPurpose = .transcription, billingPath: VoiceBillingPath) {
        self.accountID = accountID; self.operationID = operationID; self.provider = provider
        self.model = model; self.purpose = purpose; self.billingPath = billingPath
    }
}

/// Release configuration belongs to the composition root. Enabling this client
/// gate never bypasses server verification or authorizes a production purchase.
public struct VoiceAccessPolicy: Sendable {
    public let environment: VoiceBillingEnvironment
    public let productionEnabled: Bool
    public let managedConfigured: Bool
    public let disclosureRevision: Int
    public init(environment: VoiceBillingEnvironment, productionEnabled: Bool = false,
                managedConfigured: Bool = false, disclosureRevision: Int = 1) {
        self.environment = environment; self.productionEnabled = productionEnabled
        self.managedConfigured = managedConfigured; self.disclosureRevision = disclosureRevision
    }
    public func authorize(_ request: VoiceAccessRequest, entitlement: VoiceEntitlement?,
                          disclosure: VoiceAudioDisclosure?, keyAvailable: Bool,
                          reservation: VoiceUsageReservation?, now: Date = Date()) throws {
        guard !request.accountID.isEmpty, !request.operationID.isEmpty, !request.provider.isEmpty,
              !request.model.isEmpty, now.timeIntervalSince1970.isFinite, disclosureRevision > 0 else {
            throw EngramError.invalid("Voice configuration is incomplete.")
        }
        guard environment != .production || productionEnabled else {
            throw EngramError.invalid("Production voice access is not configured yet.")
        }
        if request.billingPath != .local {
            guard let disclosure, disclosure.accountID == request.accountID,
                  disclosure.provider == request.provider, disclosure.purpose == request.purpose,
                  disclosure.revision == disclosureRevision else {
                throw EngramError.invalid("Review where your audio will be sent before using this provider.")
            }
        }
        switch request.billingPath {
        case .local, .personalKey:
            guard request.billingPath != .local || request.provider == "local" else {
                throw EngramError.invalid("The selected provider does not use the local audio path.")
            }
            guard let entitlement, entitlement.accountID == request.accountID,
                  entitlement.environment == environment, !entitlement.revoked,
                  entitlement.expiresAt.timeIntervalSince1970.isFinite, entitlement.expiresAt > now else {
                throw EngramError.invalid("An active voice subscription is required. Restore purchases or continue with manual study.")
            }
            if request.billingPath == .personalKey && !keyAvailable {
                throw EngramError.invalid("Add a personal API key for the selected audio provider.")
            }
            // Deliberately ignore reservations: personal/local calls cannot spend
            // managed credits, even if the caller also has a funded wallet.
        case .managedCredits:
            guard managedConfigured else { throw EngramError.invalid("Managed voice is not configured yet.") }
            guard let reservation, !reservation.id.isEmpty, reservation.operationID == request.operationID,
                  reservation.accountID == request.accountID, reservation.provider == request.provider,
                  reservation.model == request.model, reservation.purpose == request.purpose,
                  reservation.environment == environment, !reservation.rateVersion.isEmpty,
                  reservation.expiresAt.timeIntervalSince1970.isFinite, reservation.expiresAt > now else {
                throw EngramError.invalid("Reserve sufficient voice credit before processing this answer.")
            }
        }
    }
}

/// Implementations authenticate the account server-side. Responses cannot mint
/// credit locally, and managed submission must revalidate the reservation.
public protocol VoiceBillingBackend: Sendable {
    func entitlement() async throws -> VoiceEntitlement?
    /// Idempotent by Apple transaction ID. Verify signature, bundle, product,
    /// environment and app-account binding before returning an acknowledgement.
    func verifyPurchase(_ submission: VoicePurchaseSubmission) async throws -> VoicePurchaseAcknowledgement
    func reserve(_ request: VoiceAccessRequest, maximumAudioBytes: Int) async throws -> VoiceUsageReservation
    func release(reservationID: String, operationID: String) async throws
    func settle(reservationID: String, operationID: String) async throws
}

public struct VoicePurchaseSubmission: Sendable {
    public let accountID: UUID
    public let transactionID: String
    public let productID: String
    public let environment: VoiceBillingEnvironment
    public let signedTransaction: String
    public init(accountID: UUID, transactionID: String, productID: String,
                environment: VoiceBillingEnvironment, signedTransaction: String) {
        self.accountID = accountID; self.transactionID = transactionID; self.productID = productID
        self.environment = environment; self.signedTransaction = signedTransaction
    }
}
public struct VoicePurchaseAcknowledgement: Sendable {
    public let accountID: UUID
    public let transactionID: String
    public let environment: VoiceBillingEnvironment
    public init(accountID: UUID, transactionID: String, environment: VoiceBillingEnvironment) {
        self.accountID = accountID; self.transactionID = transactionID; self.environment = environment
    }
}
