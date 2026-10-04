import XCTest
@testable import AIInfrastructure

final class AIUsageTests: XCTestCase {
    func testReportedUsageIsMetadataAndNeverVisibleText() throws {
        var decoder = AIStreamDecoder(limit: 1000)
        let events = try decoder.accept(#"data: {"type":"response.completed","response":{"status":"completed","output":[],"usage":{"input_tokens":34,"output_tokens":12,"input_tokens_details":{"cached_tokens":8},"output_tokens_details":{"reasoning_tokens":3}}}}"#)
        XCTAssertTrue(events.contains(.usage(AIUsage(inputTokens: 34, outputTokens: 12, cachedTokens: 8, reasoningTokens: 3)!)))
        XCTAssertFalse(events.contains { if case .textDelta = $0 { return true }; return false })
        XCTAssertEqual(events.last, .completed)
    }
    func testMissingAndNegativeUsageStaysUnavailableRatherThanZero() {
        XCTAssertNil(AIUsage.responses([:]))
        XCTAssertNil(AIUsage.responses(["input_tokens": -1, "output_tokens": 5]))
        XCTAssertEqual(AIUsage.gemini(["promptTokenCount": 9, "candidatesTokenCount": 3])?.inputTokens, 9)
        XCTAssertNil(AIUsage.gemini(["promptTokenCount": 9]))
    }
}
