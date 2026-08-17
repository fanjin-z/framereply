import XCTest

class FrameReplyUITestCase: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func launchStandard(
        contentSizeCategory: String? = nil,
        onboardingVersion: Int = OnboardingVersionForUITests.current,
        additionalArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-framereply.lastCompletedOnboardingVersion", "\(onboardingVersion)",
            "-framereply.installationMarker.v1", "YES"
        ]
        if let contentSizeCategory {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                contentSizeCategory
            ]
        }
        app.launchArguments += additionalArguments
        app.launch()
        return app
    }

    func launchShowcase(
        contentSizeCategory: String = "UICTContentSizeCategoryL"
    ) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += [
            "--framereply-showcase",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-UIPreferredContentSizeCategoryName", contentSizeCategory,
            "-UIAccessibilityReduceMotionEnabled", "YES"
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

    func launchShowcaseOnboarding() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += [
            "--framereply-showcase-onboarding",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-UIAccessibilityReduceMotionEnabled", "YES"
        ]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        return app
    }

    func openMaya(in app: XCUIApplication) {
        let maya = app.buttons["chat-card-showcase.maya"]
        XCTAssertTrue(maya.waitForExistence(timeout: 5))
        maya.tap()
    }

    func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    func scrollUntilHittable(
        _ element: XCUIElement,
        timeout: TimeInterval = 3,
        maximumSwipes: Int = 4,
        swiping: () -> Void
    ) -> Bool {
        _ = element.waitForExistence(timeout: timeout)
        var swipeCount = 0
        while (!element.exists || !element.isHittable) && swipeCount < maximumSwipes {
            swiping()
            swipeCount += 1
        }
        return element.exists && element.isHittable
    }

    func waitForValue(
        _ value: String,
        of element: XCUIElement,
        timeout: TimeInterval = 2
    ) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}

private enum OnboardingVersionForUITests {
    static let current = 1
}
