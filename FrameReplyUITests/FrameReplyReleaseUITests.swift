import UIKit
import XCTest

final class FrameReplyReleaseUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFirstLaunchAndPrivacyControlsAreAccessible() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["app-tab-inbox"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["app-tab-personas"].exists)
        XCTAssertTrue(app.buttons["app-tab-settings"].exists)
        XCTAssertTrue(app.buttons["add-messages"].exists)

        app.buttons["app-tab-settings"].tap()
        XCTAssertFalse(app.buttons["shortcut-setup-guide"].exists)
        let privacyAndData = app.buttons["privacy-and-data"]
        XCTAssertTrue(privacyAndData.waitForExistence(timeout: 3))
        privacyAndData.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["privacy-and-data-screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["privacy-policy-link"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["terms-link"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["support-link"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["delete-all-local-data"].exists)
        XCTAssertFalse(app.staticTexts["On This Device"].exists)
        XCTAssertFalse(app.staticTexts["Provider Sharing"].exists)
    }

    func testProviderConsentCanBeCancelledWithoutSaving() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["app-tab-settings"].tap()
        app.buttons["add-provider"].tap()

        XCTAssertTrue(app.buttons["select-provider"].waitForExistence(timeout: 3))
        app.buttons["select-provider"].tap()
        app.buttons["provider-choice-openAI"].tap()

        let apiKey = app.secureTextFields["provider-api-key"]
        XCTAssertTrue(apiKey.waitForExistence(timeout: 3))
        apiKey.tap()
        apiKey.typeText("synthetic-key")

        app.buttons["connect-provider"].tap()
        XCTAssertTrue(app.alerts["Share chat content with OpenAI?"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["provider-consent-allow"].firstMatch.exists)
        app.buttons["provider-consent-cancel"].firstMatch.tap()

        XCTAssertTrue(app.buttons["connect-provider"].exists)
        app.buttons["close-add-provider"].tap()
        XCTAssertTrue(app.buttons["add-provider"].exists)
    }

    func testAddMessagesSheetUsesCompactImportList() throws {
        let app = XCUIApplication()
        app.launch()

        let addMessages = app.buttons["add-messages"].firstMatch
        XCTAssertTrue(addMessages.waitForExistence(timeout: 8))
        addMessages.tap()

        let screenshots = app.buttons["choose-screenshots"]
        let paste = app.buttons["paste-copied-messages"]
        XCTAssertTrue(screenshots.waitForExistence(timeout: 3))
        XCTAssertTrue(paste.waitForExistence(timeout: 3))
        XCTAssertTrue(screenshots.isHittable)
        XCTAssertTrue(paste.isHittable)
        XCTAssertLessThan(screenshots.frame.maxY, paste.frame.minY)
        XCTAssertEqual(screenshots.frame.maxX, paste.frame.maxX, accuracy: 2)
        XCTAssertGreaterThanOrEqual(screenshots.frame.height, 44)
        // PasteButton reports its visible system capsule, while its 44-point layout slot
        // supplies the surrounding hit area.
        XCTAssertGreaterThanOrEqual(paste.frame.height, 32)
        XCTAssertEqual(app.buttons.matching(identifier: "paste-copied-messages").count, 1)
        XCTAssertTrue(app.staticTexts["Chat screenshots"].exists)
        XCTAssertTrue(app.staticTexts["Copied text"].exists)
        let clipboardDetail = app.staticTexts["Import text from your clipboard"]
        XCTAssertTrue(clipboardDetail.exists)
        XCTAssertGreaterThanOrEqual(paste.frame.midY, app.staticTexts["Copied text"].frame.minY)
        XCTAssertLessThanOrEqual(paste.frame.midY, clipboardDetail.frame.maxY)
        XCTAssertTrue(app.buttons["close-add-messages"].exists)
        let redundantCopy = app.staticTexts.matching(
            NSPredicate(
                format: "label == %@",
                "Copied text is sent to your selected provider for analysis. FrameReply stores the imported messages in its protected local database, but does not retain a separate copy of the source transcript."
            )
        ).firstMatch
        XCTAssertFalse(
            redundantCopy.exists
        )

        UIPasteboard.general.string = "Alex: Are we still meeting tomorrow?"
        XCTAssertTrue(paste.isEnabled)
        paste.tap()
        XCTAssertTrue(paste.waitForNonExistence(timeout: 3))
    }

    func testChooseScreenshotsPresentsPhotoPicker() throws {
        let app = XCUIApplication()
        app.launch()

        let addMessages = app.buttons["add-messages"].firstMatch
        XCTAssertTrue(addMessages.waitForExistence(timeout: 8))
        addMessages.tap()

        let screenshots = app.buttons["choose-screenshots"]
        XCTAssertTrue(screenshots.waitForExistence(timeout: 3))
        screenshots.tap()
        XCTAssertTrue(app.buttons["Cancel"].firstMatch.waitForExistence(timeout: 5))
    }

    func testAddMessagesSheetSupportsLargeDynamicType() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        let addMessages = app.buttons["add-messages"].firstMatch
        XCTAssertTrue(addMessages.waitForExistence(timeout: 8))
        addMessages.tap()

        let screenshots = app.buttons["choose-screenshots"]
        let paste = app.buttons["paste-copied-messages"]
        XCTAssertTrue(screenshots.waitForExistence(timeout: 3))
        XCTAssertTrue(screenshots.isHittable)
        XCTAssertTrue(paste.waitForExistence(timeout: 3))
        if !paste.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(paste.isHittable)
    }

    func testPrivacyScreenSupportsLargeDynamicType() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()
        app.buttons["app-tab-settings"].tap()

        let privacyAndData = app.buttons["privacy-and-data"]
        XCTAssertTrue(privacyAndData.waitForExistence(timeout: 3))
        privacyAndData.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["privacy-and-data-screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["delete-all-local-data"].exists)
    }
}
