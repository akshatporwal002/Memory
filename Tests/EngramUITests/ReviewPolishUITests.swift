import XCTest
import UIKit

final class ReviewPolishUITests: XCTestCase {
    @MainActor func testPhoneTypedSubmissionAndReadySummary() throws { try device(.phone); typed(landscape: false) }
    @MainActor func testIPadLandscapeTypedSubmissionAndReadySummary() throws { try device(.pad); typed(landscape: true) }
    @MainActor func testPhoneInlineKeyboardAndModifiers() throws { try device(.phone); maths(landscape: false) }
    @MainActor func testIPadLandscapeInlineKeyboardAndModifiers() throws { try device(.pad); maths(landscape: true) }
    @MainActor func testPhoneSettingsAndAutomaticTutor() throws { try device(.phone); tutor(landscape: false) }
    @MainActor func testIPadLandscapeSettingsAndAutomaticTutor() throws { try device(.pad); tutor(landscape: true) }
    @MainActor func testPhoneRetentionForecastAndScroll() throws { try device(.phone); retention(landscape: false) }
    @MainActor func testIPadLandscapeRetentionForecastAndScroll() throws { try device(.pad); retention(landscape: true) }
    @MainActor private func device(_ idiom: UIUserInterfaceIdiom) throws { try XCTSkipIf(UIDevice.current.userInterfaceIdiom != idiom, "Validated on its matching existing simulator") }
    @MainActor private func app(landscape: Bool, maths: Bool = false) -> XCUIApplication {
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-monochrome", "--ui-review-polish-fixture"] + (maths ? ["--ui-inline-maths"] : [])
        if landscape { app.launchArguments.append("--ui-landscape") }
        app.launch()
        XCTAssertTrue(app.buttons["Start review"].waitForExistence(timeout: 15))
        if landscape {
            XCUIDevice.shared.orientation = .landscapeLeft
            let wide = NSPredicate { _, _ in app.frame.width > app.frame.height }
            expectation(for: wide, evaluatedWith: app); waitForExpectations(timeout: 10)
        }
        return app
    }
    @MainActor private func typed(landscape: Bool) {
        let app = app(landscape: landscape)
        app.buttons["Start review"].tap()
        XCTAssertTrue(app.buttons["Type answer"].waitForExistence(timeout: 5)); app.buttons["Type answer"].tap()
        capture("\(landscape ? "iPad" : "iPhone")-Typed-After", app)
        let input = app.textFields["typed-answer-input"].firstMatch
        let field = input.exists ? input : app.textViews["typed-answer-input"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("On-demand access to computing resources.")
        app.buttons["typed-answer-submit"].tap()
        XCTAssertTrue(app.staticTexts["Reference answer"].waitForExistence(timeout: 5))
        capture("\(landscape ? "iPad" : "iPhone")-Reference-After", app)
        let ready = app.buttons.containing(.staticText, identifier: "Review feedback ready").firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: 15)); ready.tap()
        XCTAssertTrue(app.navigationBars["Review feedback"].waitForExistence(timeout: 5))
        capture("\(landscape ? "iPad" : "iPhone")-Summary-After", app)
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Next question"].waitForExistence(timeout: 5))
    }
    @MainActor private func maths(landscape: Bool) {
        let app = app(landscape: landscape, maths: true)
        app.buttons["Start review"].tap(); app.buttons["Type answer"].tap()
        XCTAssertTrue(app.buttons["math-key-fraction"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.keyboards.count, 0)
        capture("\(landscape ? "iPad" : "iPhone")-Maths-After", app)
        app.buttons["ctrl"].tap()
        XCTAssertEqual(app.buttons["math-key-power"].label, "Nth root")
        capture("\(landscape ? "iPad" : "iPhone")-Maths-Ctrl-After", app)
        app.buttons["ctrl"].tap()
        app.buttons["math-key-fraction"].tap(); app.buttons["math-key-1"].tap(); app.buttons["math-key-next"].tap(); app.buttons["math-key-2"].tap()
        XCTAssertTrue(app.buttons["typed-answer-submit"].isEnabled)
        XCTAssertEqual(app.keyboards.count, 0)
        capture("\(landscape ? "iPad" : "iPhone")-Maths-Fraction-After", app)
    }
    @MainActor private func tutor(landscape: Bool) {
        let app = app(landscape: landscape)
        app.buttons["Settings"].firstMatch.tap()
        capture("\(landscape ? "iPad" : "iPhone")-Settings-After", app)
        let tutor = app.buttons["settings-Tutor"]
        for _ in 0..<4 where !tutor.isHittable { app.swipeUp() }
        XCTAssertTrue(tutor.exists); tutor.tap()
        if app.buttons["Activate tutor workspace"].waitForExistence(timeout: 2) { app.buttons["Activate tutor workspace"].tap() }
        XCTAssertTrue(app.buttons["All students"].waitForExistence(timeout: 5))
        capture("\(landscape ? "iPad" : "iPhone")-Tutor-After", app)
        app.buttons["All students"].tap()
        XCTAssertTrue(app.textFields["tutor-student-search"].waitForExistence(timeout: 5))
        capture("\(landscape ? "iPad" : "iPhone")-Tutor-Students-After", app)
    }
    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    @MainActor private func retention(landscape: Bool) {
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--ui-monochrome", "--ui-retention-fixture", "--ui-minimalist"]
        if landscape { app.launchArguments.append("--ui-landscape") }
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].firstMatch.waitForExistence(timeout: 15))
        if landscape {
            XCUIDevice.shared.orientation = .landscapeLeft
            let wide = NSPredicate { _, _ in app.frame.width > app.frame.height }
            expectation(for: wide, evaluatedWith: app); waitForExpectations(timeout: 10)
            app.collectionViews["Sidebar"].staticTexts["Library"].tap()
        } else { app.buttons["tab-library"].tap() }
        let deck = app.buttons["library-deck-ui-deck"]
        XCTAssertTrue(deck.waitForExistence(timeout: 5)); deck.tap()
        let chart = app.descendants(matching: .any)["deck-retention-chart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 10))
        capture("\(landscape ? "iPad" : "iPhone")-Retention-After", app)
        chart.swipeLeft()
        capture("\(landscape ? "iPad" : "iPhone")-Retention-Scrolled-After", app)
    }
}
