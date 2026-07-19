import XCTest

final class FrameReplyReleaseUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFirstLaunchAndPrivacyControlsAreAccessible() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["Inbox"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Personas"].exists)
        XCTAssertTrue(app.buttons["Settings"].exists)
        XCTAssertTrue(app.buttons["Add messages"].exists)

        app.buttons["Settings"].tap()
        let privacyAndData = app.buttons["privacy-and-data"]
        XCTAssertTrue(privacyAndData.waitForExistence(timeout: 3))
        privacyAndData.tap()
        XCTAssertTrue(app.navigationBars["Privacy & Data"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["privacy-policy-link"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["terms-link"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["support-link"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["delete-all-local-data"].exists)
    }

    func testProviderConsentCanBeCancelledWithoutSaving() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Settings"].tap()
        app.buttons["Add model provider"].tap()

        XCTAssertTrue(app.buttons["Select provider"].waitForExistence(timeout: 3))
        app.buttons["Select provider"].tap()
        app.buttons["OpenAI"].tap()

        let apiKey = app.secureTextFields["Enter API key"]
        XCTAssertTrue(apiKey.waitForExistence(timeout: 3))
        apiKey.tap()
        apiKey.typeText("synthetic-key")

        app.buttons["Connect"].tap()
        XCTAssertTrue(app.alerts["Share chat content with OpenAI?"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Allow & Connect"].exists)
        app.buttons["Not Now"].tap()

        XCTAssertTrue(app.buttons["Connect"].exists)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Add model provider"].exists)
    }

    func testPrivacyScreenSupportsLargeDynamicType() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()
        app.buttons["Settings"].tap()

        let privacyAndData = app.buttons["privacy-and-data"]
        XCTAssertTrue(privacyAndData.waitForExistence(timeout: 3))
        privacyAndData.tap()
        XCTAssertTrue(app.navigationBars["Privacy & Data"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["delete-all-local-data"].exists)
    }
}
