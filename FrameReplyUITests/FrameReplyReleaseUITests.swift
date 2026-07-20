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
        let privacyAndData = app.buttons["privacy-and-data"]
        XCTAssertTrue(privacyAndData.waitForExistence(timeout: 3))
        privacyAndData.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["privacy-and-data-screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["privacy-policy-link"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["terms-link"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["support-link"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["delete-all-local-data"].exists)
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
