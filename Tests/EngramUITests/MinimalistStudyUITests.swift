import XCTest

final class MinimalistStudyUITests: XCTestCase {
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
        XCTAssertTrue(app.staticTexts["CloudFront caches content near readers at edge locations."].waitForExistence(timeout:5))
        app.buttons["Close assistant"].tap()
        entry.tap()
        app.buttons["Chat history"].tap()
        XCTAssertTrue(app.staticTexts["Previous chats"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["Return to this screen's chat"].exists)
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
        capture("Assistant-Expanded-Swipe",app)
        handle.swipeDown()
        XCTAssertTrue(app.buttons["Expand assistant"].waitForExistence(timeout:5))
        capture("Assistant-Compact-Swipe",app)
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

    @MainActor private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-minimalist", "--ui-assistant-fixture"] + extra
        app.launch(); return app
    }
    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
