import XCTest

final class FrameReplyReleaseUITests: FrameReplyUITestCase {
    func testPersonaOnboardingRequiresSelectionAndPersistsDefault() {
        let app = launchShowcaseOnboarding()

        XCTAssertTrue(element("onboarding-persona-step", in: app).waitForExistence(timeout: 8))
        let continueButton = app.buttons["continue-from-persona"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 3))
        XCTAssertFalse(continueButton.isEnabled)

        let spark = element("onboarding-persona-card-spark", in: app)
        XCTAssertTrue(spark.waitForExistence(timeout: 3))
        spark.tap()
        XCTAssertTrue(continueButton.isEnabled)
        continueButton.tap()

        XCTAssertTrue(element("onboarding-shortcuts-step", in: app).waitForExistence(timeout: 3))
        app.buttons["finish-onboarding"].tap()
        XCTAssertTrue(element("chats-screen", in: app).waitForExistence(timeout: 5))

        app.buttons["app-tab-personas"].tap()
        let persistedSpark = element("persona-card-spark", in: app)
        XCTAssertTrue(persistedSpark.waitForExistence(timeout: 3))
        XCTAssertEqual(persistedSpark.value as? String, "Default persona")
    }

    func testFreshInstallCanLeaveProviderOnboardingForSettings() {
        let app = launchStandard(onboardingVersion: 0)

        XCTAssertTrue(element("onboarding-provider-step", in: app).waitForExistence(timeout: 8))
        app.buttons["Skip Setup"].tap()
        let skipAnyway = app.buttons["Skip Anyway"]
        XCTAssertTrue(skipAnyway.waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(element("onboarding-provider-step", in: app).waitForExistence(timeout: 3))

        app.buttons["Skip Setup"].tap()
        XCTAssertTrue(skipAnyway.waitForExistence(timeout: 3))
        skipAnyway.tap()

        XCTAssertTrue(element("settings-screen", in: app).waitForExistence(timeout: 5))
    }

    func testCriticalNavigationAndPrivacyControlsAreReachable() {
        let app = launchStandard()
        let chats = app.buttons["app-tab-chats"]
        let personas = app.buttons["app-tab-personas"]
        let settings = app.buttons["app-tab-settings"]
        XCTAssertTrue(chats.waitForExistence(timeout: 8))

        personas.tap()
        XCTAssertTrue(element("personas-screen", in: app).waitForExistence(timeout: 3))

        chats.tap()
        XCTAssertTrue(element("chats-screen", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["add-messages"].waitForExistence(timeout: 3))

        settings.tap()
        let privacyAndData = app.buttons["privacy-and-data"]
        XCTAssertTrue(scrollUntilHittable(privacyAndData, swiping: app.swipeUp))
        privacyAndData.tap()

        XCTAssertTrue(element("privacy-and-data-screen", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(element("privacy-policy-link", in: app).exists)
        XCTAssertTrue(element("terms-link", in: app).exists)
        XCTAssertTrue(element("support-link", in: app).exists)
        XCTAssertTrue(
            scrollUntilHittable(element("delete-all-local-data", in: app), swiping: app.swipeUp)
        )
    }

    func testReplyGuidancePersistsIntoImport() {
        let app = launchShowcase()
        openMaya(in: app)
        let addMessages = app.buttons["assistant-add-messages"]
        let guidance = element("reply-guidance-field", in: app)
        XCTAssertTrue(addMessages.waitForExistence(timeout: 3))
        XCTAssertTrue(guidance.waitForExistence(timeout: 3))

        guidance.tap()
        guidance.typeText("Use this import context")
        addMessages.tap()

        XCTAssertTrue(element("add-messages-screen", in: app).waitForExistence(timeout: 3))
        let importedGuidance = element("import-reply-guidance", in: app)
        XCTAssertTrue(importedGuidance.waitForExistence(timeout: 3))
        XCTAssertEqual(importedGuidance.value as? String, "Use this import context")
    }
}
