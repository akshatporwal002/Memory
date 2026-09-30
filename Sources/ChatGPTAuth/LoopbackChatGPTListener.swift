#if canImport(Network)
import Foundation
import Network

/// Binds only IPv4 loopback, using an ephemeral port and a five-minute deadline.
@MainActor public final class LoopbackChatGPTListener: ChatGPTCallbackListening {
    private var listener: NWListener?
    private var startContinuation: CheckedContinuation<URL, Error>?
    private var callbackContinuation: CheckedContinuation<OAuthCallback, Error>?
    private var attempt: OAuthAttempt?
    private var timeout: Task<Void, Never>?
    private var connections: [UUID: NWConnection] = [:]
    public init() {}

    public func start() async throws -> URL {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        parameters.allowLocalEndpointReuse = false
        let server: NWListener
        do { server = try NWListener(using: parameters, on: .any) }
        catch { throw ChatGPTAuthError.listenerUnavailable }
        listener = server
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                startContinuation = continuation
                server.stateUpdateHandler = { [weak self] state in
                    Task { @MainActor in
                        guard let self else { return }
                        switch state {
                        case .ready:
                            guard let port = server.port else { self.finish(.failure(ChatGPTAuthError.listenerUnavailable)); return }
                            let continuation = self.startContinuation; self.startContinuation = nil
                            continuation?.resume(returning: URL(string: "http://127.0.0.1:\(port.rawValue)/auth/callback")!)
                        case .failed: self.finish(.failure(ChatGPTAuthError.listenerUnavailable))
                        default: break
                        }
                    }
                }
                server.newConnectionHandler = { [weak self] connection in
                    Task { @MainActor in self?.accept(connection) }
                }
                server.start(queue: .main)
                timeout = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 300_000_000_000); self?.finish(.failure(ChatGPTAuthError.timedOut)) }
                    catch { }
                }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.cancel() } }
    }

    public func authorize(_ attempt: OAuthAttempt, openBrowser: @MainActor (URL) throws -> Void,
                          authorizationURL: URL) async throws -> OAuthCallback {
        guard listener != nil else { throw ChatGPTAuthError.cancelled }
        self.attempt = attempt
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                callbackContinuation = continuation
                do { try openBrowser(authorizationURL) }
                catch { finish(.failure(ChatGPTAuthError.browserUnavailable)) }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.cancel() } }
    }

    public func cancel() { finish(.failure(ChatGPTAuthError.cancelled)) }

    private func accept(_ connection: NWConnection) {
        guard connections.count < 8 else { connection.cancel(); return }
        let id = UUID(); connections[id] = connection
        connection.start(queue: .main)
        receive(connection, id: id, buffer: Data())
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            self?.connections.removeValue(forKey: id)?.cancel()
        }
    }
    private func receive(_ connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.connections[id] != nil else { return }
                let received = buffer + (data ?? Data())
                guard received.count <= 16_384 else { self.respond(connection, id: id, status: "400 Bad Request", message: "Invalid request."); return }
                if let text = String(data: received, encoding: .utf8), text.contains("\r\n\r\n") {
                    self.handle(text, connection: connection, id: id)
                } else if complete || error != nil { self.connections.removeValue(forKey: id)?.cancel() }
                else { self.receive(connection, id: id, buffer: received) }
            }
        }
    }
    private func handle(_ text: String, connection: NWConnection, id: UUID) {
        guard let attempt, let first = text.components(separatedBy: "\r\n").first else {
            respond(connection, id: id, status: "404 Not Found", message: "No sign-in is waiting."); return
        }
        let line = first.split(separator: " ").map(String.init)
        guard line.count == 3, line[0] == "GET", line[1].hasPrefix("/auth/callback?"),
              let url = URL(string: "http://127.0.0.1:\(attempt.redirectURI.port!)" + line[1]) else {
            respond(connection, id: id, status: "404 Not Found", message: "Not found."); return
        }
        do {
            let callback = try attempt.callback(url)
            respond(connection, id: id, status: "200 OK", message: "Sign-in received. Return to Engram to finish connecting.")
            finish(.success(callback), preserving: id)
        } catch ChatGPTAuthError.denied {
            respond(connection, id: id, status: "200 OK", message: "Access was not granted. Return to Engram.")
            finish(.failure(ChatGPTAuthError.denied), preserving: id)
        } catch {
            // Wrong-state/unsolicited requests must not end the legitimate authorization attempt.
            respond(connection, id: id, status: "400 Bad Request", message: "This callback could not be verified.")
        }
    }
    private func respond(_ connection: NWConnection, id: UUID, status: String, message: String) {
        let body = "<!doctype html><html><head><meta name=viewport content='width=device-width, initial-scale=1'><title>Engram</title></head><body><h1>Engram</h1><p>\(message)</p></body></html>"
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'none'\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] _ in
            connection.cancel()
            Task { @MainActor in self?.connections.removeValue(forKey: id) }
        })
    }
    private func finish(_ result: Result<OAuthCallback, Error>, preserving id: UUID? = nil) {
        let starting = startContinuation; startContinuation = nil
        let waiting = callbackContinuation; callbackContinuation = nil
        if let starting { starting.resume(throwing: result.failure ?? ChatGPTAuthError.cancelled) }
        waiting?.resume(with: result)
        listener?.cancel(); listener = nil; attempt = nil; timeout?.cancel(); timeout = nil
        for (key, connection) in connections where key != id { connection.cancel() }
        connections = connections.filter { $0.key == id }
    }
}

private extension Result where Success == OAuthCallback, Failure == Error {
    var failure: Error? { if case .failure(let error) = self { return error }; return nil }
}
#endif
