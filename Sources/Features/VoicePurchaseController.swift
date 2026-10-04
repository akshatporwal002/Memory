import Foundation
import Observation
import LearningCore
#if canImport(StoreKit)
import StoreKit

/// StoreKit is an input to server verification, not a local credit ledger.
/// Product identifiers and production activation are deliberately unconfigured.
@MainActor @Observable final class VoicePurchaseController {
    struct Configuration {
        let subscriptionID: String
        let topUpID: String
        let environment: VoiceBillingEnvironment
        var productionEnabled = false
        var configured: Bool {
            #if DEBUG
            guard environment == .sandbox else { return false }
            #endif
            return !subscriptionID.isEmpty && !topUpID.isEmpty && subscriptionID != topUpID &&
            (environment != .production || productionEnabled)
        }
    }
    /// App Store Connect draft identifiers. A caller must still supply authenticated
    /// server verification; this does not grant credits or enable a purchase UI.
    static let sandboxConfiguration = Configuration(
        subscriptionID: "dev.engram.study.voice.monthly",
        topUpID: "dev.engram.study.voice.credits10",
        environment: .sandbox
    )
    typealias Verify = @Sendable (VoicePurchaseSubmission) async throws -> VoicePurchaseAcknowledgement
    private(set) var products: [Product] = []
    private(set) var busy = false
    private(set) var pending = false
    var error: String?
    @ObservationIgnored private let configuration: Configuration
    @ObservationIgnored private let verify: Verify
    @ObservationIgnored private var accountID: UUID?
    @ObservationIgnored private var epoch = UUID()
    @ObservationIgnored private var listener: Task<Void, Never>?
    init(configuration: Configuration, verify: @escaping Verify) {
        self.configuration = configuration; self.verify = verify
    }
    func selectAccount(_ id: UUID?) {
        guard id != accountID else { return }
        listener?.cancel(); listener = nil; epoch = UUID(); accountID = id
        products = []; pending = false; error = nil
        guard id != nil, configuration.configured else { return }
        let token = epoch
        listener = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self, self.epoch == token, !Task.isCancelled else { return }
                do { try await self.deliver(result, token: token) }
                catch { if self.epoch == token { self.error = "Purchase verification is pending. Restore purchases to retry." } }
            }
        }
    }
    func loadProducts() async {
        guard configuration.configured, accountID != nil, !busy else { return }
        busy = true; let token = epoch; defer { busy = false }
        do {
            let loaded = try await Product.products(for: [configuration.subscriptionID, configuration.topUpID])
            guard epoch == token else { return }
            products = loaded.filter {
                ($0.id == configuration.subscriptionID && $0.type == .autoRenewable) ||
                ($0.id == configuration.topUpID && $0.type == .consumable)
            }
            if products.count != 2 { error = "Voice purchase products are not configured in this storefront." }
        } catch { if epoch == token { self.error = "Could not load voice purchases. Try again later." } }
    }
    func purchase(_ product: Product) async {
        guard configuration.configured, let accountID, !busy,
              products.contains(where: { $0.id == product.id }) else { return }
        busy = true; pending = false; error = nil; let token = epoch; defer { busy = false }
        do {
            // Checking only the returned purchase environment is too late: a
            // sandbox-configured build must refuse a production purchase first.
            let app = try await AppTransaction.shared
            guard case .verified(let appTransaction) = app,
                  appTransaction.environment == (configuration.environment == .sandbox ? .sandbox : .production),
                  epoch == token, self.accountID == accountID else { throw EngramError.conflict }
            try Task.checkCancellation()
            switch try await product.purchase(options: [.appAccountToken(accountID)]) {
            case .success(let result): try await deliver(result, token: token)
            case .pending: if epoch == token { pending = true }
            case .userCancelled: break
            @unknown default: if epoch == token { error = "This purchase needs confirmation in the App Store." }
            }
        } catch { if epoch == token { self.error = "Purchase was not verified. No voice credit was added on this device." } }
    }
    func restore() async {
        guard configuration.configured, accountID != nil, !busy else { return }
        busy = true; error = nil; let token = epoch; defer { busy = false }
        do {
            try await AppStore.sync()
            for await result in Transaction.currentEntitlements {
                try Task.checkCancellation(); guard epoch == token else { return }
                try await deliver(result, token: token)
            }
            // Unfinished consumables are not in currentEntitlements. A finished
            // top-up is restored from the server wallet, never credited twice here.
            for await result in Transaction.unfinished {
                try Task.checkCancellation(); guard epoch == token else { return }
                try await deliver(result, token: token)
            }
        } catch { if epoch == token { self.error = "Restore needs another attempt. Your server wallet has not been replaced." } }
    }
    private func deliver(_ result: VerificationResult<Transaction>, token: UUID) async throws {
        guard epoch == token, let accountID, configuration.configured else { throw EngramError.conflict }
        guard case .verified(let transaction) = result else { throw EngramError.invalid("Unverified purchase.") }
        guard transaction.productID == configuration.subscriptionID || transaction.productID == configuration.topUpID else { return }
        guard transaction.appAccountToken == accountID else { throw EngramError.conflict }
        let environment: VoiceBillingEnvironment
        switch transaction.environment {
        case .sandbox: environment = .sandbox
        case .production: environment = .production
        default: throw EngramError.invalid("Local StoreKit fixtures cannot be submitted to hosted billing.")
        }
        guard environment == configuration.environment else { throw EngramError.conflict }
        let acknowledgement = try await verify(VoicePurchaseSubmission(accountID: accountID,
            transactionID: String(transaction.id), productID: transaction.productID,
            environment: environment, signedTransaction: result.jwsRepresentation))
        guard epoch == token, self.accountID == accountID,
              acknowledgement.accountID == accountID, acknowledgement.transactionID == String(transaction.id),
              acknowledgement.environment == environment else { throw EngramError.conflict }
        // The authenticated server must apply refunds/revocations as well as grants.
        // Finish only after acknowledgement; failed verification remains replayable.
        await transaction.finish(); pending = false
    }
}
#endif
