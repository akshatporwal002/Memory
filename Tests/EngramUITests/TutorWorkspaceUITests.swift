import XCTest

final class TutorWorkspaceUITests: XCTestCase {
    @MainActor func testPhoneWorkspacePersists() { exercise(landscape: false) }
    @MainActor func testIPadLandscapeWorkspacePersists() { exercise(landscape: true) }

    @MainActor private func exercise(landscape: Bool) {
        if landscape { XCUIDevice.shared.orientation = .landscapeLeft }
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"] + (landscape ? ["--ui-landscape"] : []); app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 15)); app.buttons["Settings"].tap()
        openTutor(app)
        if app.buttons["Activate tutor workspace"].waitForExistence(timeout: 2) { app.buttons["Activate tutor workspace"].tap() }
        XCTAssertTrue(app.buttons["All students"].waitForExistence(timeout: 5))
        capture("Tutor-\(landscape ? "iPad" : "iPhone")-Empty", app)
        capture("Tutor-\(landscape ? "iPad" : "iPhone")-Created", app)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 15)); app.buttons["Settings"].tap()
        openTutor(app)
        XCTAssertTrue(app.buttons["All students"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Activate tutor workspace"].exists)
        capture("Tutor-\(landscape ? "iPad" : "iPhone")-Reopened", app)
        if landscape { XCTAssertGreaterThan(app.frame.width, app.frame.height) }
    }
    @MainActor private func openTutor(_ app: XCUIApplication) {
        let tutor = app.buttons["settings-Tutor"]
        if !tutor.waitForExistence(timeout: 2) {
            for _ in 0..<6 {
                app.swipeUp()
                if tutor.exists { break }
            }
        }
        XCTAssertTrue(tutor.waitForExistence(timeout: 3), "Tutor must be reachable from Settings")
        if tutor.exists { tutor.tap() }
    }
    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
