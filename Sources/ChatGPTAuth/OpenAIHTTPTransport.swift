import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class NoOAuthRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor public final class OpenAIHTTPTransport: ChatGPTHTTPTransport {
    private let session: URLSession
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: NoOAuthRedirects(), delegateQueue: nil)
    }
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, ChatGPTOAuth.trustedEndpoint(url) else { throw ChatGPTAuthError.invalidConfiguration }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ChatGPTAuthError.requestFailed }
        return (data, response)
    }
}
