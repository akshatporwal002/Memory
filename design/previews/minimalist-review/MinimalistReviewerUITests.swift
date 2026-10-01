import XCTest

final class MinimalistReviewerUITests: XCTestCase {
    @MainActor func testAssistantProbe() {
        let app = launch()
        capture("01-Assistant-Before", app)
        let entry = app.buttons["assistant-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
        capture("02-Assistant-After-First-Tap", app)
        var composer = app.descendants(matching: .any)["assistant-composer"].firstMatch
        if !composer.waitForExistence(timeout: 3) {
            entry.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            capture("03-Assistant-After-Coordinate-Tap", app)
            composer = app.descendants(matching: .any)["assistant-composer"].firstMatch
        }
        guard composer.waitForExistence(timeout: 3) else { XCTFail("Assistant composer never opens after two visible entry taps"); return }
        composer.tap(); composer.typeText("Explain CloudFront")
        capture("04-Assistant-Keyboard", app)
        app.buttons["Send message"].tap()
        guard app.buttons["Expand assistant"].waitForExistence(timeout: 4) else { capture("05-Assistant-Send-State", app); XCTFail("No expandable response"); return }
        capture("05-Assistant-Response", app)
        app.buttons["Expand assistant"].tap(); capture("06-Assistant-Expanded", app)
        app.buttons["Collapse assistant"].tap(); capture("07-Assistant-Collapsed", app)
        app.buttons["Close assistant"].tap(); entry.tap(); capture("08-Assistant-Reopened", app)
    }
    @MainActor func testPhoneRetentionNotesAndSave() {
        let app = launch(); guard app.buttons["tab-library"].exists else { throwSkip(app); return }
        openDeck(app)
        let target = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Target 90%'")).firstMatch
        target.tap(); capture("10-Target-Settings", app)
        app.switches["Custom target for this deck"].firstMatch.switches.firstMatch.tap()
        XCTAssertTrue(app.sliders.firstMatch.waitForExistence(timeout: 3))
        app.sliders.firstMatch.adjust(toNormalizedSliderPosition: 0.9)
        capture("11-Target-Adjusted", app)
        app.navigationBars.buttons["Save"].tap(); capture("12-Target-Saved", app)
        app.swipeUp(); capture("13-Deck-Links-Scrolled", app)
        app.buttons["deck-notes"].tap()
        guard app.navigationBars["Notes"].waitForExistence(timeout: 5) else { capture("14-Notes-Unavailable", app); XCTFail("Notes did not open"); return }
        capture("14-Notes-Top", app)
        let rail = app.descendants(matching: .any)["notes-contents-rail"].firstMatch
        XCTAssertTrue(rail.waitForExistence(timeout: 3))
        rail.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: 70, dy: 53)).tap()
        capture("15-Notes-Rail-Jump", app)
        XCTAssertTrue(String(describing: rail.value ?? "").contains("Shared responsibility"))
        app.swipeUp(); capture("16-Notes-Scrolled", app)
        app.buttons["Edit"].tap(); capture("17-Notes-Editing", app)
        let fields = app.textFields.matching(NSPredicate(format: "label == %@", "Notebook writing")).allElementsBoundByIndex
        if let field = fields.first(where: {
            $0.isHittable && $0.frame.minY > 140 && $0.frame.maxY < app.frame.maxY - 120
        }) { field.tap(); field.typeText(" Reviewer saved prose.") }
        else { capture("18-Notes-Field-Missing", app); XCTFail("Writing editor field unavailable"); return }
        capture("18-Notes-Editing-Keyboard", app)
        app.navigationBars.buttons["Save"].tap(); capture("19-Notes-Saved", app)
        app.navigationBars.buttons.firstMatch.tap(); capture("20-Notes-Back-State", app)
        if !app.buttons["deck-questions"].exists { openDeck(app) }
        if !app.buttons["deck-questions"].isHittable { app.swipeUp() }
        app.buttons["deck-questions"].tap(); capture("21-Questions-After-Notes-Save", app)
        XCTAssertTrue(app.staticTexts["Answer B"].firstMatch.exists)
        app.swipeUp(); app.swipeUp(); capture("22-Questions-Last-After-Save", app)
        XCTAssertTrue(app.staticTexts["5. Which tool can alert you when spending exceeds a planned amount?"].exists)
    }
    @MainActor func testPhoneReviewAndBack() {
        let app = launch(); guard app.buttons["tab-today"].exists else { throwSkip(app); return }
        app.buttons["Start review"].tap(); capture("30-Review-Question", app)
        let back = app.navigationBars.buttons.firstMatch
        if back.exists { back.tap() }
        capture("31-Today-Paused", app)
        let resume = app.buttons["Resume saved session"]
        if !resume.isHittable { app.swipeUp() }
        if resume.exists { resume.tap(); capture("32-Review-Resumed", app) }
        else { XCTFail("Resume action missing after leaving review") }
    }
    @MainActor func testTabletRouteProbe() {
        let app = launch(); guard !app.buttons["tab-library"].exists else { throwSkip(app); return }
        capture("40-Tablet-Today", app)
        let deck = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'AWS Cloud Practitioner'")).firstMatch
        if !deck.isHittable { app.swipeUp() }
        deck.tap(); capture("41-Tablet-Deck-Route", app)
        XCTAssertTrue(app.buttons["deck-questions"].exists, "iPad still routes to legacy Library rather than the new deck overview")
        let entry = app.buttons["assistant-entry"]
        if entry.exists { entry.tap(); capture("42-Tablet-Assistant-Tap", app) }
    }
    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--ui-minimalist", "--ui-assistant-fixture"]
        app.launch(); XCTAssertTrue(app.buttons["Start review"].waitForExistence(timeout: 15)); return app
    }
    @MainActor private func openDeck(_ app: XCUIApplication) {
        if app.buttons["tab-library"].exists { app.buttons["tab-library"].tap() }
        let deck = app.buttons["library-deck-ui-deck"]
        XCTAssertTrue(deck.waitForExistence(timeout: 5)); deck.tap()
        XCTAssertTrue(app.buttons["deck-actions"].waitForExistence(timeout: 5))
    }
    @MainActor private func throwSkip(_ app: XCUIApplication) { capture("Device-Not-Applicable", app) }
    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
}
