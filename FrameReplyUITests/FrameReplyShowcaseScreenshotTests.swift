import XCTest

final class FrameReplyShowcaseScreenshotTests: FrameReplyUITestCase {
    func test01SuggestedReplies() {
        let app = launchShowcase()
        openMaya(in: app)

        XCTAssertTrue(element("chat-assistant-screen", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("reply-brief-summary", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(element("suggested-reply-1", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(element("suggested-reply-2", in: app).waitForExistence(timeout: 3))

        let copyButtons = app.buttons.matching(
            NSPredicate(format: "label == %@", "Copy")
        )
        let firstCopy = copyButtons.element(boundBy: 0)
        XCTAssertTrue(firstCopy.waitForExistence(timeout: 3))
        firstCopy.tap()
        let copiedButton = app.buttons.matching(
            NSPredicate(format: "label == %@", "Copied")
        ).firstMatch
        XCTAssertTrue(copiedButton.waitForExistence(timeout: 2))
        capture("01-suggested-replies")
    }

    func test02AddMessages() {
        let app = launchShowcase()
        let addMessages = app.buttons["add-messages"].firstMatch
        XCTAssertTrue(addMessages.waitForExistence(timeout: 5))
        addMessages.tap()

        let sheet = element("add-messages-screen", in: app)
        XCTAssertTrue(sheet.waitForExistence(timeout: 3))
        let chooseScreenshots = app.buttons["choose-screenshots"]
        let pasteMessages = app.buttons["paste-copied-messages"]
        XCTAssertTrue(chooseScreenshots.waitForExistence(timeout: 3))
        XCTAssertTrue(pasteMessages.waitForExistence(timeout: 3))
        let screen = app.frame
        let navigationBar = app.navigationBars["Add Messages"]
        let sheetTop = navigationBar.frame.maxY
        for option in [chooseScreenshots, pasteMessages] {
            XCTAssertGreaterThanOrEqual(option.frame.minY, sheetTop)
            XCTAssertLessThanOrEqual(option.frame.maxY, screen.maxY)
        }
        XCTAssertTrue(chooseScreenshots.isHittable)
        capture("02-add-messages")

        sheet.swipeUp()
        XCTAssertEqual(navigationBar.frame.maxY, sheetTop, accuracy: 1)
    }

    func test03ReplyBrief() {
        let app = launchShowcase(contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL")
        openMaya(in: app)
        let replyBrief = element("reply-brief-summary", in: app)
        XCTAssertTrue(replyBrief.waitForExistence(timeout: 5))
        let goal = app.buttons["reply-brief-goal"]
        let input = element("reply-brief-goal-input", in: app)
        func openGoalEditor() {
            // System hit testing can include content under a floating bar on iOS 26.
            let content = element("chat-assistant-screen", in: app)
            let composer = app.buttons["assistant-add-messages"]
            for _ in 0..<5 {
                let top = app.navigationBars.firstMatch.frame.maxY
                let bottom = composer.frame.minY
                if goal.frame.minY >= top && goal.frame.maxY < bottom { break }
                let moveUp = goal.frame.maxY >= bottom
                content.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: moveUp ? 0.5 : 0.2))
                    .press(
                        forDuration: 0.05,
                        thenDragTo: content.coordinate(
                            withNormalizedOffset: CGVector(dx: 0.5, dy: moveUp ? 0.15 : 0.5)))
            }
            XCTAssertTrue(goal.isHittable)
            goal.tap()
            XCTAssertTrue(input.waitForExistence(timeout: 3))
        }
        openGoalEditor()
        let originalGoal = input.value as? String ?? ""
        input.tap()
        input.typeText(" Draft")
        capture("03-reply-brief")
        app.buttons["reply-goal-cancel"].tap()
        openGoalEditor()
        XCTAssertEqual(input.value as? String, originalGoal)
        input.tap()
        input.typeText(" Saved")
        let savedGoal = input.value as? String
        app.buttons["reply-goal-save"].tap()
        openGoalEditor()
        XCTAssertEqual(input.value as? String, savedGoal)
    }

    func test04Chats() {
        let app = launchShowcase()
        XCTAssertTrue(element("chats-screen", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["chat-card-showcase.sam"].waitForExistence(timeout: 3))
        capture("04-chats")
    }

    func test05Personas() {
        let app = launchShowcase()
        let personasTab = app.tabBars.buttons["Personas"]
        XCTAssertTrue(personasTab.waitForExistence(timeout: 5))
        personasTab.tap()

        XCTAssertTrue(element("personas-screen", in: app).waitForExistence(timeout: 3))
        let createPersona = app.buttons["Create New Persona"]
        XCTAssertTrue(createPersona.waitForExistence(timeout: 3))
        capture("05-personas")
    }

    func test06ContextAndRationale() {
        let app = launchShowcase()
        openMaya(in: app)
        let details = element("open-chat-details", in: app)
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        details.tap()

        XCTAssertTrue(element("chat-details-screen", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(element("strategy-rationale-card", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(element("chat-memory-card", in: app).waitForExistence(timeout: 3))
        capture("06-context-and-rationale")

        let memoryID = "20000000-0000-4000-8000-000000000001"
        let memory = element("chat-memory-row-\(memoryID)", in: app)
        XCTAssertTrue(scrollUntilHittable(memory, swiping: app.swipeUp))
        memory.swipeLeft()
        let deleteMemory = app.buttons["chat-memory-delete-\(memoryID)"]
        XCTAssertTrue(deleteMemory.waitForExistence(timeout: 3))
        deleteMemory.tap()
        XCTAssertTrue(element("chat-memory-empty-state", in: app).waitForExistence(timeout: 3))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("chat-assistant-screen", in: app).waitForExistence(timeout: 3))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("chats-screen", in: app).waitForExistence(timeout: 3))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
