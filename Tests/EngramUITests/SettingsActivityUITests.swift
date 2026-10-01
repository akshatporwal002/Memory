import XCTest

final class SettingsActivityUITests: XCTestCase {
    @MainActor func testSettingsNavigationAndActivity() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["Settings"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        screenshot("Settings", app: app)
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Study")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Study"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "New cards per day")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["New Cards"].waitForExistence(timeout: 5))
        let original = Int(app.textFields.firstMatch.value as? String ?? "")!
        app.steppers.buttons["Increment"].tap()
        XCTAssertEqual(app.textFields.firstMatch.value as? String, String(original + 1))
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "New cards per day")).firstMatch.tap()
        XCTAssertEqual(app.textFields.firstMatch.value as? String, String(original + 1))
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts["Review attempts"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Bars"].tap()
        screenshot("Activity", app: app)
        let chart = app.descendants(matching: .any)["review-activity-chart"].firstMatch
        XCTAssertTrue(chart.exists)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Show entire period"].waitForExistence(timeout: 5))
        app.buttons["Show entire period"].tap()
        app.segmentedControls.buttons["Line"].tap()
        screenshot("Activity-Line", app: app)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Show entire period"].waitForExistence(timeout: 5))
        app.buttons["Show entire period"].tap()
        app.buttons["Previous period"].tap()
        XCTAssertTrue(app.buttons["Next period"].isEnabled)
        app.buttons["Next period"].tap()
        XCTAssertFalse(app.buttons["Next period"].isEnabled)
    }
    @MainActor func testVoiceDiagnosticsAndStorage() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["Settings"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["Settings"].firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Voice")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Test microphone"].waitForExistence(timeout: 5))
        screenshot("Voice", app: app)
        app.buttons["Test microphone"].tap()
        XCTAssertTrue(app.buttons["Record sample"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        let storage = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Storage & Downloads")).firstMatch
        if !storage.isHittable { app.swipeUp() }
        storage.tap()
        XCTAssertTrue(app.staticTexts["Media size"].waitForExistence(timeout: 5))
        screenshot("Storage", app: app)
    }
    @MainActor func testDarkThemeAndLargeTextSnapshots() {
        for (name, options) in [("Warm-Dark", ["--ui-dark"]), ("Neutral-Dark-Large", ["--ui-dark", "--ui-neutral", "--ui-large-text"])] {
            let app = XCUIApplication(); app.launchArguments = ["--ui-testing"] + options; app.launch()
            XCTAssertTrue(app.buttons["Settings"].firstMatch.waitForExistence(timeout: 15))
            app.buttons["Settings"].firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
            screenshot("Settings-" + name, app: app)
            app.navigationBars.buttons.firstMatch.tap()
            app.tabBars.buttons["Activity"].tap()
            XCTAssertTrue(app.staticTexts["Review attempts"].waitForExistence(timeout: 5))
            screenshot("Activity-" + name, app: app)
            app.terminate()
        }
    }
    @MainActor func testTabletSettingsAndChart() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["Settings"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        screenshot("Tablet-Settings", app: app)
        app.navigationBars["Settings"].buttons.firstMatch.tap()
        app.staticTexts["Activity"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Review attempts"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Line"].tap()
        screenshot("Tablet-Activity", app: app)
    }
    @MainActor private func screenshot(_ name: String, app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
