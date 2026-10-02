import XCTest
@testable import AIInfrastructure

final class AIProviderTests: XCTestCase {
    func testStreamCompletionAndDuplicateCalls() throws {
        var decoder = AIStreamDecoder()
        let call = #"data: {"type":"response.output_item.done","item":{"type":"function_call","call_id":"one","name":"edit_note","arguments":"{}"}}"#
        XCTAssertEqual(try decoder.accept(call).count,1)
        XCTAssertEqual(try decoder.accept(call).count,0)
        XCTAssertEqual(try decoder.accept(#"data: {"type":"response.completed"}"#),[.completed])
        XCTAssertTrue(decoder.completed)
    }
    func testFailureAndInvalidArgumentsRejected() {
        var decoder = AIStreamDecoder()
        XCTAssertThrowsError(try decoder.accept(#"data: {"type":"response.incomplete"}"#))
        XCTAssertThrowsError(try decoder.accept(#"data: {"type":"response.output_item.done","item":{"type":"function_call","call_id":"one","name":"edit_note","arguments":"not json"}}"#))
    }
    func testCumulativeOutputBound() throws {
        var decoder = AIStreamDecoder(limit:3)
        _ = try decoder.accept(#"data: {"type":"response.output_text.delta","delta":"ab"}"#)
        XCTAssertThrowsError(try decoder.accept(#"data: {"type":"response.output_text.delta","delta":"cd"}"#))
    }
    func testFakeProviderRequiresTerminalCompletion() async throws {
        let model = AIModelDescriptor(provider:"fake",model:"test",supportsTools:false)
        let request = AIRequest(model:model,instructions:"",input:[])
        let result = try await FakeProvider(complete:true).respond(request,token:"")
        XCTAssertEqual(result.text,"hello")
        do { _ = try await FakeProvider(complete:false).respond(request,token:""); XCTFail("Incomplete provider was accepted") }
        catch { XCTAssertEqual(error as? AIProviderError,.incomplete) }
    }
}
private struct FakeProvider: AIProvider {
    let id = "fake"
    let complete: Bool
    func models(token: String) async throws -> [AIModelDescriptor] { [] }
    func stream(_ request: AIRequest,token: String) -> AsyncThrowingStream<AIEvent,Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.textDelta("hello"))
            if complete { continuation.yield(.completed) }
            continuation.finish()
        }
    }
}
