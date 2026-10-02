import XCTest
import LearningCore
final class ContentMergeTests: XCTestCase {
    func testDifferentFieldsMergeAndOverlapRequiresResolution() throws {
        let base = Data(#"{"front":"q","back":"a"}"#.utf8)
        let yours = Data(#"{"front":"new q","back":"a"}"#.utf8)
        let theirs = Data(#"{"front":"q","back":"new a"}"#.utf8)
        let merged = try ContentMerge.merge(base:base,yours:yours,theirs:theirs)
        XCTAssertEqual(String(decoding:try XCTUnwrap(merged.merged),as:UTF8.self),#"{"back":"new a","front":"new q"}"#)
        let conflict = try ContentMerge.merge(base:base,yours:yours,theirs:Data(#"{"front":"other q","back":"a"}"#.utf8))
        XCTAssertNil(conflict.merged); XCTAssertEqual(conflict.conflictingPaths,["/front"])
    }
    func testIndependentNotebookSectionsMergeAndDeleteEditConflicts() throws {
        let base = Data(#"[{"id":"a","text":"A"},{"id":"b","text":"B"}]"#.utf8)
        let yours = Data(#"[{"id":"a","text":"new A"},{"id":"b","text":"B"}]"#.utf8)
        let theirs = Data(#"[{"id":"a","text":"A"},{"id":"b","text":"new B"}]"#.utf8)
        XCTAssertNotNil(try ContentMerge.merge(base:base,yours:yours,theirs:theirs).merged)
        let deleted = Data(#"[{"id":"b","text":"B"}]"#.utf8)
        XCTAssertNil(try ContentMerge.merge(base:base,yours:yours,theirs:deleted).merged)
    }
}
