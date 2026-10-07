import XCTest

final class FrameReplyReleaseUITests: FrameReplyUITestCase {
    func testPersonaOnboardingRequiresSelectionAndPersistsDefault() throws {
        let app = launchShowcaseOnboarding()

        XCTAssertTrue(element("onboarding-persona-step", in: app).waitForExistence(timeout: 8))
        let continueButton = app.buttons["continue-from-persona"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 3))
        XCTAssertFalse(continueButton.isEnabled)

        app.buttons["onboarding-create-persona"].tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 3))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("onboarding-persona-step", in: app).waitForExistence(timeout: 3))

        let spark = element("onboarding-persona-card-spark", in: app)
        XCTAssertTrue(spark.waitForExistence(timeout: 3))
        spark.tap()
        XCTAssertTrue(continueButton.isEnabled)
        let selectedDefaultValue = try XCTUnwrap(spark.value as? String)
        XCTAssertFalse(selectedDefaultValue.isEmpty)
        continueButton.tap()

        XCTAssertTrue(element("onboarding-shortcuts-step", in: app).waitForExistence(timeout: 3))
        app.buttons["finish-onboarding"].tap()
        XCTAssertTrue(element("chats-screen", in: app).waitForExistence(timeout: 5))

        app.tabBars.buttons["app-tab-personas"].tap()
        let persistedSpark = element("persona-card-spark", in: app)
        XCTAssertTrue(persistedSpark.waitForExistence(timeout: 3))
        XCTAssertEqual(persistedSpark.value as? String, selectedDefaultValue)
    }

    func testFreshInstallCanLeaveProviderOnboardingForSettings() {
        let app = launchStandard(onboardingVersion: 0)

        XCTAssertTrue(element("onboarding-provider-step", in: app).waitForExistence(timeout: 8))
        app.buttons["continue-without-provider"].tap()
        let alert = app.alerts.firstMatch
        let skipAnyway = alert.buttons.matching(identifier: "confirm-skip-provider").firstMatch
        XCTAssertTrue(skipAnyway.waitForExistence(timeout: 3))
        alert.buttons.matching(identifier: "cancel-skip-provider").firstMatch.tap()
        XCTAssertTrue(element("onboarding-provider-step", in: app).waitForExistence(timeout: 3))

        app.buttons["continue-without-provider"].tap()
        XCTAssertTrue(skipAnyway.waitForExistence(timeout: 3))
        skipAnyway.tap()

        XCTAssertTrue(element("settings-screen", in: app).waitForExistence(timeout: 5))
    }

    func testCriticalNavigationAndPrivacyControlsAreReachable() {
        let app = launchStandard()
        let chats = app.tabBars.buttons["app-tab-chats"]
        let personas = app.tabBars.buttons["app-tab-personas"]
        let settings = app.tabBars.buttons["app-tab-settings"]
        XCTAssertTrue(chats.waitForExistence(timeout: 8))

        personas.tap()
        XCTAssertTrue(element("personas-screen", in: app).waitForExistence(timeout: 3))

        chats.tap()
        XCTAssertTrue(element("chats-screen", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["add-messages"].waitForExistence(timeout: 3))

        settings.tap()
        app.buttons["add-provider-header"].tap()
        XCTAssertTrue(app.secureTextFields["provider-api-key"].waitForExistence(timeout: 3))
        app.secureTextFields["provider-api-key"].tap()
        app.secureTextFields["provider-api-key"].typeText("synthetic-unsaved-key")
        app.buttons["close-add-provider"].tap()
        XCTAssertTrue(element("settings-screen", in: app).waitForExistence(timeout: 3))
        XCTAssertFalse(app.secureTextFields["provider-api-key"].exists)

        let privacyAndData = app.buttons["privacy-and-data"]
        XCTAssertTrue(scrollUntilHittable(privacyAndData, swiping: app.swipeUp))
        // Tap the blank gap before the chevron instead of a hittable text or icon.
        privacyAndData.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()

        XCTAssertTrue(element("privacy-and-data-screen", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(element("privacy-policy-link", in: app).exists)
        XCTAssertTrue(element("terms-link", in: app).exists)
        XCTAssertTrue(element("support-link", in: app).exists)
        XCTAssertTrue(
            scrollUntilHittable(element("delete-all-local-data", in: app), swiping: app.swipeUp)
        )
    }

    func testShortcutGuidesAreReachableFromSettings() {
        let app = launchShowcase()

        app.tabBars.buttons["app-tab-settings"].tap()

        let howTo = app.buttons["shortcut-how-to"]
        XCTAssertTrue(scrollUntilHittable(howTo, swiping: app.swipeUp))
        howTo.tap()

        XCTAssertTrue(element("shortcut-how-to-screen", in: app).waitForExistence(timeout: 3))
        let copiedText = element("shortcut-how-to-option-text", in: app)
        XCTAssertTrue(copiedText.waitForExistence(timeout: 3))
        copiedText.tap()
        XCTAssertTrue(
            element("shortcut-text-sender-label-tip", in: app).waitForExistence(timeout: 3)
        )
        app.buttons["dismiss-shortcut-how-to"].tap()

        let backTap = app.buttons["set-up-back-tap"]
        XCTAssertTrue(scrollUntilHittable(backTap, swiping: app.swipeUp))
        backTap.tap()

        XCTAssertTrue(element("back-tap-guide-screen", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(element("back-tap-tutorial-video", in: app).exists)
        XCTAssertTrue(app.buttons["add-image-shortcut-from-back-tap-guide"].exists)
        app.buttons["dismiss-back-tap-guide"].tap()
    }

    func testDictationLanguageFollowsAppChanges() throws {
        let app = launchShowcase()
        openMaya(in: app)
        let microphone = app.buttons["reply-guidance-field-microphone"]
        XCTAssertTrue(microphone.waitForExistence(timeout: 5))
        let originalLanguage = try XCTUnwrap(microphone.value as? String)
        XCTAssertFalse(originalLanguage.isEmpty)

        // Change only the app language: the device region stays en_US.
        app.terminate()
        let languageIndex = app.launchArguments.firstIndex(of: "-AppleLanguages")! + 1
        app.launchArguments[languageIndex] = "(zh-Hans)"
        app.launch()
        openMaya(in: app)
        XCTAssertTrue(microphone.waitForExistence(timeout: 5))
        let changedLanguage = try XCTUnwrap(microphone.value as? String)
        XCTAssertFalse(changedLanguage.isEmpty)
        XCTAssertNotEqual(changedLanguage, originalLanguage)

        app.terminate()
        app.launchArguments[languageIndex] = "(en)"
        app.launch()
        openMaya(in: app)
        XCTAssertTrue(microphone.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(originalLanguage, of: microphone))
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
        importedGuidance.tap()
        importedGuidance.typeText(" and keep it brief")
        let editedGuidance = importedGuidance.value as? String
        XCTAssertTrue(editedGuidance?.contains("Use this import context") == true)
        XCTAssertTrue(editedGuidance?.contains("and keep it brief") == true)
        app.buttons["close-add-messages"].tap()
        XCTAssertTrue(guidance.waitForExistence(timeout: 3))
        XCTAssertEqual(guidance.value as? String, editedGuidance)
    }
}
