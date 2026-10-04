import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import AIInfrastructure

private actor SpeechFixtureTransport: SpeechHTTPTransport {
    let response: SpeechHTTPResponse
    private(set) var requests: [URLRequest] = []
    init(_ response: SpeechHTTPResponse) { self.response = response }
    func send(_ request: URLRequest, responseLimit: Int) async throws -> SpeechHTTPResponse {
        requests.append(request); return response
    }
}
final class SpeechProviderTests: XCTestCase {
    private let key = "fixture-key-not-a-secret"
    func testSpeechOutputRejectsTruncatedAndInconsistentWAVWithoutRetry() async throws {
        let valid = try VoiceWAV.encode([0, 0.5, -0.5], sampleRate: 24_000)
        var badRate = valid; badRate[28] ^= 1
        var oversizedChunk = valid; oversizedChunk[40] = 255
        let fake = Data("RIFF0000WAVE".utf8)
        for audio in [fake, Data(valid.dropLast()), badRate, oversizedChunk] {
            let transport = SpeechFixtureTransport(SpeechHTTPResponse(data: audio, status: 200, contentType: "audio/wav"))
            do {
                _ = try await OpenAISpeechProvider(transport: transport).synthesize(text: "Hello", token: key, requestID: UUID())
                XCTFail("Expected malformed audio rejection")
            } catch let error as SpeechServiceError {
                guard case .malformed = error else { XCTFail("Expected malformed audio error"); continue }
            }
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
        }
        let transport = SpeechFixtureTransport(SpeechHTTPResponse(data: valid, status: 200, contentType: "audio/wav"))
        let returned = try await OpenAISpeechProvider(transport: transport).synthesize(text: "Hello", token: key, requestID: UUID())
        XCTAssertEqual(returned, valid)
    }

    func testWAVChunkPaddingAndMetadataAreValidatedWithoutAllocatingDeclaredSizes() throws {
        let valid = try VoiceWAV.encode([0, 1], sampleRate: 24_000)
        // A legal odd-sized ancillary chunk has one padding byte.
        var withMetadata = Data(valid.prefix(12))
        withMetadata.append(Data([74, 85, 78, 75, 1, 0, 0, 0, 42, 0]))
        withMetadata.append(valid.dropFirst(12))
        withMetadata[4] = UInt8(withMetadata.count - 8)
        XCTAssertNoThrow(try VoiceWAV.validateOutput(withMetadata))
        var empty = valid; empty[40] = 0
        XCTAssertThrowsError(try VoiceWAV.validateOutput(empty))
        var invalidBits = valid; invalidBits[34] = 8
        XCTAssertThrowsError(try VoiceWAV.validateOutput(invalidBits))
        var hugeRIFF = valid; hugeRIFF.replaceSubrange(4..<8, with: [255, 255, 255, 255])
        XCTAssertThrowsError(try VoiceWAV.validateOutput(hugeRIFF))
        var duplicateFormat = Data(valid.prefix(36)); duplicateFormat.append(valid.dropFirst(12))
        duplicateFormat[4] = UInt8(duplicateFormat.count - 8)
        XCTAssertThrowsError(try VoiceWAV.validateOutput(duplicateFormat))
    }

    func testMultipartKeepsBinaryAudioAndNeverInjectsExpectedAnswers() throws {
        let audio = Data([0, 255, 13, 10, 42])
        let request = try OpenAISpeechProvider.transcriptionRequest(audio: audio, format: .wav, model: "gpt-4o-mini-transcribe", language: "en", token: key, requestID: UUID())
        XCTAssertEqual(request.url?.path, "/v1/audio/transcriptions")
        XCTAssertNil(request.url?.query)
        XCTAssertNotNil(request.httpBody?.range(of: audio))
        let body = String(decoding: request.httpBody!, as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"response_format\"\r\n\r\njson"))
        XCTAssertFalse(body.contains("name=\"prompt\""))
        XCTAssertFalse(body.contains(key))
        XCTAssertThrowsError(try OpenAISpeechProvider.transcriptionRequest(audio: audio, format: .wav, model: "chat-model", language: nil, token: key, requestID: UUID()))
        XCTAssertThrowsError(try OpenAISpeechProvider.transcriptionRequest(audio: audio, format: .wav, model: "whisper-1", language: "en\r\nheader", token: key, requestID: UUID()))
    }
    func testTranscriptPreservesMistakesAndUsageWithoutAwardingAGrade() throws {
        let result = try OpenAISpeechProvider.decodeTranscription(Data(#"{"text":"No, S3 is NOT a database. Actually, I don't know.","usage":{"total_tokens":22}}"#.utf8))
        XCTAssertEqual(result.text, "No, S3 is NOT a database. Actually, I don't know.")
        XCTAssertNotNil(result.usageJSON)
        for invalid in [#"{"text":" "}"#, #"{"text":12}"#, #"{"error":{"message":"secret"},"text":"ok"}"#, #"{"text":"ok","usage":"invalid"}"#] {
            XCTAssertThrowsError(try OpenAISpeechProvider.decodeTranscription(Data(invalid.utf8)))
        }
    }
    func testProviderErrorsDoNotRetryOrFallback() async throws {
        let transport = SpeechFixtureTransport(SpeechHTTPResponse(data: Data("private provider message".utf8), status: 429, contentType: "application/json"))
        let provider = OpenAISpeechProvider(transport: transport)
        do {
            _ = try await provider.transcribe(audio: Data([1]), format: .wav, model: "gpt-4o-mini-transcribe", token: key, requestID: UUID())
            XCTFail("Expected provider error")
        } catch {
            XCTAssertFalse(error.localizedDescription.contains("private provider"))
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
    }
    func testSpeechRejectsNonAudioAndUnsupportedModelVoicePairs() async throws {
        let transport = SpeechFixtureTransport(SpeechHTTPResponse(data: Data(#"{"error":"bad"}"#.utf8), status: 200, contentType: "application/json"))
        let provider = OpenAISpeechProvider(transport: transport)
        do { _ = try await provider.synthesize(text: "Hello", token: key, requestID: UUID()); XCTFail("Expected non-audio rejection") } catch {}
        do { _ = try await provider.synthesize(text: "Hello", model: "tts-1", voice: "coral", token: key, requestID: UUID()); XCTFail("Expected unsupported voice") } catch {}
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        let body = try JSONSerialization.jsonObject(with: requests[0].httpBody!) as! [String: String]
        XCTAssertEqual(body["response_format"], "wav")
        XCTAssertEqual(body["input"], "Hello")
    }
}
