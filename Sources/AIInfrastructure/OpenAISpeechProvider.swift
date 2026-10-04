import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Personal API speech transport. Callers must obtain disclosure/entitlement approval
/// before dispatch; this adapter never switches billing paths or retries a request.
public struct OpenAISpeechProvider: TranscriptionProvider, SpeechOutputProvider {
    public let id = "openai"
    private let transport: any SpeechHTTPTransport
    public init() { transport = SpeechHTTPClient() }
    init(transport: any SpeechHTTPTransport) { self.transport = transport }
    public static let transcriptionModels = ["gpt-4o-mini-transcribe", "gpt-4o-transcribe", "whisper-1"]
    public static let outputModels = ["gpt-4o-mini-tts", "tts-1", "tts-1-hd"]
    public static let voices = ["alloy", "ash", "ballad", "coral", "echo", "fable", "onyx", "nova", "sage", "shimmer", "verse", "marin", "cedar"]

    public func transcribe(audio: Data, format: RecordingFormat, model: String, language: String? = nil, token: String, requestID: UUID) async throws -> SpeechTranscription {
        let request = try Self.transcriptionRequest(audio: audio, format: format, model: model, language: language, token: token, requestID: requestID)
        let response = try await transport.send(request, responseLimit: 128_000)
        try Task.checkCancellation()
        guard (200...299).contains(response.status) else { throw SpeechServiceError.unavailable(response.status) }
        return try Self.decodeTranscription(response.data)
    }
    static func transcriptionRequest(audio: Data, format: RecordingFormat, model: String, language: String?, token: String, requestID: UUID) throws -> URLRequest {
        guard transcriptionModels.contains(model) else { throw SpeechServiceError.unsupported }
        guard !audio.isEmpty, audio.count <= 25_000_000 else { throw SpeechServiceError.tooLarge }
        if let language { guard language.count == 2, language.utf8.allSatisfy({ (97...122).contains($0) }) else { throw SpeechServiceError.invalidInput } }
        let boundary = "engram-" + UUID().uuidString
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        func field(_ name: String, _ value: String) {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        field("model", model); field("response_format", "json")
        if let language { field("language", language) }
        // Never supply the expected card answer as a transcription prompt.
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"answer.\(format.rawValue)\"\r\nContent-Type: \(format.mime)\r\n\r\n")
        body.append(audio); append("\r\n--\(boundary)--\r\n")
        var request = try authorized(path: "transcriptions", token: token, requestID: requestID)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body; return request
    }
    static func decodeTranscription(_ data: Data) throws -> SpeechTranscription {
        guard data.count <= 128_000,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], root["error"] == nil,
              let text = root["text"] as? String, text.utf8.count <= 16_000,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SpeechServiceError.malformed }
        let usage = try root["usage"].map { value in
            guard value is [String: Any] else { throw SpeechServiceError.malformed }
            return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        }
        return SpeechTranscription(text: text, usageJSON: usage)
    }
    public func synthesize(text: String, model: String = "gpt-4o-mini-tts", voice: String = "coral", token: String, requestID: UUID) async throws -> Data {
        guard Self.outputModels.contains(model), Self.voices.contains(voice) else { throw SpeechServiceError.unsupported }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 4096, text.utf8.count <= 16_000 else { throw SpeechServiceError.invalidInput }
        // Older TTS models advertise only the original six voices.
        if model != "gpt-4o-mini-tts", !["alloy", "echo", "fable", "onyx", "nova", "shimmer"].contains(voice) { throw SpeechServiceError.unsupported }
        var request = try Self.authorized(path: "speech", token: token, requestID: requestID)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "input": text, "voice": voice, "response_format": "wav"])
        let response = try await transport.send(request, responseLimit: 25_000_000)
        try Task.checkCancellation()
        guard (200...299).contains(response.status) else { throw SpeechServiceError.unavailable(response.status) }
        try VoiceWAV.validateOutput(response.data)
        return response.data
    }
    private static func authorized(path: String, token: String, requestID: UUID) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/" + path)!)
        request.httpMethod = "POST"; request.timeoutInterval = 120
        request.setValue("Bearer " + (try PersonalAPIKeyValidation.normalized(token)), forHTTPHeaderField: "Authorization")
        // Correlation only: OpenAI audio requests are not assumed idempotent.
        request.setValue(requestID.uuidString, forHTTPHeaderField: "X-Client-Request-Id")
        return request
    }
}
