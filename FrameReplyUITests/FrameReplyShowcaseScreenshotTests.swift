import XCTest

final class FrameReplyShowcaseScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test01SuggestedReplies() {
        let app = launchShowcase()
        openMaya(in: app)

        XCTAssertTrue(element("chat-assistant-screen", in: app).waitForExistence(timeout: 5))
        let replyBrief = element("reply-brief-summary", in: app)
        XCTAssertTrue(replyBrief.waitForExistence(timeout: 3))
        XCTAssertTrue(element("suggested-reply-1", in: app).waitForExistence(timeout: 3))
        let secondReply = element("suggested-reply-2", in: app)
        XCTAssertTrue(secondReply.waitForExistence(timeout: 3))
        XCTAssertTrue(secondReply.isHittable)

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
        replyBrief.tap()

        XCTAssertTrue(element("reply-brief-dialog", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Shape the next suggested replies"].exists)
        XCTAssertTrue(app.staticTexts["Current Goal"].exists)
        XCTAssertTrue(app.buttons["Thoughtful"].exists)
        XCTAssertTrue(app.buttons["reply-brief-done"].isHittable)
        XCTAssertFalse(app.keyboards.firstMatch.exists)

        capture("03-reply-brief")
    }

    func test04Chats() {
        let app = launchShowcase()

        XCTAssertTrue(element("chats-screen", in: app).waitForExistence(timeout: 5))
        for chatID in ["maya", "jordan", "riley", "sam"] {
            XCTAssertTrue(
                app.buttons["chat-card-showcase.\(chatID)"].waitForExistence(timeout: 3)
            )
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
            XCTAssertTrue(
                element("persona-card-\(persona)", in: app).waitForExistence(timeout: 3)
            )
        }
        XCTAssertTrue(app.buttons["Create New Persona"].isHittable)

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
        XCTAssertFalse(app.keyboards.firstMatch.exists)

        capture("06-context-and-rationale")
    }

    func test07ChatsSearchAndActions() {
        let app = launchShowcase()

        let search = app.textFields["chats-search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Jordan")

        XCTAssertTrue(app.buttons["chat-card-showcase.jordan"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["chat-card-showcase.maya"].exists)

        let clearSearch = app.buttons["clear-chat-search"]
        XCTAssertTrue(clearSearch.waitForExistence(timeout: 3))
        clearSearch.tap()
        XCTAssertTrue(app.buttons["chat-card-showcase.maya"].waitForExistence(timeout: 3))

        let maya = app.buttons["chat-card-showcase.maya"]
        maya.swipeLeft()

        let deleteChat = app.buttons["chat-delete-showcase.maya"]
        XCTAssertTrue(deleteChat.waitForExistence(timeout: 3))
        deleteChat.tap()

        let confirmation = app.sheets.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Delete chat with Maya?"].waitForExistence(timeout: 3))
        XCTAssertTrue(confirmation.buttons["Delete Chat"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        XCTAssertFalse(confirmation.waitForExistence(timeout: 2))
    }

    func test08ChatsRemainUsableAtAccessibilityTextSize() {
        let app = launchShowcase(
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL"
        )

        let maya = app.buttons["chat-card-showcase.maya"]
        XCTAssertTrue(maya.waitForExistence(timeout: 5))
        XCTAssertTrue(maya.isHittable)
        XCTAssertTrue(app.buttons["add-messages"].firstMatch.isHittable)

        capture("07-chats-accessibility")
    }

    func test09ReplyGuidanceComposerIsPersistentAndSharesImportInput() {
        let app = launchShowcase()
        openMaya(in: app)

        let addMessages = app.buttons["assistant-add-messages"]
        let guidance = element("reply-guidance-field", in: app)
        let submit = app.buttons["submit-reply-guidance"]

        XCTAssertTrue(addMessages.waitForExistence(timeout: 3))
        XCTAssertTrue(addMessages.isHittable, addMessages.debugDescription)
        XCTAssertTrue(guidance.isHittable)
        XCTAssertFalse(submit.exists)
        let singleLineHeight = guidance.frame.height
        capture("08-reply-guidance")

        func tapGuidanceSurface(horizontal: CGFloat, vertical: CGFloat) {
            let addFrame = addMessages.frame
            let fieldLeft = addFrame.maxX + 12
            let fieldRight = app.frame.maxX - 24
            let point = CGPoint(
                x: fieldLeft + ((fieldRight - fieldLeft) * horizontal),
                y: addFrame.minY + (44 * vertical)
            )
            app.coordinate(
                withNormalizedOffset: CGVector(
                    dx: point.x / app.frame.width,
                    dy: point.y / app.frame.height
                )
            ).tap()
        }

        app.swipeUp()
        XCTAssertTrue(addMessages.isHittable)
        XCTAssertTrue(guidance.isHittable)

        tapGuidanceSurface(horizontal: 0.03, vertical: 0.12)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))
        guidance.typeText("Make it warmer\nKeep it concise")
        XCTAssertGreaterThan(guidance.frame.height, singleLineHeight)
        XCTAssertTrue(submit.waitForExistence(timeout: 3))
        XCTAssertTrue(submit.isHittable)

        submit.tap()
        XCTAssertTrue(submit.waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.keyboards.firstMatch.exists)

        tapGuidanceSurface(horizontal: 0.97, vertical: 0.88)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))
        guidance.typeText("Use this import context")
        XCTAssertTrue(submit.waitForExistence(timeout: 3))

        addMessages.tap()
        XCTAssertTrue(element("add-messages-screen", in: app).waitForExistence(timeout: 3))
        let importedGuidance = element("import-reply-guidance", in: app)
        XCTAssertTrue(importedGuidance.waitForExistence(timeout: 3))
        XCTAssertEqual(importedGuidance.value as? String, "Use this import context")
    }

    func test10ReplyGuidanceComposerAdaptsAtAccessibilityTextSize() {
        let app = launchShowcase(
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        openMaya(in: app)

        let addMessages = app.buttons["assistant-add-messages"]
        XCTAssertTrue(addMessages.waitForExistence(timeout: 3))
        XCTAssertTrue(addMessages.isHittable, addMessages.debugDescription)
        XCTAssertGreaterThan(addMessages.frame.width, 100)
        XCTAssertTrue(element("reply-guidance-field", in: app).isHittable)

        capture("09-reply-guidance-accessibility")
    }

    func test11ConversationContentConsumesFirstTapWhileGuidanceIsFocused() {
        let app = launchShowcase()
        openMaya(in: app)

        let guidance = element("reply-guidance-field", in: app)
        let replyBrief = element("reply-brief-summary", in: app)
        let replyBriefDialog = element("reply-brief-dialog", in: app)

        XCTAssertTrue(guidance.waitForExistence(timeout: 3))
        XCTAssertTrue(replyBrief.waitForExistence(timeout: 3))

        guidance.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))

        replyBrief.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 2))
        XCTAssertFalse(replyBriefDialog.exists)

        replyBrief.tap()
        XCTAssertTrue(replyBriefDialog.waitForExistence(timeout: 3))
    }

    func test12HistoryConsumesFirstTapWhileGuidanceIsFocused() {
        let app = launchShowcase()
        openMaya(in: app)

        let guidance = element("reply-guidance-field", in: app)
        let viewAllHistory = element("recent-chat-view-all", in: app)

        XCTAssertTrue(guidance.waitForExistence(timeout: 3))
        XCTAssertTrue(viewAllHistory.waitForExistence(timeout: 3))

        guidance.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))

        viewAllHistory.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Chat History"].exists)

        viewAllHistory.tap()
        XCTAssertTrue(app.staticTexts["Chat History"].waitForExistence(timeout: 3))
    }

    private func launchShowcase(
        contentSizeCategory: String = "UICTContentSizeCategoryL"
    ) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += [
            "--framereply-showcase",
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US",
            "-UIPreferredContentSizeCategoryName",
            contentSizeCategory,
            "-UIAccessibilityReduceMotionEnabled",
            "YES"
        ]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        let portraitExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in app.frame.height > app.frame.width },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [portraitExpectation], timeout: 3), .completed)
        XCTAssertTrue(element("chats-screen", in: app).waitForExistence(timeout: 8))
        return app
    }

    private func openMaya(in app: XCUIApplication) {
        let maya = app.buttons["chat-card-showcase.maya"]
        XCTAssertTrue(maya.waitForExistence(timeout: 5))
        maya.tap()
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 0.35)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
