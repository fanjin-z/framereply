import XCTest

@testable import zeptly

final class ScreenshotShortcutConfigurationTests: XCTestCase {
    func testInstallationURLValidation() {
        let cases: [(String, Bool)] = [
            ("https://www.icloud.com/shortcuts/0123456789abcdef", true),
            ("", false),
            ("https://example.com/shortcuts/0123456789abcdef", false),
            ("https://www.icloud.com/drive/0123456789abcdef", false),
            ("https://www.icloud.com/shortcuts/", false)
        ]

        for (value, isValid) in cases {
            XCTAssertEqual(
                ScreenshotShortcutConfiguration.validatedInstallationURL(from: value) != nil,
                isValid,
                value
            )
        }
    }
}
