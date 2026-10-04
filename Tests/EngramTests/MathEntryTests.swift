import XCTest
import LearningCore

final class MathEntryTests: XCTestCase {
    func testUndoRedoRestoreStructureAndUnwrapPreservesValuesAndIDs() throws {
        var document = MathEntryDocument()
        let initial = try XCTUnwrap(document.slots.first?.id)
        let first = try XCTUnwrap(document.insert(.fraction, at: initial))
        XCTAssertTrue(document.update(id: first, value: "1"))
        let second = try XCTUnwrap(document.slots.last?.id)
        XCTAssertTrue(document.update(id: second, value: "2"))
        XCTAssertTrue(document.canRemoveTemplate(containing: first))
        XCTAssertTrue(document.removeTemplate(containing: first))
        XCTAssertEqual(document.latex, #"1\;2"#)
        XCTAssertEqual(document.slots.map(\.id), [first, second])
        document.undo(); XCTAssertEqual(document.latex, #"\frac{1}{2}"#)
        document.redo(); XCTAssertEqual(document.latex, #"1\;2"#)
        document.undo(); XCTAssertTrue(document.update(id: first, value: "3"))
        XCTAssertFalse(document.canRedo); XCTAssertEqual(document.latex, #"\frac{3}{2}"#)
    }
    func testCustomMatrixAndPiecewiseDimensionsPreserveRowOrderAndRejectOversize() throws {
        var matrix = MathEntryDocument()
        let id = try XCTUnwrap(matrix.slots.first?.id)
        XCTAssertNotNil(matrix.insertMatrix(rows: 2, columns: 3, at: id))
        for (index, slot) in matrix.slots.enumerated() { XCTAssertTrue(matrix.update(id: slot.id, value: String(index + 1))) }
        XCTAssertEqual(matrix.latex, #"\begin{pmatrix}1&2&3\\4&5&6\end{pmatrix}"#)
        let before = matrix
        XCTAssertNil(matrix.insertMatrix(rows: 7, columns: 1, at: matrix.slots[0].id))
        XCTAssertEqual(matrix, before)
        var piecewise = MathEntryDocument()
        XCTAssertNotNil(piecewise.insertPiecewise(cases: 3, at: try XCTUnwrap(piecewise.slots.first?.id)))
        XCTAssertEqual(piecewise.slots.count, 6)
        for slot in piecewise.slots { XCTAssertTrue(piecewise.update(id: slot.id, value: "x")) }
        XCTAssertEqual(piecewise.latex, #"\begin{cases}x&x\\x&x\\x&x\end{cases}"#)
    }
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
