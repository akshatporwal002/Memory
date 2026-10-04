import Foundation
import XCTest
@testable import AIInfrastructure

final class PersonalProviderTests: XCTestCase {
    func testAPICatalogHasDistinctProviderAndDoesNotGuessToolSupport() throws {
        let models = try OpenAIAPIProvider.decodeModels(["data": [["id": "fixture"], ["id": "fixture"], ["id": "audio-fixture"]]])
        XCTAssertEqual(models.map(\.id), ["openai:fixture", "openai:audio-fixture"])
        XCTAssertTrue(models.allSatisfy { !$0.supportsTools && $0.toolSupportKnown == false })
        XCTAssertThrowsError(try OpenAIAPIProvider.decodeModels(["models": []]))
    }
    func testProviderContinuationCannotBeMistakenForChatGPTOAuth() throws {
        var decoder = AIStreamDecoder(provider: "openai")
        let events = try decoder.accept(#"data: {"type":"response.output_item.done","item":{"type":"reasoning","id":"rs_fixture","summary":[],"encrypted_content":"fixture"}}"#)
        guard case .contextItem(let context) = events.first else { return XCTFail("Missing provider context") }
        XCTAssertEqual(context.provider, "openai")
        XCTAssertThrowsError(try AIContextItem(provider: "gemini", json: context.json))
    }
    func testKeyValidationRejectsWhitespaceAndControlCharactersWithoutEchoingSecrets() throws {
        XCTAssertEqual(try PersonalAPIKeyValidation.normalized("  fixture-key-123456789  "), "fixture-key-123456789")
        for key in ["short", "fixture key 123456789", "fixture-key\n123456789", "fixture-key\u{0}123456789", String(repeating: "a", count: 4097)] {
            XCTAssertThrowsError(try PersonalAPIKeyValidation.normalized(key)) { error in
                XCTAssertFalse(error.localizedDescription.contains(key))
            }
        }
    }
    func testCrossProviderRequestIsRejectedBeforeNetworking() async {
        let request = AIRequest(model: AIModelDescriptor(provider: "chatgpt", model: "fixture", supportsTools: false), instructions: "", input: [])
        do { _ = try await OpenAIAPIProvider().respond(request, token: "fixture"); XCTFail("Expected provider mismatch") }
        catch { XCTAssertEqual(error as? AIProviderError, .unsupportedModel) }
    }
}
