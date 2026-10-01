import XCTest
import LearningCore

final class VoiceReviewCommandTests: XCTestCase {
    func testOrdinaryAnswersAndNegatedCommandsCannotGrade() {
        for text in ["That is easy", "Good availability", "Do not grade easy", "I think grade good is wrong", "grade easy then stop"] {
            XCTAssertEqual(VoiceReviewCommand.parse(text), .answer)
        }
    }
    func testExplicitGradeAndStopCommands() {
        XCTAssertEqual(VoiceReviewCommand.parse(" Grade GOOD. "), .grade(.good))
        XCTAssertEqual(VoiceReviewCommand.parse("grade again"), .grade(.again))
        XCTAssertEqual(VoiceReviewCommand.parse("grade hard"), .grade(.hard))
        XCTAssertEqual(VoiceReviewCommand.parse("grade easy"), .grade(.easy))
        XCTAssertEqual(VoiceReviewCommand.parse("Stop!"), .stop)
        XCTAssertEqual(VoiceReviewCommand.parse("repeat answer"), .repeatCard)
    }
}
