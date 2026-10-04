import Foundation

extension ChatGPTVault {
    /// All registrations in this vault have their issuer verified against ChatGPTOAuth.issuer.
    /// Email is display metadata; the issuer's subject is the account identity.
    mutating func normalizeRegistrations() {
        var accounts: [String: ChatGPTRegistration] = [:]
        var order: [String] = []
        for candidate in registrations where candidate.credentials != nil {
            if let current = accounts[candidate.subject] {
                let preferred = candidate.clientID == activeClientID ||
                    (current.clientID != activeClientID && candidate.credentials!.expiresAt > current.credentials!.expiresAt)
                var retained = preferred ? candidate : current
                retained.acknowledgedPlanUsage = current.acknowledgedPlanUsage || candidate.acknowledgedPlanUsage
                accounts[candidate.subject] = retained
            } else {
                order.append(candidate.subject); accounts[candidate.subject] = candidate
            }
        }
        registrations = order.compactMap { accounts[$0] }
        if !registrations.contains(where: { $0.clientID == activeClientID }) { activeClientID = nil }
    }

    mutating func accept(_ registration: ChatGPTRegistration) throws {
        if let reused = registrations.first(where: { $0.clientID == registration.clientID }), reused.subject != registration.subject {
            throw ChatGPTAuthError.invalidIdentity
        }
        var replacement = registration
        replacement.acknowledgedPlanUsage = registrations.contains { $0.subject == registration.subject && $0.acknowledgedPlanUsage }
        registrations.removeAll { $0.subject == registration.subject || $0.clientID == registration.clientID }
        registrations.append(replacement); activeClientID = replacement.clientID
        normalizeRegistrations()
    }
}
