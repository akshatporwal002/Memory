import XCTest
@testable import AIInfrastructure

final class AIProviderTests: XCTestCase {
    func testOpaqueReasoningContextIsRetainedBeforeToolResultsAndDeduplicated() throws {
        var decoder = AIStreamDecoder()
        let event = #"data: {"type":"response.output_item.done","item":{"id":"rs_one","type":"reasoning","summary":[],"encrypted_content":"opaque","untrusted_extra":"discard"}}"#
        let received = try decoder.accept(event)
        guard case .contextItem(let item) = received.first else { return XCTFail("Missing continuation item") }
        XCTAssertEqual(item.wire["encrypted_content"] as? String,"opaque")
        XCTAssertNil(item.wire["untrusted_extra"])
        XCTAssertTrue(try decoder.accept(event).isEmpty)
        let original: [AIInput] = [.context(item),.call(AIToolCall(id:"call",name:"edit",arguments:"{}")),.result(callID:"call",output:"Saved")]
        XCTAssertEqual(try JSONDecoder().decode([AIInput].self,from:JSONEncoder().encode(original)),original)
    }
    func testProviderContractRejectsUnsupportedActionsAndBoundsOutput() async {
        let descriptor = AIModelDescriptor(provider:"fake",model:"text",supportsTools:false)
        do { _ = try await FakeProvider(complete:true).respond(AIRequest(model:descriptor,instructions:"",input:[],tools:[AIToolDefinition(name:"edit",summary:"",parametersJSON:"{}")]),token:""); XCTFail("Unsupported tools accepted") }
        catch { XCTAssertEqual(error as? AIProviderError,.unsupportedModel) }
        do { _ = try await FakeProvider(complete:true).respond(AIRequest(model:descriptor,instructions:"",input:[],outputLimit:3),token:""); XCTFail("Unbounded output accepted") }
        catch { XCTAssertEqual(error as? AIProviderError,.exceededLimit) }
    }
    func testInterruptedHistoryRecoversReceiptWithoutExecutingAgain() {
        let call = AIToolCall(id:"saved",name:"edit",arguments:"{}")
        let history = AIHistoryRecovery.reconcile([.call(call)],receipts:["saved":"completed: renamed deck"])
        XCTAssertEqual(history,[.call(call),.result(callID:"saved",output:"completed: renamed deck")])
        XCTAssertEqual(AIHistoryRecovery.reconcile(history,receipts:[:]),history)
        let interrupted = AIHistoryRecovery.reconcile([.call(call)],receipts:[:])
        guard case .result(_,let message) = interrupted.last else { return XCTFail("Missing terminal receipt") }
        XCTAssertTrue(message.contains("Do not assume success or repeat"))
    }
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
