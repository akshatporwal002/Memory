import XCTest

final class TutorWorkspaceUITests: XCTestCase {
    @MainActor func testPhoneWorkspacePersists() { exercise(landscape: false) }
    @MainActor func testIPadLandscapeWorkspacePersists() { exercise(landscape: true) }

    @MainActor private func exercise(landscape: Bool) {
        if landscape { XCUIDevice.shared.orientation = .landscapeLeft }
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 15)); app.buttons["Settings"].tap()
        openTutor(app)
        let field = app.textFields["tutor-workspace-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        capture("Tutor-\(landscape ? "iPad" : "iPhone")-Empty", app)
        let name = "AWS UI \(UUID().uuidString.prefix(6))"
        field.tap(); field.typeText(name)
        app.buttons["tutor-create-workspace"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
        capture("Tutor-\(landscape ? "iPad" : "iPhone")-Created", app)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 15)); app.buttons["Settings"].tap()
        openTutor(app)
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
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
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
