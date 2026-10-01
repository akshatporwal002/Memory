import XCTest

final class MinimalistStudyUITests: XCTestCase {
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
