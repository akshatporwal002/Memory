import XCTest
import LearningCore

final class MathEntryTests: XCTestCase {
    func testNativeSelectionReplacesTextAtCaretAndUndoRestoresTheAttempt() throws {
        var document = MathEntryDocument()
        let id = try XCTUnwrap(document.slots.first?.id)
        XCTAssertTrue(document.update(id: id, value: "α🙂z"))
        let selection = try XCTUnwrap(MathEntryTextSelection(source: "α🙂z", utf16Range: NSRange(location: 1, length: 2)))
        let caret = try XCTUnwrap(document.replaceText("+", at: id, selection: selection))
        XCTAssertEqual(document.slots.first?.value, "α+z")
        XCTAssertEqual(caret.utf16Range, NSRange(location: 2, length: 0))
        XCTAssertNotNil(document.replaceText("θ", at: id, selection: caret))
        XCTAssertEqual(document.slots.first?.value, "α+θz")
        document.undo(); XCTAssertEqual(document.slots.first?.value, "α+z")
        document.undo(); XCTAssertEqual(document.slots.first?.value, "α🙂z")
    }
    func testTemplateReplacementIsOneUndoAndPreservesUnselectedText() throws {
        var document = MathEntryDocument()
        let id = try XCTUnwrap(document.slots.first?.id)
        XCTAssertTrue(document.update(id: id, value: "a+b"))
        let before = document.latex
        let selection = try XCTUnwrap(MathEntryTextSelection(source: "a+b", utf16Range: NSRange(location: 1, length: 1)))
        XCTAssertNotNil(document.insert(.fraction, at: id, selection: selection))
        XCTAssertEqual(document.slots.first?.value, "a")
        XCTAssertEqual(document.slots.last?.value, "b")
        document.undo(); XCTAssertEqual(document.latex, before)
        XCTAssertEqual(document.slots.first?.id, id)
    }
    func testBrokenUnicodeStaleSelectionsAndOversizedReplacementsDoNotMutate() throws {
        XCTAssertNil(MathEntryTextSelection(source: "🙂", utf16Range: NSRange(location: 1, length: 0)))
        XCTAssertNil(MathEntryTextSelection(source: "e\u{301}", utf16Range: NSRange(location: 0, length: 1)))
        var document = MathEntryDocument()
        let id = try XCTUnwrap(document.slots.first?.id)
        XCTAssertTrue(document.update(id: id, value: "new"))
        let stale = try XCTUnwrap(MathEntryTextSelection(source: "old", utf16Range: NSRange(location: 1, length: 1)))
        let before = document
        XCTAssertNil(document.replaceText("+", at: id, selection: stale))
        XCTAssertNil(document.insert(.fraction, at: id, selection: stale))
        XCTAssertNil(document.replaceText(String(repeating: "x", count: 2001), at: id))
        XCTAssertEqual(document, before)
    }
    func testResizeBeyondDocumentSlotLimitLeavesStructureAndHistoryIntact() throws {
        var document = MathEntryDocument()
        XCTAssertNotNil(document.insertMatrix(rows: 6, columns: 6, at: try XCTUnwrap(document.slots.first?.id)))
        let outer = document.slots
        let inner = try XCTUnwrap(document.insertMatrix(rows: 2, columns: 2, at: outer[0].id))
        XCTAssertNotNil(document.insertMatrix(rows: 6, columns: 6, at: outer[1].id))
        XCTAssertEqual(document.slots.count, 74)
        let before = document
        XCTAssertFalse(document.resize(containing: inner, rows: 6, columns: 6))
        XCTAssertEqual(document, before)
    }
    func testMatrixResizePreservesCoordinatesAndIdentitiesAcrossColumnCountChanges() throws {
        var document = MathEntryDocument()
        let first = try XCTUnwrap(document.insertMatrix(rows: 2, columns: 2, at: try XCTUnwrap(document.slots.first?.id)))
        let original = document.slots
        for (index, slot) in original.enumerated() { XCTAssertTrue(document.update(id: slot.id, value: String(index + 1))) }
        XCTAssertTrue(document.resize(containing: first, rows: 3, columns: 3))
        XCTAssertEqual(document.slots[0].id, original[0].id)
        XCTAssertEqual(document.slots[1].id, original[1].id)
        XCTAssertEqual(document.slots[3].id, original[2].id)
        XCTAssertEqual(document.slots[4].id, original[3].id)
        XCTAssertEqual(document.slots[3].value, "3")
        XCTAssertEqual(document.slots[4].value, "4")
        XCTAssertEqual(document.slots.count, 9)
        let expanded = document.latex
        document.undo(); XCTAssertEqual(document.latex, #"\begin{pmatrix}1&2\\3&4\end{pmatrix}"#)
        document.redo(); XCTAssertEqual(document.latex, expanded)
        XCTAssertTrue(document.resize(containing: first, rows: 2, columns: 2))
        XCTAssertEqual(document.slots.map(\.id), original.map(\.id))
        XCTAssertEqual(document.latex, #"\begin{pmatrix}1&2\\3&4\end{pmatrix}"#)
    }
    func testShrinkingNonemptyMatrixRequiresExplicitConsentAndUndoRestoresRemovedValues() throws {
        var document = MathEntryDocument()
        let first = try XCTUnwrap(document.insertMatrix(rows: 2, columns: 2, at: try XCTUnwrap(document.slots.first?.id)))
        for slot in document.slots { XCTAssertTrue(document.update(id: slot.id, value: "x")) }
        let before = document
        XCTAssertTrue(document.resizeWouldDiscardContent(containing: first, rows: 1, columns: 1))
        XCTAssertFalse(document.resize(containing: first, rows: 1, columns: 1))
        XCTAssertEqual(document, before)
        XCTAssertTrue(document.resize(containing: first, rows: 1, columns: 1, allowDiscardingContent: true))
        XCTAssertEqual(document.slots.count, 1)
        document.undo(); XCTAssertEqual(document.latex, before.latex)
        XCTAssertEqual(document.slots, before.slots)
        let restored = document
        XCTAssertFalse(document.resize(containing: first, rows: 7, columns: 1, allowDiscardingContent: true))
        XCTAssertEqual(document, restored)
    }
    func testNestedTemplatesSurvivePiecewiseResizeAndNearestMatrixIsResized() throws {
        var document = MathEntryDocument()
        let expression = try XCTUnwrap(document.insertPiecewise(cases: 2, at: try XCTUnwrap(document.slots.first?.id)))
        let numerator = try XCTUnwrap(document.insert(.fraction, at: expression))
        XCTAssertTrue(document.update(id: numerator, value: "x"))
        let nestedIDs = document.slots.map(\.id)
        XCTAssertTrue(document.resize(containing: numerator, rows: 3, columns: 2))
        XCTAssertEqual(Array(document.slots.prefix(nestedIDs.count)).map(\.id), nestedIDs)
        XCTAssertTrue(document.latex.contains(#"\frac{x}{\square}"#))
        let before = document
        XCTAssertFalse(document.resize(containing: numerator, rows: 3, columns: 3))
        XCTAssertEqual(document, before)
        let inner = try XCTUnwrap(document.insertMatrix(rows: 1, columns: 1, at: numerator))
        XCTAssertTrue(document.resize(containing: inner, rows: 1, columns: 2))
        XCTAssertEqual(document.dimensions(containing: inner)?.rows, 1)
        XCTAssertEqual(document.dimensions(containing: inner)?.columns, 2)
        XCTAssertTrue(document.latex.contains(#"\begin{cases}"#))
    }
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
