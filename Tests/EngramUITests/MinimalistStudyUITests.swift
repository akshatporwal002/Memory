import XCTest

final class MinimalistStudyUITests: XCTestCase {
    @MainActor func testPDFSampleApprovalAndSourceLinkedSave() {
        let app = launch(extra: ["--ui-pdf-fixture"])
        XCTAssertTrue(app.buttons["New deck"].waitForExistence(timeout: 15))
        app.buttons["New deck"].tap()
        XCTAssertTrue(app.buttons["deck-pdf-learning"].waitForExistence(timeout: 5))
        app.buttons["deck-pdf-learning"].tap()
        XCTAssertTrue(app.buttons["pdf-source-inspect"].waitForExistence(timeout: 5))
        capture("PDF-Learning-Brief", app)
        for _ in 0..<5 where !app.buttons["pdf-preview"].isHittable { app.swipeUp() }
        app.buttons["pdf-preview"].tap()
        XCTAssertTrue(app.buttons["pdf-approve"].waitForExistence(timeout: 10))
        capture("PDF-Learning-Sample", app)
        for _ in 0..<5 where !app.buttons["pdf-approve"].isHittable { app.swipeUp() }
        app.buttons["pdf-approve"].tap()
        XCTAssertTrue(app.buttons["pdf-save"].waitForExistence(timeout: 10))
        capture("PDF-Learning-Review", app)
        for _ in 0..<6 where !app.buttons["pdf-save"].isHittable { app.swipeUp() }
        app.buttons["pdf-save"].tap()
        XCTAssertTrue(app.buttons["deck-actions"].waitForExistence(timeout: 10))
        app.buttons["deck-actions"].tap()
        XCTAssertTrue(app.buttons["PDF source pages"].waitForExistence(timeout: 5))
        app.buttons["PDF source pages"].tap()
        XCTAssertTrue(app.buttons["Page 1"].waitForExistence(timeout: 5))
        capture("PDF-Saved-Source", app)
        app.buttons["Done"].tap()
        for _ in 0..<5 where !app.buttons["deck-questions"].isHittable { app.swipeUp() }
        app.buttons["deck-questions"].tap()
        XCTAssertTrue(app.staticTexts["1. Which service caches content near users?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Source evidence"].exists)
        capture("PDF-Saved-Questions", app)
    }
    @MainActor func testDeckQuestionsAndNotesNavigation() {
        let app = launch()
        XCTAssertTrue(app.buttons["Start review"].waitForExistence(timeout: 15))
        capture("Today-Green-Study", app)
        app.buttons["tab-library"].tap()
        XCTAssertTrue(app.buttons["library-deck-ui-deck"].waitForExistence(timeout: 5))
        app.buttons["library-deck-ui-deck"].tap()
        XCTAssertTrue(app.buttons["deck-actions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["deck-questions"].exists)
        XCTAssertTrue(app.buttons["deck-notes"].exists)
        capture("Deck-Flat-Outlook", app)
        XCTAssertTrue(app.staticTexts["7 days"].exists)
        app.buttons["deck-questions"].tap()
        XCTAssertTrue(app.navigationBars["Questions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Answer B"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["1. Which service delivers cached content close to users?"].exists)
        capture("Questions-Structured-MCQ", app)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["deck-notes"].tap()
        XCTAssertTrue(app.navigationBars["Notes"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Answer B"].exists)
        capture("Notes-Compact-Contents", app)
        let rail = app.descendants(matching: .any)["notes-contents-rail"].firstMatch
        XCTAssertTrue(rail.exists)
        rail.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.66)).tap()
        let selectedSection = expectation(for: NSPredicate(format: "value == %@", "Shared responsibility"), evaluatedWith: rail)
        wait(for: [selectedSection], timeout: 5)
        capture("Notes-Rail-Jump", app)
        app.swipeUp()
        capture("Notes-Scrolled-Contents", app)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["deck-questions"].waitForExistence(timeout: 5))
    }

    @MainActor func testAssistantKeyboardResponseAndExpansion() {
        let app = launch()
        let entry = app.buttons["assistant-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15)); entry.tap()
        let composer = app.textFields["assistant-composer"].firstMatch.exists ? app.textFields["assistant-composer"].firstMatch : app.textViews["assistant-composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5)); composer.tap()
        composer.typeText("Explain CloudFront")
        capture("Assistant-Keyboard", app)
        if app.keyboards.firstMatch.exists {
            XCTAssertLessThanOrEqual(composer.frame.maxY, app.keyboards.firstMatch.frame.minY + 2)
        }
        app.buttons["Send message"].tap()
        XCTAssertTrue(app.buttons["Expand assistant"].waitForExistence(timeout: 5))
        capture("Assistant-Response", app)
        app.buttons["Expand assistant"].tap()
        XCTAssertTrue(app.buttons["Collapse assistant"].waitForExistence(timeout: 5))
        capture("Assistant-Expanded", app)
        app.buttons["Close assistant"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab-library"].isHittable)
    }

    @MainActor func testDarkAndLargeTextLayout() {
        let app = launch(extra: ["--ui-dark", "--ui-large-text"])
        XCTAssertTrue(app.buttons["assistant-entry"].waitForExistence(timeout: 15))
        capture("Today-Dark-Large", app)
        app.buttons["tab-library"].tap()
        let deck = app.buttons["library-deck-ui-deck"]
        XCTAssertTrue(deck.waitForExistence(timeout: 5)); deck.tap()
        capture("Deck-Dark-Large", app)
        app.swipeUp()
        app.buttons["deck-questions"].tap()
        XCTAssertTrue(app.navigationBars["Questions"].waitForExistence(timeout: 5))
        capture("Questions-Dark-Large", app)
    }

    @MainActor private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-minimalist", "--ui-assistant-fixture"] + extra
        app.launch(); return app
    }
    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
