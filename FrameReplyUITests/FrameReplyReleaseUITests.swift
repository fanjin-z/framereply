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

    func testBottomNavigationExposesSelectedTabState() throws {
        let app = XCUIApplication()
        app.launch()

        let chats = app.buttons["app-tab-chats"]
        let personas = app.buttons["app-tab-personas"]
        let settings = app.buttons["app-tab-settings"]

        XCTAssertTrue(chats.waitForExistence(timeout: 8))
        XCTAssertTrue(personas.waitForExistence(timeout: 3))
        XCTAssertTrue(settings.waitForExistence(timeout: 3))

        chats.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["chats-screen"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertEqual(chats.value as? String, "Current tab")
        XCTAssertNotEqual(personas.value as? String, "Current tab")
        XCTAssertNotEqual(settings.value as? String, "Current tab")

        personas.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["personas-screen"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertNotEqual(chats.value as? String, "Current tab")
        XCTAssertEqual(personas.value as? String, "Current tab")

        settings.tap()
        XCTAssertNotEqual(personas.value as? String, "Current tab")
        XCTAssertEqual(settings.value as? String, "Current tab")
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

    func testSettingsSectionsFollowPriorityOrder() throws {
        let app = XCUIApplication()
        app.launch()

        let settings = app.buttons["app-tab-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["settings-screen"]
                .waitForExistence(timeout: 3)
        )

        let personalization = app.staticTexts["Personalization"]
        let modelProviders = app.staticTexts["Model Providers"]
        let shortcuts = app.staticTexts["Shortcuts"]
        let privacyAndSupport = app.staticTexts["Privacy & Support"]

        XCTAssertTrue(personalization.exists)
        XCTAssertTrue(modelProviders.exists)
        XCTAssertTrue(shortcuts.exists)
        XCTAssertTrue(privacyAndSupport.exists)
        XCTAssertLessThan(personalization.frame.minY, modelProviders.frame.minY)
        XCTAssertLessThan(modelProviders.frame.minY, shortcuts.frame.minY)
        XCTAssertLessThan(shortcuts.frame.minY, privacyAndSupport.frame.minY)

        XCTAssertTrue(app.buttons["personal-info"].isHittable)
        XCTAssertTrue(app.buttons["add-provider-header"].isHittable)
    }

    func testPersonalInfoNavigationIsReachable() throws {
        let app = XCUIApplication()
        app.launch()

        let settings = app.buttons["app-tab-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()

        let personalInfo = app.buttons["personal-info"]
        XCTAssertTrue(
            scrollUntilHittable(personalInfo, swiping: app.swipeUp)
        )
        personalInfo.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["personal-info-screen"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.navigationBars["Personal Info"].exists)
        XCTAssertTrue(app.staticTexts["Your Names in Chats"].exists)
        XCTAssertTrue(app.staticTexts["Facts About You"].exists)
    }

    func testPersonalInfoComposerAndLearningToggleAreReachable() throws {
        let app = XCUIApplication()
        app.launch()

        let settings = app.buttons["app-tab-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()
        let personalInfo = app.buttons["personal-info"]
        XCTAssertTrue(scrollUntilHittable(personalInfo, swiping: app.swipeUp))
        personalInfo.tap()

        let learningToggle = app.switches["personal-info-learning-toggle"]
        XCTAssertTrue(learningToggle.waitForExistence(timeout: 3))
        let initialToggleValue = (learningToggle.value as? String) ?? "1"
        let toggledValue = initialToggleValue == "1" ? "0" : "1"
        learningToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(waitForValue(toggledValue, of: learningToggle))
        learningToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(waitForValue(initialToggleValue, of: learningToggle))

        let composer = app.textFields["Add one short fact about yourself"]
        XCTAssertTrue(composer.exists)
        composer.tap()
        composer.typeText("UI test personal info")
        let addFact = app.buttons["add-personal-info-fact"]
        XCTAssertTrue(addFact.exists)
        XCTAssertTrue(addFact.isEnabled)
    }

    func testCriticalControlsRemainReachableAtLargestDynamicType() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        let chats = app.buttons["app-tab-chats"]
        XCTAssertTrue(chats.waitForExistence(timeout: 8))
        chats.tap()

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

        let personalInfo = app.buttons["personal-info"]
        XCTAssertTrue(
            scrollUntilHittable(personalInfo, swiping: app.swipeUp)
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
        _ = element.waitForExistence(timeout: timeout)
        var swipeCount = 0
        while !element.exists || !element.isHittable, swipeCount < maximumSwipes {
            swiping()
            swipeCount += 1
        }

        return element.exists && element.isHittable
    }

    private func waitForValue(
        _ value: String,
        of element: XCUIElement,
        timeout: TimeInterval = 2
    ) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
