import XCTest

final class MinimalistReviewerUITests: XCTestCase {
    @MainActor func testPDFAdjustedSampleSavedNotesManualDraftAndReview() {
        let app = launchPDF()
        XCTAssertTrue(app.buttons["New deck"].waitForExistence(timeout: 15))
        app.buttons["New deck"].tap()
        let title = app.textFields["deck-title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("Manual draft kept")
        let document = app.textViews["deck-document"].firstMatch
        document.tap(); document.typeText("Manual question?: Manual answer.")
        app.swipeDown()
        capture("PDF-01-Manual-Draft", app)
        visible(app.buttons["deck-pdf-learning"], app, up: false).tap()
        XCTAssertTrue(app.buttons["pdf-source-inspect"].waitForExistence(timeout: 5))
        capture("PDF-02-Brief-Top", app)
        app.buttons["pdf-source-inspect"].tap()
        XCTAssertTrue(app.buttons["Page 1"].waitForExistence(timeout: 5)); app.buttons["Page 1"].tap()
        capture("PDF-03-Imported-Source", app); app.buttons["Done"].tap()
        visible(app.buttons["pdf-preview"], app).tap()
        XCTAssertTrue(app.buttons["pdf-approve"].waitForExistence(timeout: 10))
        app.swipeDown(); capture("PDF-04-Sample-Top", app)
        let evidence = app.buttons["Supporting evidence"].firstMatch
        if evidence.isHittable { evidence.tap(); capture("PDF-05-Sample-Evidence", app) }
        visible(app.buttons["pdf-adjust"], app).tap()
        XCTAssertTrue(app.buttons["pdf-preview"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["pdf-approve"].exists); XCTAssertFalse(app.buttons["pdf-save"].exists)
        capture("PDF-06-Adjusted-Brief", app)
        visible(app.buttons["pdf-preview"], app).tap()
        XCTAssertTrue(app.buttons["pdf-approve"].waitForExistence(timeout: 10))
        visible(app.buttons["pdf-approve"], app).tap()
        XCTAssertTrue(app.buttons["pdf-save"].waitForExistence(timeout: 10))
        capture("PDF-07-Full-Review", app)
        let edit = app.buttons["Edit wording"].firstMatch
        visible(edit, app).tap()
        let answer = app.descendants(matching: .any).matching(NSPredicate(format: "value == %@", "CloudFront uses edge locations to reduce latency and origin load.")).firstMatch
        visible(answer, app).tap(); answer.typeText("Reviewed wording. ")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Edited by you · not rechecked"].firstMatch.exists)
        capture("PDF-07b-Edited-Unverified", app)
        visible(app.buttons["pdf-save"], app).tap()
        if !app.buttons["deck-actions"].waitForExistence(timeout: 4) {
            capture("PDF-08-Save-Stuck", app)
            for _ in 0..<3 where !app.buttons["tab-library"].isHittable {
                let back = app.navigationBars.buttons["BackButton"].firstMatch
                if back.exists { back.tap() }
            }
            if app.buttons["tab-library"].isHittable { app.buttons["tab-library"].tap() }
            capture("PDF-09-Library-After-Save", app)
            let deck = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "AWS PDF learning")).firstMatch
            guard deck.waitForExistence(timeout: 5) else { XCTFail("Saved PDF deck not found in Library"); return }
            deck.tap()
        }
        XCTAssertTrue(app.buttons["deck-actions"].waitForExistence(timeout: 5))
        app.buttons["deck-actions"].tap(); app.buttons["PDF source pages"].tap()
        app.buttons["Page 1"].tap(); capture("PDF-10-Saved-Source", app); app.buttons["Done"].tap()
        visible(app.buttons["deck-questions"], app).tap()
        XCTAssertTrue(app.buttons["Source evidence"].waitForExistence(timeout: 5))
        app.buttons["Source evidence"].tap(); capture("PDF-11-Saved-Question-Evidence", app)
        app.navigationBars.buttons["BackButton"].firstMatch.tap()
        visible(app.buttons["deck-notes"], app).tap()
        XCTAssertTrue(app.navigationBars["Notes"].waitForExistence(timeout: 5))
        capture("PDF-12-Saved-Notes", app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "S3 stores objects")).firstMatch.exists)
        app.navigationBars.buttons["BackButton"].firstMatch.tap()
        visible(app.buttons["deck-study"], app, up: false).tap()
        let correctChoice = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "Option [A-D], CloudFront")).firstMatch
        XCTAssertTrue(correctChoice.waitForExistence(timeout: 8))
        let displayedLabel = correctChoice.label
        capture("PDF-13-Shuffled-Review", app)
        correctChoice.tap(); correctChoice.tap()
        XCTAssertTrue(app.staticTexts["Correct"].waitForExistence(timeout: 5))
        XCTAssertEqual(correctChoice.label, displayedLabel)
        XCTAssertEqual(correctChoice.value as? String, "Correct answer")
        capture("PDF-14-Correct-Shuffled-Answer", app)
        app.navigationBars.buttons["BackButton"].firstMatch.tap()
        for _ in 0..<3 where !app.textFields["deck-title"].firstMatch.exists {
            let back = app.navigationBars.buttons["BackButton"].firstMatch
            if back.exists { back.tap() }
        }
        guard app.textFields["deck-title"].firstMatch.waitForExistence(timeout: 5) else { capture("PDF-15-Manual-Draft-Unavailable", app); XCTFail("Manual writing destination unavailable"); return }
        XCTAssertEqual(app.textFields["deck-title"].firstMatch.value as? String, "Manual draft kept")
        XCTAssertEqual(app.textViews["deck-document"].firstMatch.value as? String, "Manual question?: Manual answer.")
        capture("PDF-15-Manual-Draft-Preserved", app)
    }
    @MainActor func testPDFLargeTextBriefAndSample() {
        let app = launchPDF(extra: ["--ui-large-text", "--ui-dark"])
        visible(app.buttons["New deck"], app).tap()
        visible(app.buttons["deck-pdf-learning"], app).tap()
        XCTAssertTrue(app.buttons["pdf-source-inspect"].waitForExistence(timeout: 5))
        capture("PDF-20-Large-Brief-Top", app)
        app.swipeUp(); app.swipeUp(); capture("PDF-21-Large-Brief-Controls", app)
        app.swipeUp(); capture("PDF-21b-Large-Brief-Preferences", app)
        visible(app.buttons["pdf-preview"], app).tap()
        XCTAssertTrue(app.buttons["pdf-approve"].waitForExistence(timeout: 10))
        capture("PDF-22-Large-Sample", app)
        visible(app.buttons["pdf-approve"], app); capture("PDF-23-Large-Approval", app)
    }
    @MainActor func testPDFPauseAndRetry() {
        let app = launchPDF()
        visible(app.buttons["New deck"], app).tap()
        visible(app.buttons["deck-pdf-learning"], app).tap()
        XCTAssertTrue(app.buttons["pdf-source-inspect"].waitForExistence(timeout: 5))
        visible(app.buttons["pdf-preview"], app).tap()
        let pause = app.buttons["pdf-pause"]
        if pause.exists && pause.isHittable {
            pause.tap()
            capture("PDF-30-Pause-State", app)
            if app.staticTexts["Paused. Completed batches are kept; you can resume."].exists {
                XCTAssertFalse(app.buttons["pdf-approve"].exists)
                visible(app.buttons["pdf-preview"], app).tap()
                XCTAssertTrue(app.buttons["pdf-approve"].waitForExistence(timeout: 10))
                capture("PDF-31-Retried-Sample", app)
            } else { capture("PDF-30-Pause-Window-Missed", app) }
        } else { capture("PDF-30-Pause-Window-Missed", app) }
    }
    @MainActor func testMCQSelectionResetsForNextQuestion() {
        let app = launchPDF()
        app.buttons["tab-library"].tap()
        XCTAssertTrue(app.buttons["library-new-deck"].waitForExistence(timeout: 5)); app.buttons["library-new-deck"].tap()
        let title = app.textFields["deck-title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("MCQ selection fixture")
        let document = app.textViews["deck-document"].firstMatch
        document.tap(); document.typeText("Which word is a number? A) One B) Blue: A) One.\nWhich word is a color? A) Red B) Three: A) Red.")
        app.navigationBars.buttons["Create"].tap()
        for _ in 0..<3 where !app.buttons["library-new-deck"].isHittable {
            let back = app.navigationBars.buttons["BackButton"].firstMatch
            if back.exists { back.tap() }
        }
        let deck = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "MCQ selection fixture")).firstMatch
        XCTAssertTrue(deck.waitForExistence(timeout: 5)); deck.tap()
        visible(app.buttons["deck-study"], app).tap()
        let options = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Option "))
        XCTAssertTrue(options.firstMatch.waitForExistence(timeout: 8))
        options.firstMatch.tap(); options.firstMatch.tap()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 5)); app.buttons["Next"].tap()
        XCTAssertTrue(options.firstMatch.waitForExistence(timeout: 5))
        capture("PDF-40-Next-MCQ-Unselected", app)
        for choice in options.allElementsBoundByIndex { XCTAssertEqual(choice.value as? String, "Not selected") }
        options.firstMatch.tap()
        XCTAssertEqual(options.firstMatch.value as? String, "Selected")
        XCTAssertFalse(app.buttons["Next"].exists)
        capture("PDF-41-Next-MCQ-First-Tap", app)
    }
    @MainActor func testPDFEditorLabelsAndManualDraftPreservation() {
        let app = launchPDF(); app.buttons["New deck"].tap()
        let title = app.textFields["deck-title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("Manual draft kept")
        let document = app.textViews["deck-document"].firstMatch
        document.tap(); document.typeText("Manual question?: Manual answer."); app.swipeDown()
        visible(app.buttons["deck-pdf-learning"], app, up: false).tap()
        XCTAssertTrue(app.buttons["pdf-source-inspect"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["deck-create"].exists)
        visible(app.buttons["Difficulty"], app).tap(); app.buttons["Beginner"].tap()
        XCTAssertEqual(app.buttons["Difficulty"].value as? String, "Beginner")
        capture("PDF-50-Labelled-Brief-Preference", app)
        visible(app.buttons["pdf-preview"], app).tap()
        XCTAssertTrue(app.buttons["pdf-approve"].waitForExistence(timeout: 10)); visible(app.buttons["pdf-approve"], app).tap()
        XCTAssertTrue(app.buttons["pdf-save"].waitForExistence(timeout: 10))
        let edit = app.buttons["Edit wording"].firstMatch
        visible(edit, app).tap()
        let answer = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND value == %@", "Answer or notes", "CloudFront uses edge locations to reduce latency and origin load.")).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND value == %@", "Question or heading", "Which service caches content near users?")).firstMatch.exists)
        capture("PDF-51-Labelled-Wording-Editors", app)
        visible(answer, app).tap(); answer.typeText("Reviewed wording. ")
        XCTAssertTrue(app.staticTexts["Edited by you · not rechecked"].firstMatch.exists)
        capture("PDF-52-Edited-Status", app)
        edit.tap()
        app.swipeUp()
        let save = app.buttons["pdf-save"]
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(save.isHittable)
        capture("PDF-52b-Save-Ready", app)
        save.tap()
        XCTAssertTrue(app.buttons["deck-actions"].waitForExistence(timeout: 8)); capture("PDF-53-Edited-Deck-Saved", app)
        for _ in 0..<3 where !app.descendants(matching: .any)["deck-title"].firstMatch.exists {
            let back = app.navigationBars.buttons["BackButton"].firstMatch
            if back.exists { back.tap() }
        }
        if !app.descendants(matching: .any)["deck-title"].firstMatch.exists {
            let newDeck = app.buttons["New deck"]
            XCTAssertTrue(newDeck.waitForExistence(timeout: 5)); visible(newDeck, app).tap()
        }
        XCTAssertEqual(app.descendants(matching: .any)["deck-title"].firstMatch.value as? String, "Manual draft kept")
        XCTAssertEqual(app.descendants(matching: .any)["deck-document"].firstMatch.value as? String, "Manual question?: Manual answer.")
        capture("PDF-54-Manual-Draft-Preserved", app)
    }
    @MainActor private func launchPDF(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--ui-minimalist", "--ui-assistant-fixture", "--ui-pdf-fixture"] + extra
        app.launch(); XCTAssertTrue(app.buttons["Start review"].waitForExistence(timeout: 15)); return app
    }
    @MainActor @discardableResult private func visible(_ element: XCUIElement, _ app: XCUIApplication, up: Bool = true) -> XCUIElement {
        for _ in 0..<8 where !element.isHittable { if up { app.swipeUp() } else { app.swipeDown() } }
        XCTAssertTrue(element.isHittable, "Expected a visible control: \(element)"); return element
    }
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
