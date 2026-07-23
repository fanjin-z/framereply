import XCTest

final class FrameReplyReleaseUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCriticalNavigationAndPrivacyControlsAreReachable() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["app-tab-chats"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["app-tab-personas"].waitForExistence(timeout: 3))

        let settings = app.buttons["app-tab-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["add-messages"].waitForExistence(timeout: 3))
        settings.tap()

        let privacyAndData = app.buttons["privacy-and-data"]
        XCTAssertTrue(
            scrollUntilHittable(privacyAndData, swiping: app.swipeUp)
        )
        privacyAndData.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["privacy-and-data-screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["privacy-policy-link"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["terms-link"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["support-link"].exists)
        XCTAssertTrue(
            scrollUntilHittable(
                app.descendants(matching: .any)["delete-all-local-data"],
                swiping: app.swipeUp
            )
        )
    }

    func testProviderConsentCanBeCancelledWithoutSaving() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-framereply.providerDataConsent.openAI.v1",
            "0"
        ]
        app.launch()

        let settings = app.buttons["app-tab-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()

        let addProvider = app.buttons["add-provider-header"]
        XCTAssertTrue(addProvider.waitForExistence(timeout: 3))
        addProvider.tap()

        XCTAssertTrue(app.buttons["select-provider"].waitForExistence(timeout: 3))
        app.buttons["select-provider"].tap()
        app.buttons["provider-choice-openAI"].tap()

        let apiKey = app.secureTextFields["provider-api-key"]
        XCTAssertTrue(apiKey.waitForExistence(timeout: 3))
        apiKey.tap()
        apiKey.typeText("synthetic-key")

        app.buttons["connect-provider"].tap()
        let consentAlert = app.alerts["Share chat content with OpenAI?"]
        XCTAssertTrue(consentAlert.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["provider-consent-allow"].firstMatch.exists)
        app.buttons["provider-consent-cancel"].firstMatch.tap()

        XCTAssertTrue(consentAlert.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["connect-provider"].exists)
        app.buttons["close-add-provider"].tap()
        XCTAssertTrue(addProvider.waitForExistence(timeout: 3))
    }

    func testNamesAndUsernamesNavigationIsReachable() throws {
        let app = XCUIApplication()
        app.launch()

        let settings = app.buttons["app-tab-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()

        let namesAndUsernames = app.buttons["names-and-usernames"]
        XCTAssertTrue(
            scrollUntilHittable(namesAndUsernames, swiping: app.swipeUp)
        )
        namesAndUsernames.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["names-and-usernames-screen"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.navigationBars["Names & Usernames"].exists)
    }

    func testCriticalControlsRemainReachableAtLargestDynamicType() throws {
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
        XCTAssertTrue(
            scrollUntilHittable(screenshots, swiping: app.swipeUp)
        )
        XCTAssertTrue(
            scrollUntilHittable(paste, swiping: app.swipeUp)
        )

        let closeAddMessages = app.buttons["close-add-messages"]
        XCTAssertTrue(
            scrollUntilHittable(closeAddMessages, swiping: app.swipeDown)
        )
        closeAddMessages.tap()

        let settings = app.buttons["app-tab-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.tap()

        let namesAndUsernames = app.buttons["names-and-usernames"]
        XCTAssertTrue(
            scrollUntilHittable(namesAndUsernames, swiping: app.swipeUp)
        )

        let privacyAndData = app.buttons["privacy-and-data"]
        XCTAssertTrue(
            scrollUntilHittable(privacyAndData, swiping: app.swipeUp)
        )
        privacyAndData.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["privacy-and-data-screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            scrollUntilHittable(
                app.descendants(matching: .any)["delete-all-local-data"],
                swiping: app.swipeUp
            )
        )
    }

    private func scrollUntilHittable(
        _ element: XCUIElement,
        timeout: TimeInterval = 3,
        maximumSwipes: Int = 4,
        swiping: () -> Void
    ) -> Bool {
        guard element.waitForExistence(timeout: timeout) else {
            return false
        }

        var swipeCount = 0
        while !element.isHittable, swipeCount < maximumSwipes {
            swiping()
            swipeCount += 1
        }

        return element.isHittable
    }
}
