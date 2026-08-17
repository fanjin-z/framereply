import XCTest

final class FrameReplyReleaseUITests: FrameReplyUITestCase {
    func testPersonaOnboardingRequiresSelectionAndPersistsDefault() {
        let app = launchShowcaseOnboarding()

        XCTAssertTrue(element("onboarding-persona-step", in: app).waitForExistence(timeout: 8))
        let continueButton = app.buttons["continue-from-persona"]
        XCTAssertTrue(continueButton.exists)
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

    func testPersonaCreatedDuringOnboardingBecomesDefault() {
        let app = launchShowcaseOnboarding()

        XCTAssertTrue(element("onboarding-persona-step", in: app).waitForExistence(timeout: 8))
        app.buttons["onboarding-create-persona"].tap()
        XCTAssertTrue(app.staticTexts["New Persona"].waitForExistence(timeout: 3))

        let name = app.textFields["e.g. Work Mode"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("Onboarding Persona")
        app.buttons["Create Persona"].tap()

        XCTAssertTrue(element("onboarding-persona-step", in: app).waitForExistence(timeout: 5))
        let continueButton = app.buttons["continue-from-persona"]
        XCTAssertTrue(continueButton.isEnabled)
        continueButton.tap()
        app.buttons["finish-onboarding"].tap()

        XCTAssertTrue(element("chats-screen", in: app).waitForExistence(timeout: 5))
        app.buttons["app-tab-personas"].tap()
        let createdPersona = app.staticTexts["Onboarding Persona"]
        XCTAssertTrue(createdPersona.waitForExistence(timeout: 3))
    }

    func testPersonaObservationTapEditSwipeRemoveAndVerticalScroll() {
        let app = launchShowcase()
        app.buttons["app-tab-personas"].tap()

        let professional = element("persona-card-professional", in: app)
        XCTAssertTrue(professional.waitForExistence(timeout: 3))
        professional.tap()
        XCTAssertTrue(element("persona-detail-screen", in: app).waitForExistence(timeout: 3))

        let rowIdentifierPrefix = "persona-observation-row-"
        let observationRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", rowIdentifierPrefix)
        ).firstMatch
        XCTAssertTrue(scrollUntilHittable(observationRow, swiping: app.swipeUp))

        let observationID = String(observationRow.identifier.dropFirst(rowIdentifierPrefix.count))
        XCTAssertFalse(observationID.isEmpty)
        let removeObservation = app.buttons["persona-observation-remove-\(observationID)"]

        let dragStart = observationRow.coordinate(
            withNormalizedOffset: CGVector(dx: 0.65, dy: 0.75)
        )
        let dragEnd = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.55, dy: 0.2)
        )
        dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
        let exampleCardTitle = app.staticTexts["Teach It Your Voice"]
        XCTAssertTrue(exampleCardTitle.waitForExistence(timeout: 3))
        XCTAssertTrue(exampleCardTitle.isHittable)
        XCTAssertFalse(removeObservation.exists)

        XCTAssertTrue(scrollUntilHittable(observationRow, swiping: app.swipeDown))
        observationRow.tap()
        let editor = element("persona-observation-editor-\(observationID)", in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Save"].exists)
        XCTAssertTrue(app.buttons["Cancel"].exists)
        app.buttons["Cancel"].tap()

        XCTAssertTrue(observationRow.waitForExistence(timeout: 3))
        observationRow.swipeLeft()
        XCTAssertTrue(removeObservation.waitForExistence(timeout: 3))
        removeObservation.tap()

        let removedRow = app.buttons["persona-observation-row-\(observationID)"]
        XCTAssertTrue(removedRow.waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.sheets.firstMatch.exists)
    }

    func testFreshInstallShowsProviderOnboardingAndExplicitEscapeOpensSettings() {
        let app = launchStandard(onboardingVersion: 0)

        XCTAssertTrue(element("onboarding-provider-step", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Connect a Model Provider"].exists)
        XCTAssertFalse(app.staticTexts["Add one provider to generate replies."].exists)

        app.buttons["Skip Setup"].tap()
        XCTAssertTrue(app.buttons["Skip Anyway"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Cancel"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(element("onboarding-provider-step", in: app).waitForExistence(timeout: 3))

        app.buttons["Skip Setup"].tap()
        app.buttons["Skip Anyway"].tap()

        XCTAssertTrue(element("settings-screen", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["app-tab-settings"].value as? String, "Current tab")
    }

    func testCriticalNavigationAndPrivacyControlsAreReachable() {
        let app = launchStandard()
        XCTAssertTrue(app.buttons["app-tab-chats"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["app-tab-personas"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["add-messages"].waitForExistence(timeout: 3))

        let settings = app.buttons["app-tab-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
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

    func testBottomNavigationExposesSelectedTabState() {
        let app = launchStandard()
        let chats = app.buttons["app-tab-chats"]
        let personas = app.buttons["app-tab-personas"]
        let settings = app.buttons["app-tab-settings"]
        XCTAssertTrue(chats.waitForExistence(timeout: 8))

        chats.tap()
        XCTAssertTrue(element("chats-screen", in: app).waitForExistence(timeout: 3))
        XCTAssertEqual(chats.value as? String, "Current tab")
        XCTAssertNotEqual(personas.value as? String, "Current tab")
        XCTAssertFalse(app.buttons["Create New Persona"].exists)

        personas.tap()
        XCTAssertTrue(element("personas-screen", in: app).waitForExistence(timeout: 3))
        XCTAssertEqual(personas.value as? String, "Current tab")
        XCTAssertNotEqual(chats.value as? String, "Current tab")
        XCTAssertTrue(app.buttons["Create New Persona"].isHittable)

        settings.tap()
        XCTAssertEqual(settings.value as? String, "Current tab")
        XCTAssertNotEqual(personas.value as? String, "Current tab")
        XCTAssertFalse(app.buttons["Create New Persona"].exists)
    }

    func testProviderConsentCanBeCancelledWithoutSaving() {
        let app = launchStandard(
            additionalArguments: ["-framereply.providerDataConsent.openAI.v1", "0"]
        )
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
        app.buttons["provider-consent-cancel"].firstMatch.tap()
        XCTAssertTrue(consentAlert.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["connect-provider"].exists)
        app.buttons["close-add-provider"].tap()
        XCTAssertTrue(addProvider.waitForExistence(timeout: 3))
    }

    func testPersonalInfoNavigationLearningAndComposerAreReachable() {
        let app = launchStandard()
        let settings = app.buttons["app-tab-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()
        let personalInfo = app.buttons["personal-info"]
        XCTAssertTrue(scrollUntilHittable(personalInfo, swiping: app.swipeUp))
        personalInfo.tap()

        XCTAssertTrue(element("personal-info-screen", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["Personal Info"].exists)
        XCTAssertTrue(app.staticTexts["Your Names in Chats"].exists)
        XCTAssertTrue(app.staticTexts["Facts About You"].exists)

        let learningToggle = app.switches["personal-info-learning-toggle"]
        XCTAssertTrue(learningToggle.waitForExistence(timeout: 3))
        let initialValue = (learningToggle.value as? String) ?? "1"
        let toggledValue = initialValue == "1" ? "0" : "1"
        learningToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(waitForValue(toggledValue, of: learningToggle))
        learningToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(waitForValue(initialValue, of: learningToggle))

        let composer = app.textFields["Add one short fact about yourself"]
        XCTAssertTrue(composer.exists)
        composer.tap()
        composer.typeText("UI test personal info")
        let addFact = app.buttons["add-personal-info-fact"]
        XCTAssertTrue(addFact.exists)
        XCTAssertTrue(addFact.isEnabled)
    }

    func testCriticalControlsRemainReachableAtLargestDynamicType() {
        let app = launchStandard(
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        )
        let chats = app.buttons["app-tab-chats"]
        XCTAssertTrue(chats.waitForExistence(timeout: 8))
        chats.tap()

        let addMessages = app.buttons["add-messages"].firstMatch
        XCTAssertTrue(addMessages.waitForExistence(timeout: 8))
        addMessages.tap()
        XCTAssertTrue(
            scrollUntilHittable(app.buttons["choose-screenshots"], swiping: app.swipeUp)
        )
        XCTAssertTrue(
            scrollUntilHittable(app.buttons["paste-copied-messages"], swiping: app.swipeUp)
        )
        let close = app.buttons["close-add-messages"]
        XCTAssertTrue(scrollUntilHittable(close, swiping: app.swipeDown))
        close.tap()

        let settings = app.buttons["app-tab-settings"]
        settings.tap()
        XCTAssertTrue(scrollUntilHittable(app.buttons["personal-info"], swiping: app.swipeUp))
        let privacy = app.buttons["privacy-and-data"]
        XCTAssertTrue(scrollUntilHittable(privacy, swiping: app.swipeUp))
        privacy.tap()
        XCTAssertTrue(element("privacy-and-data-screen", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(
            scrollUntilHittable(element("delete-all-local-data", in: app), swiping: app.swipeUp)
        )
    }

    func testChatsSearchAndDeleteCancellation() {
        let app = launchShowcase()
        let search = app.textFields["chats-search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Jordan")
        XCTAssertTrue(app.buttons["chat-card-showcase.jordan"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["chat-card-showcase.maya"].exists)

        app.buttons["clear-chat-search"].tap()
        let maya = app.buttons["chat-card-showcase.maya"]
        XCTAssertTrue(maya.waitForExistence(timeout: 3))
        maya.swipeLeft()
        let deleteChat = app.buttons["chat-delete-showcase.maya"]
        XCTAssertTrue(deleteChat.waitForExistence(timeout: 3))
        deleteChat.tap()

        let confirmation = app.sheets.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Delete chat with Maya?"].exists)
        XCTAssertTrue(confirmation.buttons["Delete Chat"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        XCTAssertTrue(confirmation.waitForNonExistence(timeout: 2))
    }

    func testChatMemoryTapToEditAndSwipeToDelete() {
        let app = launchShowcase(
            additionalArguments: ["--framereply-showcase-memory-list"]
        )
        openMaya(in: app)

        let details = element("open-chat-details", in: app)
        XCTAssertTrue(details.waitForExistence(timeout: 3))
        details.tap()

        let memoryID = "20000000-0000-4000-8000-000000000001"
        let memoryRow = element("chat-memory-row-\(memoryID)", in: app)
        let deleteMemory = app.buttons["chat-memory-delete-\(memoryID)"]
        XCTAssertTrue(scrollUntilHittable(memoryRow, swiping: app.swipeUp))

        let dragStart = memoryRow.coordinate(
            withNormalizedOffset: CGVector(dx: 0.65, dy: 0.75)
        )
        let dragEnd = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.55, dy: 0.2)
        )
        dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
        XCTAssertTrue(app.buttons["Delete Chat"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Delete Chat"].isHittable)
        XCTAssertFalse(deleteMemory.exists)
        app.swipeDown()
        XCTAssertTrue(scrollUntilHittable(memoryRow, swiping: app.swipeUp))

        memoryRow.tap()
        let editor = element("chat-memory-editor-\(memoryID)", in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Save"].exists)
        XCTAssertTrue(app.buttons["Cancel"].exists)
        app.buttons["Cancel"].tap()

        XCTAssertTrue(memoryRow.waitForExistence(timeout: 3))
        memoryRow.swipeLeft()
        XCTAssertTrue(deleteMemory.waitForExistence(timeout: 3))
        deleteMemory.tap()

        XCTAssertTrue(memoryRow.waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.sheets.firstMatch.exists)
    }

    func testReplyGuidancePersistsIntoImport() {
        let app = launchShowcase()
        openMaya(in: app)
        let addMessages = app.buttons["assistant-add-messages"]
        let guidance = element("reply-guidance-field", in: app)
        let submit = app.buttons["submit-reply-guidance"]
        XCTAssertTrue(addMessages.waitForExistence(timeout: 3))
        XCTAssertTrue(guidance.isHittable)
        XCTAssertFalse(submit.exists)

        guidance.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))
        guidance.typeText("Use this import context")
        XCTAssertTrue(submit.waitForExistence(timeout: 3))
        addMessages.tap()

        XCTAssertTrue(element("add-messages-screen", in: app).waitForExistence(timeout: 3))
        let importedGuidance = element("import-reply-guidance", in: app)
        XCTAssertTrue(importedGuidance.waitForExistence(timeout: 3))
        XCTAssertEqual(importedGuidance.value as? String, "Use this import context")
    }

    func testReplyGuidanceRemainsUsableAtAccessibilityTextSize() {
        let app = launchShowcase(
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        openMaya(in: app)

        let addMessages = app.buttons["assistant-add-messages"]
        XCTAssertTrue(addMessages.waitForExistence(timeout: 3))
        XCTAssertTrue(addMessages.isHittable, addMessages.debugDescription)
        XCTAssertGreaterThan(addMessages.frame.width, 100)
        XCTAssertTrue(element("reply-guidance-field", in: app).isHittable)
    }

    func testConversationTapDismissesGuidanceBeforeOpeningContent() {
        let app = launchShowcase()
        openMaya(in: app)
        let guidance = element("reply-guidance-field", in: app)
        let replyBrief = element("reply-brief-summary", in: app)
        let dialog = element("reply-brief-dialog", in: app)
        XCTAssertTrue(guidance.waitForExistence(timeout: 3))
        XCTAssertTrue(replyBrief.waitForExistence(timeout: 3))

        guidance.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))
        replyBrief.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 2))
        XCTAssertFalse(dialog.exists)

        replyBrief.tap()
        XCTAssertTrue(dialog.waitForExistence(timeout: 3))
    }
}
