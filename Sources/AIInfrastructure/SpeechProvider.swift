import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum SpeechServiceError: Error, LocalizedError {
    case invalidInput, unsupported, unavailable(Int), malformed, tooLarge, uncertainDelivery
    public var errorDescription: String? {
        switch self {
        case .invalidInput: "Check the recording or speech settings before trying again."
        case .unsupported: "This speech model or audio format is not supported."
        case .unavailable(let status): "The speech provider could not complete the request (HTTP \(status))."
        case .malformed: "The speech provider returned an unreadable result."
        case .tooLarge: "This recording or speech response is too large."
        case .uncertainDelivery: "The connection interrupted. The provider may have processed this request; retrying could incur another provider charge."
        }
    }
}

public enum RecordingFormat: String, Codable, Sendable {
    case wav, m4a, mp3, flac, ogg, webm
    var mime: String {
        switch self {
        case .wav: "audio/wav"
        case .m4a: "audio/mp4"
        case .mp3: "audio/mpeg"
        case .flac: "audio/flac"
        case .ogg: "audio/ogg"
        case .webm: "audio/webm"
        }
    }
}

public struct SpeechTranscription: Sendable, Equatable {
    public let text: String
    /// Provider-reported usage, never an estimate of the learner's correctness.
    public let usageJSON: Data?
    public init(text: String, usageJSON: Data? = nil) { self.text = text; self.usageJSON = usageJSON }
}
public protocol TranscriptionProvider: Sendable {
    var id: String { get }
    func transcribe(audio: Data, format: RecordingFormat, model: String, language: String?, token: String, requestID: UUID) async throws -> SpeechTranscription
}
public protocol SpeechOutputProvider: Sendable {
    var id: String { get }
    func synthesize(text: String, model: String, voice: String, token: String, requestID: UUID) async throws -> Data
}

struct SpeechHTTPResponse: Sendable {
    let data: Data
    let status: Int
    let contentType: String?
}
protocol SpeechHTTPTransport: Sendable {
    func send(_ request: URLRequest, responseLimit: Int) async throws -> SpeechHTTPResponse
}
struct SpeechHTTPClient: SpeechHTTPTransport {
    func send(_ request: URLRequest, responseLimit: Int) async throws -> SpeechHTTPResponse {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: SpeechRedirectBlocker(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            #if os(iOS) || os(macOS)
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw SpeechServiceError.malformed }
            guard (200...299).contains(http.statusCode) else { throw SpeechServiceError.unavailable(http.statusCode) }
            guard response.expectedContentLength <= Int64(responseLimit) else { throw SpeechServiceError.tooLarge }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < responseLimit else { throw SpeechServiceError.tooLarge }
                data.append(byte)
            }
            #else
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SpeechServiceError.malformed }
            guard (200...299).contains(http.statusCode) else { throw SpeechServiceError.unavailable(http.statusCode) }
            guard data.count <= responseLimit else { throw SpeechServiceError.tooLarge }
            #endif
            return SpeechHTTPResponse(data: data, status: http.statusCode, contentType: http.value(forHTTPHeaderField: "Content-Type"))
        } catch let error as SpeechServiceError { throw error }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw SpeechServiceError.uncertainDelivery }
    }
}
private final class SpeechRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
