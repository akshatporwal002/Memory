import XCTest
@testable import AIInfrastructure

final class VoiceWAVTests: XCTestCase {
    func testHeaderFramesAndClippingArePortable() throws {
        let data = try VoiceWAV.encode([-2, -1, 0, 1, 2])
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(data.count, 54)
        XCTAssertEqual(Array(data.suffix(10)), [0, 128, 0, 128, 0, 0, 255, 127, 255, 127])
    }
    func testEmptyNonfiniteOversizedAndInvalidRateAreRejected() {
        XCTAssertThrowsError(try VoiceWAV.encode([]))
        XCTAssertThrowsError(try VoiceWAV.encode([.nan]))
        XCTAssertThrowsError(try VoiceWAV.encode([.infinity]))
        XCTAssertThrowsError(try VoiceWAV.encode([0], sampleRate: 0))
        XCTAssertThrowsError(try VoiceWAV.encode(Array(repeating: 0, count: 8_000 * 120 + 1), sampleRate: 8_000))
    }
}
