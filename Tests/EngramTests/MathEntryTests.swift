import XCTest
import LearningCore

final class MathEntryTests: XCTestCase {
    func testFractionFieldsProducePortableNotationWithoutEvaluating() throws {
        var document = MathEntryDocument()
        let initial = try XCTUnwrap(document.slots.first?.id)
        let numerator = try XCTUnwrap(document.insert(.fraction, at: initial))
        XCTAssertFalse(document.complete)
        XCTAssertTrue(document.update(id: numerator, value: "1"))
        let denominator = try XCTUnwrap(document.slots.last?.id)
        XCTAssertTrue(document.update(id: denominator, value: "2"))
        XCTAssertTrue(document.complete)
        XCTAssertEqual(document.latex, #"\frac{1}{2}"#)
    }
    func testNestedInsertionPreservesUnicodeOnBothSidesOfCursor() throws {
        var document = MathEntryDocument()
        let initial = try XCTUnwrap(document.slots.first?.id)
        XCTAssertTrue(document.update(id: initial, value: "αβ"))
        let slot = try XCTUnwrap(document.insert(.root, at: initial, offset: 1))
        let nested = try XCTUnwrap(document.insert(.power, at: slot))
        XCTAssertTrue(document.update(id: nested, value: "x"))
        let exponent = try XCTUnwrap(document.slots.first { $0.label == "Power · Exponent" }?.id)
        XCTAssertTrue(document.update(id: exponent, value: "2"))
        XCTAssertEqual(document.latex, #"α\sqrt{{x}^{2}}β"#)
        XCTAssertTrue(document.complete)
    }
    func testAllTemplatesHaveEditableSlotsAndNoUnresolvedRecipeMarkers() throws {
        for template in MathEntryTemplate.allCases {
            var document = MathEntryDocument()
            let initial = try XCTUnwrap(document.slots.first?.id)
            XCTAssertNotNil(document.insert(template, at: initial))
            XCTAssertEqual(document.slots.count, template.labels.count)
            for slot in document.slots { XCTAssertTrue(document.update(id: slot.id, value: "x")) }
            XCTAssertTrue(document.complete); XCTAssertFalse(document.latex.contains("«"))
            XCTAssertFalse(document.latex.contains("»"))
        }
    }
    func testTextCannotInjectCommandsOrRewriteAnotherTemplateSlot() throws {
        var document = MathEntryDocument()
        let initial = try XCTUnwrap(document.slots.first?.id)
        let numerator = try XCTUnwrap(document.insert(.fraction, at: initial))
        XCTAssertTrue(document.update(id: numerator, value: #"\href{https://example.com}{«1»}"#))
        let denominator = try XCTUnwrap(document.slots.last?.id)
        XCTAssertTrue(document.update(id: denominator, value: "z"))
        XCTAssertFalse(document.latex.contains(#"\href"#))
        XCTAssertTrue(document.latex.contains("«1»")); XCTAssertTrue(document.latex.hasSuffix("{z}"))
        let before = document
        XCTAssertFalse(document.update(id: denominator, value: String(repeating: "x", count: 2001)))
        XCTAssertEqual(before, document)
    }
}
