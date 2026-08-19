import XCTest

final class FrameReplyShowcaseScreenshotTests: FrameReplyUITestCase {
    func test01SuggestedReplies() {
        let app = launchShowcase()
        openMaya(in: app)

        XCTAssertTrue(element("chat-assistant-screen", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("reply-brief-summary", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(element("suggested-reply-1", in: app).waitForExistence(timeout: 3))
        let secondReply = element("suggested-reply-2", in: app)
        XCTAssertTrue(secondReply.waitForExistence(timeout: 3))
        XCTAssertTrue(secondReply.isHittable)

        let copyButtons = app.buttons.matching(
            NSPredicate(format: "label == %@", "Copy")
        )
        XCTAssertGreaterThanOrEqual(copyButtons.count, 2)
        let firstCopy = copyButtons.element(boundBy: 0)
        let secondCopy = copyButtons.element(boundBy: 1)
        XCTAssertTrue(firstCopy.isHittable)
        XCTAssertTrue(secondCopy.isHittable)
        XCTAssertEqual(firstCopy.frame.maxX, secondCopy.frame.maxX, accuracy: 2)
        let copyButtonRightEdge = secondCopy.frame.maxX
        XCTAssertGreaterThan(firstCopy.frame.midX, element("suggested-reply-1", in: app).frame.midX)
        XCTAssertGreaterThan(secondCopy.frame.midX, secondReply.frame.midX)
        XCTAssertLessThan(element("suggested-reply-1", in: app).frame.height, 120)
        XCTAssertLessThan(secondReply.frame.height, 120)

        firstCopy.tap()
        let copiedButton = app.buttons.matching(
            NSPredicate(format: "label == %@", "Copied")
        ).firstMatch
        XCTAssertTrue(copiedButton.waitForExistence(timeout: 2))
        XCTAssertEqual(copiedButton.frame.height, 44, accuracy: 1)
        XCTAssertLessThan(copiedButton.frame.width, 100)
        XCTAssertEqual(copiedButton.frame.maxX, copyButtonRightEdge, accuracy: 2)
        capture("01-suggested-replies")
    }

    func test02AddMessages() {
        let app = launchShowcase()
        let addMessages = app.buttons["add-messages"].firstMatch
        XCTAssertTrue(addMessages.waitForExistence(timeout: 5))
        addMessages.tap()

        let sheet = element("add-messages-screen", in: app)
        XCTAssertTrue(sheet.waitForExistence(timeout: 3))
        sheet.swipeUp()
        XCTAssertTrue(app.staticTexts["Add Messages"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["choose-screenshots"].isHittable)
        XCTAssertTrue(app.buttons["paste-copied-messages"].isHittable)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        capture("02-add-messages")
    }

    func test03ReplyBrief() {
        let app = launchShowcase()
        openMaya(in: app)
        let replyBrief = element("reply-brief-summary", in: app)
        XCTAssertTrue(replyBrief.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reply-brief-goal"].isHittable)
        XCTAssertTrue(app.buttons["reply-brief-persona"].isHittable)
        XCTAssertFalse(element("reply-brief-dialog", in: app).exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)

        app.buttons["reply-brief-goal"].tap()
        XCTAssertTrue(element("reply-goal-dialog", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(element("reply-brief-goal-input", in: app).isHittable)
        XCTAssertTrue(app.buttons["reply-goal-save"].isHittable)
        XCTAssertTrue(app.buttons["reply-goal-cancel"].isHittable)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))
        XCTAssertFalse(element("reply-guidance-field", in: app).exists)
        capture("03-reply-brief")

        element("reply-brief-goal-input", in: app).typeText("!")
        app.buttons["reply-goal-save"].tap()
        XCTAssertTrue(element("reply-goal-dialog", in: app).waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 2))
        XCTAssertTrue(element("reply-guidance-field", in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(
            element("assistant-reply-refresh-notice", in: app).waitForExistence(timeout: 2)
        )
    }

    func test04Chats() {
        let app = launchShowcase()
        XCTAssertTrue(element("chats-screen", in: app).waitForExistence(timeout: 5))
        for chatID in ["maya", "jordan", "riley", "sam"] {
            XCTAssertTrue(app.buttons["chat-card-showcase.\(chatID)"].waitForExistence(timeout: 3))
        }
        XCTAssertTrue(app.buttons["chat-card-showcase.sam"].isHittable)
        capture("04-chats")
    }

    func test05Personas() {
        let app = launchShowcase()
        let personasTab = app.buttons["app-tab-personas"]
        XCTAssertTrue(personasTab.waitForExistence(timeout: 5))
        personasTab.tap()

        XCTAssertTrue(element("personas-screen", in: app).waitForExistence(timeout: 3))
        for persona in ["professional", "spark", "thoughtful"] {
            XCTAssertTrue(element("persona-card-\(persona)", in: app).waitForExistence(timeout: 3))
        }
        let createPersona = app.buttons["Create New Persona"]
        XCTAssertTrue(createPersona.isHittable)
        capture("05-personas")

        createPersona.tap()
        XCTAssertTrue(app.staticTexts["New Persona"].waitForExistence(timeout: 3))
    }

    func test06ContextAndRationale() {
        let app = launchShowcase()
        openMaya(in: app)
        let details = element("open-chat-details", in: app)
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        details.tap()

        XCTAssertTrue(element("chat-details-screen", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(element("chat-details-back", in: app).isHittable)
        XCTAssertTrue(element("strategy-rationale-card", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(element("chat-memory-card", in: app).waitForExistence(timeout: 3))
        XCTAssertFalse(element("chat-details-top-bar", in: app).exists)
        XCTAssertFalse(app.buttons["Delete Chat"].exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        capture("06-context-and-rationale")
    }

    private func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 0.35)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
