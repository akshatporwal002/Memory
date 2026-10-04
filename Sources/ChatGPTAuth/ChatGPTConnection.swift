import Foundation
import Observation

public enum ChatGPTConnectionState: String,Sendable { case disconnected,connecting,connected,permissionMissing,expired,error }

@MainActor public protocol ChatGPTCallbackListening: AnyObject {
    func start() async throws -> URL
    func authorize(_ attempt: OAuthAttempt, openBrowser: @MainActor (URL) throws -> Void,
                   authorizationURL: URL) async throws -> OAuthCallback
    func cancel()
}

/// Lives once per app model; credentials never enter the study model or its backups.
@MainActor @Observable public final class ChatGPTConnection {
    public private(set) var registrations: [ChatGPTRegistration] = []
    public private(set) var activeClientID: String?
    public private(set) var busy = false
    public private(set) var signingIn = false
    public private(set) var waitingForBrowser = false
    public var error: String?
    public var notice: String?
    public var showPlanConfirmation = false
    @ObservationIgnored private var vault = ChatGPTVault()
    @ObservationIgnored private let storage: any ChatGPTCredentialStorage
    @ObservationIgnored private let client: ChatGPTOAuthClient
    @ObservationIgnored private let makeListener: @MainActor () -> any ChatGPTCallbackListening
    @ObservationIgnored private let makeAttempt: @MainActor (URL, String, ChatGPTRegistration?) throws -> OAuthAttempt
    @ObservationIgnored private var listener: (any ChatGPTCallbackListening)?
    @ObservationIgnored private var signInTask: Task<Void, Never>?
    @ObservationIgnored private var storageReady = false

    public var activeAccount: ChatGPTRegistration? { registrations.first { $0.clientID == activeClientID } }
    public var state: ChatGPTConnectionState {
        if signingIn { return .connecting }
        if error != nil { return .error }
        guard let account = activeAccount else { return .disconnected }
        guard let credentials = account.credentials else { return .expired }
        if !account.planUsageEnabled { return .permissionMissing }
        if credentials.expiresAt <= Date() { return .expired }
        return .connected
    }
    public func renewSession() async {
        error = nil
        do { _ = try await validAccessToken() } catch { self.error = error.localizedDescription }
    }

    public init(storage: any ChatGPTCredentialStorage, client: ChatGPTOAuthClient,
                makeListener: @escaping @MainActor () -> any ChatGPTCallbackListening,
                makeAttempt: @escaping @MainActor (URL, String, ChatGPTRegistration?) throws -> OAuthAttempt) {
        self.storage = storage; self.client = client; self.makeListener = makeListener; self.makeAttempt = makeAttempt
        do {
            vault = try storage.load() ?? ChatGPTVault()
            vault.normalizeRegistrations()
            try storage.save(vault)
            storageReady = true; publish()
        } catch { self.error = ChatGPTAuthError.secureStorageUnavailable.localizedDescription }
    }

    public func signIn(registrationID: String? = nil, openBrowser: @escaping @MainActor (URL) throws -> Void) {
        guard !busy, storageReady else { return }
        let previous = registrationID.flatMap { id in vault.registrations.first { $0.clientID == id } }
        guard registrationID == nil || previous != nil else { return }
        busy = true; signingIn = true; error = nil; notice = nil
        signInTask = Task {
            defer { listener?.cancel(); listener = nil; busy = false; signingIn = false; waitingForBrowser = false; signInTask = nil }
            do {
                let callbackListener = makeListener(); listener = callbackListener
                let redirectURI = try await callbackListener.start()
                try Task.checkCancellation()
                let attempt = try makeAttempt(redirectURI, vault.hostID, previous)
                let authorizationURL = try await client.authorizationURL(for: attempt)
                try Task.checkCancellation()
                waitingForBrowser = true
                let callback = try await callbackListener.authorize(attempt, openBrowser: openBrowser, authorizationURL: authorizationURL)
                waitingForBrowser = false
                try Task.checkCancellation()
                let registration = try await client.exchange(callback, attempt: attempt)
                try Task.checkCancellation()
                var updated = vault
                try updated.accept(registration)
                try persist(updated)
                showPlanConfirmation = activeAccount?.planUsageEnabled == true && activeAccount?.acknowledgedPlanUsage == false
                if !registration.planUsageEnabled { notice = "Account connected. ChatGPT plan usage was not granted." }
            } catch is CancellationError { notice = "Sign-in cancelled." }
            catch ChatGPTAuthError.cancelled { notice = "Sign-in cancelled." }
            catch { self.error = (error as? ChatGPTAuthError ?? .requestFailed).localizedDescription }
        }
    }

    public func cancelSignIn() { signInTask?.cancel(); listener?.cancel() }

    public func selectAccount(_ clientID: String) {
        guard !busy, vault.registrations.contains(where: { $0.clientID == clientID && $0.credentials != nil }) else { return }
        do { var updated = vault; updated.activeClientID = clientID; try persist(updated); error = nil; notice = nil }
        catch { self.error = ChatGPTAuthError.secureStorageUnavailable.localizedDescription }
    }

    public func acknowledgePlanUsage() {
        guard let id = activeClientID, let index = vault.registrations.firstIndex(where: { $0.clientID == id }) else { return }
        do { var updated = vault; updated.registrations[index].acknowledgedPlanUsage = true; try persist(updated); showPlanConfirmation = false }
        catch { self.error = ChatGPTAuthError.secureStorageUnavailable.localizedDescription }
    }

    public func signOut() async {
        guard !busy, let account = activeAccount else { return }
        busy = true; error = nil; notice = nil
        defer { busy = false }
        var revoked = false
        for attempt in 0..<2 {
            do { try await client.revoke(account); revoked = true; break }
            catch { if attempt == 0 { try? await Task.sleep(nanoseconds: 500_000_000) } }
        }
        do {
            var updated = vault
            updated.registrations.removeAll { $0.subject == account.subject }
            updated.activeClientID = nil
            try persist(updated)
            notice = revoked ? "Signed out of ChatGPT on this device." :
                "Signed out on this device. Remote revocation was not confirmed; disconnect Engram in ChatGPT settings to remove access."
        } catch { self.error = ChatGPTAuthError.secureStorageUnavailable.localizedDescription }
    }

    /// Future AI adapters use this gate. Main-actor busy state serializes rotating-token refreshes.
    public func signOutAll() async {
        guard !busy else { return }
        busy = true; error = nil; defer { busy = false }
        var revoked = true
        for account in vault.registrations where account.credentials != nil {
            do { try await client.revoke(account) } catch { revoked = false }
        }
        do {
            var updated = vault; updated.registrations = []; updated.activeClientID = nil
            try persist(updated); showPlanConfirmation = false
            notice = revoked ? "All ChatGPT accounts disconnected on this device." : "Disconnected on this device. Remove Engram access in ChatGPT settings if remote revocation was not completed."
        } catch { self.error = ChatGPTAuthError.secureStorageUnavailable.localizedDescription }
    }

    public func validAccessToken(now: Date = Date()) async throws -> String {
        guard storageReady, !busy, let account = activeAccount, let credentials = account.credentials else { throw ChatGPTAuthError.signInRequired }
        guard account.planUsageEnabled else { throw ChatGPTAuthError.planPermissionMissing }
        if credentials.expiresAt > now.addingTimeInterval(60) { return credentials.accessToken }
        busy = true; defer { busy = false }
        let refreshed = try await client.refresh(account, now: now)
        var updated = vault
        guard let index = updated.registrations.firstIndex(where: { $0.clientID == account.clientID }) else { throw ChatGPTAuthError.signInRequired }
        updated.registrations[index] = refreshed
        try persist(updated)
        guard refreshed.planUsageEnabled, let token = refreshed.credentials?.accessToken else { throw ChatGPTAuthError.planPermissionMissing }
        return token
    }

    private func persist(_ updated: ChatGPTVault) throws {
        try storage.save(updated); vault = updated; publish()
    }
    private func publish() { registrations = vault.registrations; activeClientID = vault.activeClientID }
}

#if canImport(Security) && canImport(Network) && canImport(CryptoKit)
extension ChatGPTConnection {
    public static func live() -> ChatGPTConnection {
        ChatGPTConnection(storage: KeychainChatGPTStorage(),
            client: ChatGPTOAuthClient(transport: OpenAIHTTPTransport(), verifier: OpenAIIDTokenVerifier()),
            makeListener: { LoopbackChatGPTListener() },
            makeAttempt: { try OAuthAttempt.secure(redirectURI: $0, hostID: $1, registration: $2) })
    }
}
#endif
