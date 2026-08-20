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
        sheet.swipeUp()
        XCTAssertTrue(app.buttons["choose-screenshots"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["paste-copied-messages"].waitForExistence(timeout: 3))
        capture("02-add-messages")
    }

    func test03ReplyBrief() {
        let app = launchShowcase()
        openMaya(in: app)
        let replyBrief = element("reply-brief-summary", in: app)
        XCTAssertTrue(replyBrief.waitForExistence(timeout: 5))
        let goal = app.buttons["reply-brief-goal"]
        XCTAssertTrue(goal.waitForExistence(timeout: 3))
        goal.tap()
        XCTAssertTrue(element("reply-goal-dialog", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(element("reply-brief-goal-input", in: app).waitForExistence(timeout: 3))
        capture("03-reply-brief")
    }

    func test04Chats() {
        let app = launchShowcase()
        XCTAssertTrue(element("chats-screen", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["chat-card-showcase.sam"].waitForExistence(timeout: 3))
        capture("04-chats")
    }

    func test05Personas() {
        let app = launchShowcase()
        let personasTab = app.buttons["app-tab-personas"]
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
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
