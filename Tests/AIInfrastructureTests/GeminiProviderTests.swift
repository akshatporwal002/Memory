import Foundation
import XCTest
@testable import AIInfrastructure

final class GeminiProviderTests: XCTestCase {
    func testProviderSelectionsNeverFallbackFromMalformedOrUnknownProviders() throws {
        XCTAssertEqual(try AIProviderRegistry.descriptor("legacy-model").provider, "chatgpt")
        XCTAssertEqual(try AIProviderRegistry.descriptor("gemini:model").provider, "gemini")
        for invalid in ["", ":model", "openai:", "unknown:model", " gemini:model", "gemini: model"] {
            XCTAssertThrowsError(try AIProviderRegistry.descriptor(invalid), invalid)
        }
    }
    func testCatalogUsesAdvertisedGenerationMethodsAndSafeModelPaths() throws {
        let root: [String: Any] = ["models": [
            ["name": "models/gemini-fixture", "displayName": "Fixture", "supportedGenerationMethods": ["generateContent"]],
            ["name": "models/embedding-fixture", "supportedGenerationMethods": ["embedContent"]],
            ["name": "models/../../other", "supportedGenerationMethods": ["generateContent"]]
        ]]
        let models = try GeminiAIProvider.decodeModels(root)
        XCTAssertEqual(models.map(\.id), ["gemini:gemini-fixture"])
        XCTAssertEqual(models[0].toolSupportKnown, false)
    }
    func testInternalThoughtsAndArgumentsAreNotTextEventsAndCallsWaitForCompletion() throws {
        var decoder = GeminiStreamDecoder()
        let first = try decoder.accept(#"data: {"candidates":[{"content":{"parts":[{"text":"Internal", "thought":true},{"functionCall":{"id":"call1","name":"inspect","args":{"id":"deck"}},"thoughtSignature":"opaque"}]}}]}"#)
        XCTAssertTrue(first.isEmpty)
        XCTAssertFalse(decoder.completed)
        let final = try decoder.accept(#"data: {"candidates":[{"finishReason":"STOP"}]}"#)
        XCTAssertTrue(decoder.completed)
        XCTAssertEqual(final.last, .completed)
        XCTAssertTrue(final.contains { if case .toolCall(let call) = $0 { return call.id == "call1" }; return false })
        guard case .contextItem(let context) = final.first else { return XCTFail("Missing opaque context") }
        XCTAssertTrue(context.json.contains("opaque"))
        XCTAssertEqual(context.provider, "gemini")
    }
    func testIncompleteOrBlockedResponseCannotReleaseToolCalls() throws {
        for reason in ["MAX_TOKENS", "SAFETY", "MALFORMED_FUNCTION_CALL", "RECITATION"] {
            var decoder = GeminiStreamDecoder()
            _ = try decoder.accept(#"data: {"candidates":[{"content":{"parts":[{"functionCall":{"name":"edit","args":{"id":"deck"}}}]}}]}"#)
            XCTAssertThrowsError(try decoder.accept("data: {\"candidates\":[{\"finishReason\":\"\(reason)\"}]}"))
            XCTAssertFalse(decoder.completed)
        }
    }
    func testLocalCallIDsDoNotRewriteSignaturesOrBecomeInventedServerIDs() throws {
        var decoder = GeminiStreamDecoder()
        let events = try decoder.accept(#"data: {"candidates":[{"content":{"parts":[{"functionCall":{"name":"inspect","args":{"id":"deck"}},"thoughtSignature":"opaque"}]},"finishReason":"STOP"}]}"#)
        guard case .contextItem(let context) = events[0], case .toolCall(let call) = events[1] else { return XCTFail("Missing call context") }
        let request = AIRequest(model: AIModelDescriptor(provider: "gemini", model: "fixture", supportsTools: true), instructions: "Instructions", input: [
            .message(AIMessage(role: "user", text: "Inspect")), .context(context), .call(call), .result(callID: call.id, output: "Found deck")
        ])
        let wire = try GeminiWire.request(request)
        let contents = try XCTUnwrap(wire["contents"] as? [[String: Any]])
        XCTAssertEqual(contents.count, 3)
        let parts = try XCTUnwrap(contents[1]["parts"] as? [[String: Any]])
        XCTAssertEqual(parts[0]["thoughtSignature"] as? String, "opaque")
        XCTAssertNil((parts[0]["functionCall"] as? [String: Any])?["id"])
        let resultParts = try XCTUnwrap(contents[2]["parts"] as? [[String: Any]])
        let result = try XCTUnwrap(resultParts[0]["functionResponse"] as? [String: Any])
        XCTAssertNil(result["id"]); XCTAssertEqual(result["name"] as? String, "inspect")
    }
    func testTextLimitMalformedArgumentsAndForeignContextFailClosed() throws {
        var decoder = GeminiStreamDecoder(limit: 3)
        XCTAssertThrowsError(try decoder.accept(#"data: {"candidates":[{"content":{"parts":[{"text":"long text"}]},"finishReason":"STOP"}]}"#))
        var bad = GeminiStreamDecoder()
        XCTAssertThrowsError(try bad.accept(#"data: {"candidates":[{"content":{"parts":[{"functionCall":{"name":"edit","args":"broken"}}]},"finishReason":"STOP"}]}"#))
        let context = try AIContextItem(provider: "openai", json: #"{"type":"reasoning","id":"fixture"}"#)
        XCTAssertThrowsError(try GeminiWire.request(AIRequest(model: AIModelDescriptor(provider: "gemini", model: "fixture", supportsTools: true), instructions: "", input: [.context(context)])))
    }
    func testOrdinaryProseStreamsAndCompleteResponseKeepsSignature() throws {
        var decoder = GeminiStreamDecoder()
        XCTAssertEqual(try decoder.accept(#"data: {"candidates":[{"content":{"parts":[{"text":"Hello "}]}}]}"#), [.textDelta("Hello ")])
        let last = try decoder.accept(#"data: {"candidates":[{"content":{"parts":[{"text":"there","thoughtSignature":"opaque"}]},"finishReason":"STOP"}]}"#)
        XCTAssertEqual(last.first, .textDelta("there"))
        XCTAssertEqual(last.last, .completed)
    }
    func testTamperedContinuationCannotRelabelOrChangeRecordedCall() throws {
        XCTAssertThrowsError(try AIContextItem(provider: "gemini", json: #"{"content":{"role":"model","parts":[{"functionCall":{"id":"one","name":"inspect","args":{}}}]},"calls":[{"id":"one","name":"edit"}]}"#))
        var decoder = GeminiStreamDecoder()
        let events = try decoder.accept(#"data: {"candidates":[{"content":{"parts":[{"functionCall":{"id":"one","name":"inspect","args":{"id":"deck"}}}]},"finishReason":"STOP"}]}"#)
        guard case .contextItem(let context) = events[0] else { return XCTFail("Missing context") }
        let changed = AIToolCall(id: "one", name: "inspect", arguments: #"{"id":"other"}"#)
        let request = AIRequest(model: AIModelDescriptor(provider: "gemini", model: "fixture", supportsTools: true), instructions: "", input: [.context(context), .call(changed)])
        XCTAssertThrowsError(try GeminiWire.request(request))
    }
}
