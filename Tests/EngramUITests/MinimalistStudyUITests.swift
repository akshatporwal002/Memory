import XCTest

final class MinimalistStudyUITests: XCTestCase {
    @MainActor func testMatrixResizeOnPhone() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        exerciseMatrixResize(app, prefix: "iPhone")
    }
    @MainActor func testMatrixResizeOnIPadLandscape() {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        let landscape = NSPredicate { _, _ in app.frame.width > app.frame.height }
        expectation(for: landscape, evaluatedWith: app); waitForExpectations(timeout: 10)
        exerciseMatrixResize(app, prefix: "iPad")
        XCTAssertGreaterThan(app.screenshot().image.size.width, app.screenshot().image.size.height)
    }
    @MainActor private func exerciseMatrixResize(_ app: XCUIApplication, prefix: String) {
        XCTAssertTrue(app.buttons["Start review"].waitForExistence(timeout: 15)); app.buttons["Start review"].tap()
        XCTAssertTrue(app.buttons["Type answer"].waitForExistence(timeout: 5)); app.buttons["Type answer"].tap()
        capture(prefix + "-Typed-Before-Matrix", app)
        app.buttons["typed-answer-equation"].tap()
        app.buttons["math-category"].tap(); app.buttons["Matrices"].tap()
        XCTAssertTrue(app.buttons["math-template-matrix"].waitForExistence(timeout: 5)); app.buttons["math-template-matrix"].tap()
        app.buttons["math-dimensions-apply"].tap()
        let first = app.textFields["math-slot-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5)); first.tap(); first.typeText("7")
        if app.keyboards.count > 0 { app.buttons["Done"].tap() }
        capture(prefix + "-Matrix-Before-Resize", app)
        app.buttons["Structure"].tap(); app.buttons["math-resize"].tap()
        let rows = app.steppers["math-dimension-rows"]
        XCTAssertTrue(rows.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.buttons.count, 2)
        rows.buttons.element(boundBy: 1).tap()
        app.buttons["math-dimensions-apply"].tap()
        XCTAssertTrue(app.textFields["math-slot-5"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["math-slot-0"].value as? String, "7")
        capture(prefix + "-Matrix-After-Resize", app)
        app.buttons["Undo"].tap()
        XCTAssertFalse(app.textFields["math-slot-5"].exists)
        XCTAssertEqual(app.textFields["math-slot-0"].value as? String, "7")
    }
    @MainActor func testEquationEntryOnExistingTypedAnswer() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        exerciseEquationEntry(app, prefix: "iPhone")
    }
    @MainActor func testIPadEquationEntryLandscape() {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        let landscape = NSPredicate { _, _ in app.frame.width > app.frame.height }
        expectation(for: landscape, evaluatedWith: app); waitForExpectations(timeout: 10)
        exerciseEquationEntry(app, prefix: "iPad")
        let screenshot = app.screenshot()
        XCTAssertGreaterThan(screenshot.image.size.width, screenshot.image.size.height)
    }
    @MainActor private func exerciseEquationEntry(_ app: XCUIApplication, prefix: String) {
        XCTAssertTrue(app.buttons["Start review"].waitForExistence(timeout: 15)); app.buttons["Start review"].tap()
        XCTAssertTrue(app.buttons["Type answer"].waitForExistence(timeout: 5)); app.buttons["Type answer"].tap()
        capture(prefix + "-Typed-Answer-Before-Equation", app)
        app.buttons["typed-answer-equation"].tap()
        XCTAssertTrue(app.buttons["math-template-fraction"].waitForExistence(timeout: 5)); app.buttons["math-template-fraction"].tap()
        let numerator = app.textFields["math-slot-0"], denominator = app.textFields["math-slot-1"]
        XCTAssertTrue(numerator.waitForExistence(timeout: 5)); numerator.tap(); numerator.typeText("1")
        // Navigate with the editor's keyboard control; the next field can be
        // below the keyboard after the first value is entered on a phone.
        app.buttons["Next"].tap(); denominator.typeText("2")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["math-entry-insert"].isEnabled)
        app.buttons["Undo"].tap()
        XCTAssertFalse(app.buttons["math-entry-insert"].isEnabled)
        app.buttons["Redo"].tap()
        XCTAssertTrue(app.buttons["math-entry-insert"].isEnabled)
        capture(prefix + "-Equation-Fraction", app)
        app.buttons["math-entry-insert"].tap()
        XCTAssertTrue((app.descendants(matching: .any).matching(identifier: "typed-answer-input").firstMatch.value as? String ?? "").contains(#"\frac{1}{2}"#))
        capture(prefix + "-Typed-Answer-After-Equation", app)
    }
    @MainActor func testTestingSamplesImportAndReimport() {
        let app = launch()
        XCTAssertTrue(app.buttons["tab-library"].waitForExistence(timeout: 15)); app.buttons["tab-library"].tap()
        capture("iPhone-Library-Before-Testing-Import", app)
        exerciseTestingImport(app, prefix: "iPhone")
    }
    @MainActor func testIPadTestingSamplesLandscape() {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch()
        let landscape = NSPredicate { _, _ in app.frame.width > app.frame.height }
        expectation(for: landscape, evaluatedWith: app); waitForExpectations(timeout: 10)
        let sidebar = app.collectionViews["Sidebar"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 15)); sidebar.staticTexts["Library"].tap()
        capture("iPad-Library-Before-Testing-Import", app)
        exerciseTestingImport(app, prefix: "iPad")
        let screenshot = app.screenshot()
        XCTAssertGreaterThan(screenshot.image.size.width, screenshot.image.size.height)
    }
    @MainActor private func exerciseTestingImport(_ app: XCUIApplication, prefix: String) {
        XCTAssertTrue(app.buttons["library-add-menu"].waitForExistence(timeout: 5)); app.buttons["library-add-menu"].tap()
        app.buttons["Testing samples"].tap()
        let add = app.buttons["import-testing-samples"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        capture(prefix + "-Testing-Samples", app)
        add.tap()
        let result = app.staticTexts["testing-samples-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        XCTAssertTrue(result.label.contains("Added 13 questions in 3 notebooks"))
        capture(prefix + "-Testing-Samples-Imported", app)
        add.tap()
        let preserved = NSPredicate(format: "label CONTAINS %@", "Preserved 13 existing questions")
        expectation(for: preserved, evaluatedWith: result); waitForExpectations(timeout: 10)
        app.buttons["Done"].tap()
        capture(prefix + "-Library-After-Testing-Import", app)
    }
    @MainActor func testPersonalProviderKeyEntry() {
        let app = launch(extra: ["--ui-monochrome"])
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 15))
        app.buttons["Settings"].tap()
        app.buttons.containing(.staticText, identifier: "AI & Connections").firstMatch.tap()
        let entry = app.buttons["personal-provider-openai"]
        if !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        XCTAssertTrue(app.secureTextFields["personal-key-input"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["personal-key-save"].isEnabled)
        capture("Personal-API-Key", app)
        app.secureTextFields["personal-key-input"].tap()
        app.secureTextFields["personal-key-input"].typeText("short")
        app.buttons["personal-key-save"].tap()
        XCTAssertTrue(app.staticTexts["Enter an API key without spaces or line breaks."].waitForExistence(timeout: 5))
        capture("Personal-API-Key-Validation", app)
    }
    @MainActor func testIPadPersonalProviderKeyEntry() {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch()
        XCUIDevice.shared.orientation = .portrait
        XCUIDevice.shared.orientation = .landscapeRight
        let landscape = NSPredicate { _, _ in app.frame.width > app.frame.height }
        expectation(for: landscape, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 15)); app.buttons["Settings"].tap()
        app.buttons.containing(.staticText, identifier: "AI & Connections").firstMatch.tap()
        let entry = app.buttons["personal-provider-gemini"]
        if !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        XCTAssertTrue(app.secureTextFields["personal-key-input"].waitForExistence(timeout: 5))
        // Capture the app surface: the simulator screen attachment can retain
        // portrait pixel orientation even when the application is landscape.
        let screenshot = app.screenshot()
        XCTAssertGreaterThan(screenshot.image.size.width, screenshot.image.size.height)
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "iPad-Personal-API-Key"; attachment.lifetime = .keepAlways
        add(attachment)
    }
    @MainActor func testAccountAndLibraryBaselineCaptures() {
        let app = launch(extra: ["--ui-monochrome", "--ui-dark"])
        XCTAssertTrue(app.buttons["tab-library"].waitForExistence(timeout: 15))
        app.buttons["tab-library"].tap(); capture("Library-Before", app)
        app.buttons["Settings"].tap()
        app.buttons.containing(.staticText, identifier: "AI & Connections").firstMatch.tap()
        app.buttons["Engram account"].tap()
        capture("Account-Before", app)
    }
    @MainActor func testUnifiedAccountLightCapture() {
        let app = launch(extra: ["--ui-monochrome"])
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 15))
        app.buttons["Settings"].tap()
        app.buttons.containing(.staticText, identifier: "AI & Connections").firstMatch.tap()
        XCTAssertFalse(app.buttons["Engram account"].exists)
        XCTAssertTrue(app.buttons["account-chatgpt"].waitForExistence(timeout: 5))
        capture("Account-Unified-Light", app)
    }
    @MainActor func testUnifiedAccountAndLibraryScreens() {
        let app = launch(extra: ["--ui-monochrome", "--ui-dark"])
        XCTAssertTrue(app.buttons["tab-library"].waitForExistence(timeout: 15))
        app.buttons["tab-library"].tap()
        XCTAssertTrue(app.buttons["library-space-picker"].waitForExistence(timeout: 5))
        capture("Library-Spaces", app)
        app.buttons["library-space-picker"].tap()
        app.buttons["New library"].tap()
        let field = app.textFields["Library name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("University")
        app.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts["University"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["library-deck-ui-deck"].exists)
        capture("Library-New-Space", app)
        app.buttons["library-space-picker"].tap()
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "My library")).firstMatch.tap()
        XCTAssertTrue(app.buttons["library-deck-ui-deck"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        app.buttons.containing(.staticText, identifier: "AI & Connections").firstMatch.tap()
        XCTAssertFalse(app.buttons["Engram account"].exists)
        for id in ["account-chatgpt", "account-google", "account-apple", "account-email"] {
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 5))
        }
        capture("Account-Unified-Dark", app)
        app.buttons["account-email"].tap()
        XCTAssertTrue(app.textFields["you@example.com"].waitForExistence(timeout: 5))
        capture("Account-Email-Dark", app)
    }
    @MainActor func testIPadInlineAccountCapture() {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 15))
        app.buttons["Settings"].tap()
        app.buttons.containing(.staticText, identifier: "AI & Connections").firstMatch.tap()
        XCTAssertTrue(app.buttons["account-chatgpt"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Engram account"].exists)
        capture("iPad-Inline-Account", app)
        app.buttons["account-email"].tap()
        XCTAssertTrue(app.textFields["you@example.com"].waitForExistence(timeout: 5))
        capture("iPad-Inline-Email", app)
    }
    @MainActor func testMemoryGraphWindows() {
        let app = launch()
        XCTAssertTrue(app.buttons["tab-library"].waitForExistence(timeout: 15))
        app.buttons["tab-library"].tap()
        app.buttons["library-deck-ui-deck"].tap()
        let range = app.buttons["deck-graph-range"]
        XCTAssertTrue(range.waitForExistence(timeout: 5))
        XCTAssertTrue(range.label.contains("1 month"))
        let dates = app.descendants(matching: .any)["deck-graph-window"].firstMatch
        let initial = dates.label
        for name in ["Target", "Planned reviews", "No more reviews"] {
            let label = app.staticTexts["deck-curve-label-" + name]
            XCTAssertTrue(label.exists)
            XCTAssertGreaterThan(label.frame.intersection(app.frame).width, 0)
        }
        capture("Deck-One-Month", app)
        let chart = app.descendants(matching: .any)["deck-retention-chart"].firstMatch
        chart.swipeLeft()
        XCTAssertTrue(NSPredicate(format: "label != %@", initial).evaluate(with: dates))
        capture("Deck-Scrolled-Timeline", app)
        chart.swipeRight()
        XCTAssertNotEqual(dates.label, "")
        range.tap()
        app.buttons["Full horizon"].tap()
        XCTAssertTrue(range.label.contains("Full horizon"))
        capture("Deck-Full-Horizon", app)
    }
    @MainActor func testDailyReminderControls() {
        let app = launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 15))
        app.buttons["Settings"].tap()
        app.buttons.containing(.staticText, identifier: "Study").firstMatch.tap()
        let toggle = app.switches["daily-review-reminder"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        for _ in 0..<4 where !toggle.isHittable { app.swipeUp() }
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5))
        capture("Settings-Daily-Reminder", app)
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertFalse(app.datePickers.firstMatch.exists)
    }
    @MainActor func testLibrarySuspendAndContextMenus() {
        let app = launch(extra: ["--ui-image-fixture"])
        XCTAssertTrue(app.buttons["assistant-entry"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Your notebooks"].exists)
        XCTAssertFalse(app.buttons["Resume saved session"].exists)
        capture("Today-Simplified", app)
        app.buttons["tab-library"].tap()
        let deck = app.buttons["library-deck-ui-deck"]
        XCTAssertTrue(deck.waitForExistence(timeout: 5))
        deck.swipeLeft()
        XCTAssertTrue(app.buttons["Suspend deck"].waitForExistence(timeout: 5))
        capture("Library-Swipe-Suspend", app)
        app.buttons["Suspend deck"].tap()
        deck.swipeLeft()
        XCTAssertTrue(app.buttons["Resume deck"].waitForExistence(timeout: 5))
        app.buttons["Resume deck"].tap()
        deck.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Delete deck"].waitForExistence(timeout: 5))
        capture("Library-Deck-Context", app)
        app.buttons["Delete deck"].tap()
        XCTAssertTrue(app.buttons["Delete “AWS Cloud Practitioner”"].waitForExistence(timeout: 5))
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.25)).tap() }
        let file = app.buttons["library-file-9E2B947C-DBFC-4DF4-A15E-921021983344"]
        XCTAssertTrue(file.waitForExistence(timeout: 5))
        file.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Delete file"].waitForExistence(timeout: 5))
        capture("Library-File-Context", app)
    }
    @MainActor func testLibraryAndSettingsUtilityRoutes() {
        let app = launch()
        XCTAssertTrue(app.buttons["assistant-entry"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Import and export"].exists)
        XCTAssertFalse(app.buttons["screenshot-menu"].exists)
        capture("Today-Settings-Only", app)
        app.buttons["tab-library"].tap()
        let portability = app.buttons["library-import-export"]
        XCTAssertTrue(portability.waitForExistence(timeout: 5))
        capture("Library-Utility-Actions", app)
        app.buttons["Settings"].tap()
        let screenshots = app.buttons["settings-screenshot-all-pages"]
        for _ in 0..<5 where !screenshots.isHittable { app.swipeUp() }
        XCTAssertTrue(screenshots.isHittable)
        capture("Settings-Bottom-Utilities", app)
        screenshots.tap()
        XCTAssertTrue(app.buttons["capture-all-pages"].waitForExistence(timeout: 5))
    }
    @MainActor func testShortChatFitsItsContent() {
        let app = launch()
        XCTAssertTrue(app.buttons["assistant-entry"].waitForExistence(timeout:15)); app.buttons["assistant-entry"].tap()
        let composer = app.textFields["assistant-composer"].firstMatch.exists ? app.textFields["assistant-composer"].firstMatch : app.textViews["assistant-composer"].firstMatch
        composer.tap(); composer.typeText("Explain briefly")
        app.buttons["Send message"].tap()
        XCTAssertTrue(app.staticTexts["CloudFront is AWS’s content delivery network."].waitForExistence(timeout:5))
        let transcript = app.scrollViews["assistant-transcript"]
        XCTAssertTrue(transcript.exists)
        XCTAssertLessThan(transcript.frame.height,220)
        capture("Assistant-Short-Reply",app)
        app.buttons["Expand assistant"].tap()
        XCTAssertGreaterThan(transcript.frame.height,300)
    }
    @MainActor func testChatTitleSwitchingDeletionAndNewChat() {
        let app = launch(extra:["--ui-history-fixture"])
        XCTAssertTrue(app.buttons["assistant-entry"].waitForExistence(timeout:15))
        app.buttons["assistant-entry"].tap()
        XCTAssertFalse(app.buttons["Chat history"].exists)
        app.otherElements["assistant-drag-handle"].swipeUp()
        app.buttons["Chat history"].tap()
        let saved = app.buttons.containing(.staticText,identifier:"Explain AWS CloudFront").firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout:5)); saved.tap()
        XCTAssertTrue(app.staticTexts["CloudFront caches content near readers at edge locations."].waitForExistence(timeout:5))
        app.buttons["Chat history"].tap()
        saved.swipeLeft()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout:5)); app.buttons["Delete"].tap()
        XCTAssertFalse(saved.waitForExistence(timeout:2))
        app.otherElements["assistant-drag-handle"].swipeUp()
        app.buttons["Chat history"].tap()
        app.buttons["New chat"].tap()
        XCTAssertFalse(app.buttons["Chat history"].exists)
        capture("Assistant-New-Chat",app)
    }
    @MainActor func testChatFormulaRendering() {
        let app = launch()
        XCTAssertTrue(app.buttons["assistant-entry"].waitForExistence(timeout:15)); app.buttons["assistant-entry"].tap()
        let composer = app.textFields["assistant-composer"].firstMatch.exists ? app.textFields["assistant-composer"].firstMatch : app.textViews["assistant-composer"].firstMatch
        composer.tap(); composer.typeText("Show the quadratic formula")
        app.buttons["Send message"].tap()
        app.buttons["Expand assistant"].tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout:10))
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["For a quadratic equation, "].exists || app.webViews.count >= 2)
        capture("Assistant-Formula",app)
    }
    @MainActor func testLandscapeLongAnswersScrollIndependently() {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(extra:["--ui-review-mcq-fixture","--ui-long-mcq","--ui-eight-choices"])
        XCTAssertTrue(app.buttons["Start review"].waitForExistence(timeout:15))
        for _ in 0..<8 where !app.buttons["Start review"].isHittable { app.swipeUp() }
        app.buttons["Start review"].tap()
        let options = app.scrollViews["review-options-pane"]
        XCTAssertTrue(options.waitForExistence(timeout:5))
        let question = app.staticTexts["review-question"]
        let questionFrame = question.frame
        let correct = app.buttons["review-option-B"]
        options.swipeUp()
        for _ in 0..<12 where correct.frame.intersection(options.frame).height < 44 {
            if correct.frame.midY < options.frame.minY { options.swipeDown() }
            else { options.swipeUp() }
        }
        let visibleAnswer = correct.frame.intersection(options.frame)
        XCTAssertGreaterThanOrEqual(visibleAnswer.height,44)
        guard !visibleAnswer.isNull, visibleAnswer.height >= 44 else { return }
        XCTAssertEqual(question.frame.minY,questionFrame.minY,accuracy:2)
        XCTAssertLessThan(question.frame.maxX,correct.frame.minX)
        capture("Review-Landscape-Long",app)
        let answerPoint = app.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx:visibleAnswer.midX,dy:visibleAnswer.midY))
        answerPoint.tap(); answerPoint.tap()
        XCTAssertEqual(correct.value as? String,"Correct answer")
        let explanation = app.staticTexts["review-explanation"]
        XCTAssertTrue(explanation.waitForExistence(timeout:5))
        for _ in 0..<10 where explanation.frame.intersection(options.frame).height < 44 {
            if explanation.frame.midY < options.frame.minY { options.swipeDown() }
            else { options.swipeUp() }
        }
        XCTAssertGreaterThanOrEqual(explanation.frame.intersection(options.frame).height,44)
        capture("Review-Landscape-Long-Feedback",app)
    }

    @MainActor func testLandscapeAccessibilityUsesOneReadableColumn() {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(extra:["--ui-review-mcq-fixture","--ui-long-mcq","--ui-large-text"])
        XCTAssertTrue(app.buttons["Start review"].waitForExistence(timeout:15))
        for _ in 0..<8 where !app.buttons["Start review"].isHittable { app.swipeUp() }
        app.buttons["Start review"].tap()
        XCTAssertTrue(app.scrollViews["review-mcq-stacked"].waitForExistence(timeout:5))
        XCTAssertFalse(app.scrollViews["review-options-pane"].exists)
        capture("Review-Landscape-Accessibility",app)
    }
    @MainActor func testMCQRotationPreservesSelectionAndFeedback() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(extra:["--ui-review-mcq-fixture"])
        XCTAssertTrue(app.buttons["Start review"].waitForExistence(timeout:15)); app.buttons["Start review"].tap()
        let correct = app.buttons["review-option-B"]
        XCTAssertTrue(correct.waitForExistence(timeout:5)); correct.tap()
        XCTAssertEqual(correct.value as? String,"Selected")
        let label = correct.label
        XCUIDevice.shared.orientation = .landscapeLeft
        let split = app.scrollViews["review-options-pane"]
        XCTAssertTrue(split.waitForExistence(timeout:5))
        let positioned = expectation(for:NSPredicate { _,_ in app.staticTexts["review-question"].frame.maxX < correct.frame.minX },evaluatedWith:app)
        wait(for:[positioned],timeout:5)
        XCTAssertEqual(correct.value as? String,"Selected"); XCTAssertEqual(correct.label,label)
        capture("Review-Landscape-Selected",app)
        correct.tap()
        XCTAssertTrue(app.staticTexts["review-explanation"].waitForExistence(timeout:5))
        capture("Review-Landscape-Feedback",app)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.scrollViews["review-mcq-stacked"].waitForExistence(timeout:5))
        XCTAssertEqual(correct.value as? String,"Correct answer"); XCTAssertEqual(correct.label,label)
        capture("Review-Rotated-Feedback",app)
    }

    @MainActor func testLongMCQAtLargestTextRemainsReachable() {
        let app = launch(extra:["--ui-review-mcq-fixture","--ui-long-mcq","--ui-eight-choices","--ui-largest-text","--ui-monochrome","--ui-dark"])
        XCTAssertTrue(app.buttons["Start review"].waitForExistence(timeout:15))
        for _ in 0..<8 where !app.buttons["Start review"].isHittable { app.swipeUp() }
        app.buttons["Start review"].tap()
        XCTAssertTrue(app.staticTexts["review-question"].waitForExistence(timeout:5))
        capture("Review-Long-Largest-Question",app)
        let correct = app.buttons["review-option-B"]
        let scroll = app.scrollViews["review-mcq-stacked"]
        for _ in 0..<18 where !correct.isHittable { scroll.swipeUp() }
        XCTAssertTrue(correct.isHittable); correct.tap(); correct.tap()
        XCTAssertEqual(correct.value as? String,"Correct answer")
        XCTAssertTrue(app.buttons["Next question"].waitForExistence(timeout:5))
        capture("Review-Long-Largest-Feedback",app)
        app.buttons["Next question"].tap()
        XCTAssertFalse(app.buttons["review-option-B"].exists)
    }

    @MainActor func testTwoChoiceQuestionAndQuietVoiceMenu() {
        let app = launch(extra:["--ui-review-mcq-fixture","--ui-two-choices","--ui-neutral"])
        XCTAssertTrue(app.buttons["Start review"].waitForExistence(timeout:15)); app.buttons["Start review"].tap()
        XCTAssertTrue(app.buttons["review-option-B"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["review-option-C"].exists)
        XCTAssertFalse(app.buttons["review-voice-mode"].exists)
        capture("Review-Two-Choices-Neutral",app)
        app.buttons["Review options"].tap()
        XCTAssertTrue(app.switches["Voice mode"].waitForExistence(timeout:5))
        capture("Review-Voice-Menu",app)
    }

    @MainActor func testMonochromeLightScreens() { verifyThemeScreens(dark:false) }
    @MainActor func testMonochromeDarkScreens() { verifyThemeScreens(dark:true) }

    @MainActor func testThemeChangeKeepsUnsubmittedAnswer() {
        let app = launch(extra:["--ui-review-mcq-fixture"])
        XCTAssertTrue(app.buttons["Start review"].waitForExistence(timeout:15)); app.buttons["Start review"].tap()
        let correct = app.buttons["review-option-B"]
        XCTAssertTrue(correct.waitForExistence(timeout:5)); correct.tap()
        let label = correct.label
        app.buttons["Review options"].tap()
        let picker = app.descendants(matching:.any)["review-theme-picker"].firstMatch
        for _ in 0..<6 where !picker.exists || !picker.isHittable { app.swipeUp() }
        XCTAssertTrue(picker.waitForExistence(timeout:5)); picker.tap()
        app.buttons["Engram Mono"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(correct.waitForExistence(timeout:5))
        XCTAssertEqual(correct.value as? String,"Selected"); XCTAssertEqual(correct.label,label)
        capture("Review-Mono-Selected",app)
        correct.tap()
        XCTAssertEqual(correct.value as? String,"Correct answer")
        capture("Review-Mono-Feedback",app)
    }

    @MainActor private func verifyThemeScreens(dark:Bool) {
        let prefix = dark ? "Mono-Black" : "Mono-White"
        let app = launch(extra:["--ui-monochrome","--ui-rich-theme-fixture"] + (dark ? ["--ui-dark"] : []))
        XCTAssertTrue(app.buttons["tab-library"].waitForExistence(timeout:15))
        capture(prefix + "-Today",app)
        app.buttons["assistant-entry"].tap()
        let composer = app.textFields["assistant-composer"].firstMatch.exists ? app.textFields["assistant-composer"].firstMatch : app.textViews["assistant-composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout:5)); composer.tap()
        composer.typeText("Explain CloudFront")
        capture(prefix + "-Chat-Keyboard",app)
        if app.keyboards.firstMatch.exists { XCTAssertLessThanOrEqual(composer.frame.maxY,app.keyboards.firstMatch.frame.minY + 2) }
        app.buttons["Send message"].tap()
        XCTAssertTrue(app.buttons["Expand assistant"].waitForExistence(timeout:5))
        app.buttons["Expand assistant"].tap()
        XCTAssertTrue(app.buttons["Collapse assistant"].waitForExistence(timeout:5))
        capture(prefix + "-Chat-Expanded",app)
        app.buttons["Close assistant"].tap()
        app.buttons["tab-library"].tap(); capture(prefix + "-Library",app)
        app.buttons["library-deck-ui-deck"].tap()
        XCTAssertTrue(app.buttons["deck-notes"].waitForExistence(timeout:5))
        capture(prefix + "-Deck",app)
        app.buttons["deck-notes"].tap()
        XCTAssertTrue(app.navigationBars["Notes"].waitForExistence(timeout:5))
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout:10))
        capture(prefix + "-Rich-Notes",app)
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["tab-activity"].tap(); capture(prefix + "-Activity",app)
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout:5))
        capture(prefix + "-Settings",app)
    }
    @MainActor func testLibraryCreatesPersistentEmptyFolder() {
        let app = launch()
        XCTAssertTrue(app.buttons["tab-library"].waitForExistence(timeout:15))
        app.buttons["tab-library"].tap()
        app.buttons["Add notebook or source file"].tap()
        app.buttons["New folder"].tap()
        let prompt = app.alerts["New folder"]
        XCTAssertTrue(prompt.waitForExistence(timeout:5))
        prompt.textFields.firstMatch.tap()
        prompt.textFields.firstMatch.typeText("Research")
        prompt.buttons["Create"].tap()
        XCTAssertTrue(app.buttons["library-folder-Research"].waitForExistence(timeout:5))
        capture("Library-Folder",app)
    }
    @MainActor func testLibraryOpensImportedImage() {
        let app = launch(extra:["--ui-image-fixture"])
        XCTAssertTrue(app.buttons["tab-library"].waitForExistence(timeout:15))
        app.buttons["tab-library"].tap()
        let file = app.buttons["library-file-9E2B947C-DBFC-4DF4-A15E-921021983344"]
        XCTAssertTrue(file.waitForExistence(timeout:5))
        file.tap()
        XCTAssertTrue(app.navigationBars["CloudFront diagram.jpg"].waitForExistence(timeout:5))
        capture("Library-Image-Reader",app)
    }

    @MainActor func testPDFSampleApprovalAndSourceLinkedSave() {
        let app = launch(extra: ["--ui-pdf-fixture"])
        XCTAssertTrue(app.buttons["tab-library"].waitForExistence(timeout: 15))
        app.buttons["tab-library"].tap()
        app.buttons["Add notebook or source file"].tap()
        app.buttons["New notebook"].tap()
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
        capture("Library-Explorer",app)
        XCTAssertTrue(app.buttons["library-deck-ui-deck"].waitForExistence(timeout: 5))
        app.buttons["library-deck-ui-deck"].tap()
        XCTAssertTrue(app.buttons["deck-actions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["deck-questions"].exists)
        XCTAssertTrue(app.buttons["deck-notes"].exists)
        capture("Deck-Flat-Outlook", app)
        XCTAssertFalse(app.staticTexts["7 days"].exists)
        let horizon = app.buttons["deck-forecast-horizon"]
        XCTAssertTrue(horizon.exists)
        horizon.tap()
        XCTAssertTrue(app.switches["Exam or target date"].waitForExistence(timeout: 5))
        let examToggle = app.switches["Exam or target date"]
        examToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let enabled = expectation(for: NSPredicate(format: "value == %@", "1"), evaluatedWith: examToggle)
        wait(for: [enabled], timeout: 5)
        XCTAssertTrue(app.datePickers.firstMatch.exists)
        capture("Deck-Exam-Date-Settings", app)
        app.buttons["Save"].tap()
        XCTAssertTrue(horizon.waitForExistence(timeout: 5))
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
        app.swipeUp()
        XCTAssertTrue(rail.isHittable)
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

    @MainActor func testAssistantHistorySurvivesReopening() {
        let app = launch(extra:["--ui-history-fixture"])
        let entry = app.buttons["assistant-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout:15)); entry.tap()
        XCTAssertFalse(app.staticTexts["CloudFront caches content near readers at edge locations."].exists)
        app.otherElements["assistant-drag-handle"].swipeUp()
        XCTAssertFalse(app.staticTexts["CloudFront caches content near readers at edge locations."].exists)
        app.buttons["Chat history"].tap()
        app.buttons.containing(.staticText,identifier:"Explain AWS CloudFront").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["CloudFront caches content near readers at edge locations."].waitForExistence(timeout:5))
        app.buttons["Close assistant"].tap()
        entry.tap()
        app.otherElements["assistant-drag-handle"].swipeUp()
        app.buttons["Chat history"].tap()
        XCTAssertTrue(app.staticTexts["Chats"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["New chat"].exists)
        capture("Assistant-History",app)
    }
    @MainActor func testMCQTextChoicesAndInlineExplanation() {
        let app = launch(extra:["--ui-review-mcq-fixture"])
        let start = app.buttons["Start review"]
        XCTAssertTrue(start.waitForExistence(timeout:15)); start.tap()
        let correct = app.buttons["review-option-B"]
        XCTAssertTrue(correct.waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts["Tap an option twice to confirm, or speak its letter or answer."].exists)
        capture("Review-MCQ-Choices",app)
        correct.tap()
        XCTAssertEqual(correct.value as? String,"Selected")
        capture("Review-MCQ-Selected",app)
        correct.tap()
        XCTAssertTrue(app.staticTexts["review-explanation"].waitForExistence(timeout:5))
        XCTAssertEqual(correct.value as? String,"Correct answer")
        capture("Review-MCQ-Feedback",app)
    }
    @MainActor func testMCQIncorrectChoiceShowsBothOutcomes() {
        let app = launch(extra:["--ui-review-mcq-fixture"])
        XCTAssertTrue(app.buttons["Start review"].waitForExistence(timeout:15))
        app.buttons["Start review"].tap()
        let wrong = app.buttons["review-option-A"]
        XCTAssertTrue(wrong.waitForExistence(timeout:5))
        wrong.tap(); wrong.tap()
        XCTAssertEqual(wrong.value as? String,"Your answer, incorrect")
        XCTAssertEqual(app.buttons["review-option-B"].value as? String,"Correct answer")
        XCTAssertTrue(app.staticTexts["review-explanation"].exists)
        capture("Review-MCQ-Incorrect",app)
    }
    @MainActor func testAssistantDragStagesAndKeyboardReturn() {
        let app = launch()
        let entry = app.buttons["assistant-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout:15)); entry.tap()
        let composer = app.textFields["assistant-composer"].firstMatch.exists ? app.textFields["assistant-composer"].firstMatch : app.textViews["assistant-composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout:5)); composer.tap()
        composer.typeText("Explain CloudFront")
        app.buttons["Send message"].tap()
        XCTAssertTrue(app.staticTexts["UI review fixture — no live AI request was made."].waitForExistence(timeout:5))
        let keyboard = app.keyboards.firstMatch
        let dismissed = XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in !keyboard.exists || keyboard.frame.minY >= app.frame.maxY },object:nil)
        wait(for:[dismissed],timeout:5)
        composer.tap()
        composer.typeText("More")
        XCTAssertTrue((composer.value as? String ?? "").contains("More"))
        XCTAssertTrue(keyboard.waitForExistence(timeout:5))
        XCTAssertGreaterThan(keyboard.frame.height,180)
        print("Keyboard return frames: keyboard=\(keyboard.frame), app=\(app.frame), composer=\(composer.frame)")
        if keyboard.frame.minY < app.frame.maxY {
            XCTAssertLessThanOrEqual(composer.frame.maxY,keyboard.frame.minY + 2)
        }
        XCTAssertTrue(app.staticTexts["UI review fixture — no live AI request was made."].isHittable)
        capture("Assistant-Keyboard-Return",app)
        let handle = app.otherElements["assistant-drag-handle"]
        XCTAssertTrue(handle.exists)
        handle.swipeUp()
        XCTAssertTrue(app.buttons["Collapse assistant"].waitForExistence(timeout:5))
        XCTAssertTrue(keyboard.exists)
        XCTAssertLessThan(keyboard.frame.minY,app.frame.maxY)
        app.buttons["Collapse assistant"].tap()
        XCTAssertTrue(keyboard.exists)
        app.buttons["Expand assistant"].tap()
        XCTAssertTrue(keyboard.exists)
        capture("Assistant-Expanded-Swipe",app)
        handle.swipeDown()
        XCTAssertTrue(app.buttons["Expand assistant"].waitForExistence(timeout:5))
        capture("Assistant-Medium-Swipe",app)
        XCTAssertTrue(keyboard.exists)
        handle.swipeDown()
        XCTAssertFalse(app.buttons["Chat history"].exists)
        capture("Assistant-Compact-Swipe",app)
        XCTAssertTrue(keyboard.exists)
        handle.swipeDown()
        XCTAssertTrue(entry.waitForExistence(timeout:5))
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

    @MainActor func testIPadScreenCaptures() {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch()
        XCTAssertTrue(app.buttons["Start review"].waitForExistence(timeout: 15))
        capture("iPad-Today", app)
        let sidebar = app.collectionViews["Sidebar"]
        XCTAssertTrue(sidebar.exists)
        sidebar.staticTexts["Library"].tap()
        XCTAssertTrue(app.buttons["library-deck-ui-deck"].waitForExistence(timeout: 5))
        capture("iPad-Library", app)
        app.buttons["library-deck-ui-deck"].tap()
        XCTAssertTrue(app.buttons["deck-notes"].waitForExistence(timeout: 5))
        let chart = app.descendants(matching: .any)["deck-retention-chart"].firstMatch
        let study = app.buttons["deck-study"]
        XCTAssertTrue(chart.exists)
        XCTAssertTrue(study.isHittable)
        XCTAssertLessThanOrEqual(chart.frame.maxX, study.frame.minX + 2)
        capture("iPad-Deck", app)
        app.buttons["deck-questions"].tap()
        XCTAssertTrue(app.navigationBars["Questions"].waitForExistence(timeout: 5))
        capture("iPad-Questions", app)
        app.navigationBars["Questions"].buttons.firstMatch.tap()
        app.buttons["deck-notes"].tap()
        XCTAssertTrue(app.navigationBars["Notes"].waitForExistence(timeout: 5))
        capture("iPad-Notes", app)
        app.navigationBars["Notes"].buttons.firstMatch.tap()
        sidebar.staticTexts["Activity"].tap()
        capture("iPad-Activity", app)
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        capture("iPad-Settings", app)
    }
    @MainActor func testIPadLandscapeReviewAndChatCaptures() {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(extra: ["--ui-review-mcq-fixture"])
        XCTAssertTrue(app.buttons["Start review"].waitForExistence(timeout: 15))
        app.buttons["Start review"].tap()
        let correct = app.buttons["review-option-B"]
        XCTAssertTrue(correct.waitForExistence(timeout: 5))
        capture("iPad-Review-MCQ", app)
        correct.tap()
        capture("iPad-Review-Selected", app)
        correct.tap()
        XCTAssertTrue(app.staticTexts["review-explanation"].waitForExistence(timeout: 5))
        capture("iPad-Review-Feedback", app)
        app.terminate()
        let chatApp = launch()
        XCTAssertTrue(chatApp.buttons["assistant-entry"].waitForExistence(timeout: 15))
        chatApp.buttons["assistant-entry"].tap()
        let composer = chatApp.textFields["assistant-composer"].firstMatch.exists ? chatApp.textFields["assistant-composer"].firstMatch : chatApp.textViews["assistant-composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap()
        composer.typeText("Explain CloudFront")
        capture("iPad-Chat-Keyboard", chatApp)
        chatApp.buttons["Send message"].tap()
        XCTAssertTrue(chatApp.buttons["Expand assistant"].waitForExistence(timeout: 5))
        capture("iPad-Chat-Response", chatApp)
        chatApp.buttons["Expand assistant"].tap()
        XCTAssertTrue(chatApp.buttons["Collapse assistant"].waitForExistence(timeout: 5))
        capture("iPad-Chat-Expanded", chatApp)
    }
    @MainActor private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-minimalist", "--ui-assistant-fixture"] + extra
        app.launch(); return app
    }
    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        let settled = expectation(description:"Surface animation settled")
        DispatchQueue.main.asyncAfter(deadline:.now() + 0.6) { settled.fulfill() }
        wait(for:[settled],timeout:2)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
