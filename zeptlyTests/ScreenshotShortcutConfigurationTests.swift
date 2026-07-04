import XCTest

@testable import zeptly

final class ScreenshotShortcutConfigurationTests: XCTestCase {
    func testAcceptsCanonicalICloudShortcutURL() {
        let url = ScreenshotShortcutConfiguration.validatedInstallationURL(
            from: "https://www.icloud.com/shortcuts/0123456789abcdef"
        )

        XCTAssertEqual(url?.absoluteString, "https://www.icloud.com/shortcuts/0123456789abcdef")
    }

    func testRejectsEmptyOrNonICloudURLs() {
        XCTAssertNil(ScreenshotShortcutConfiguration.validatedInstallationURL(from: ""))
        XCTAssertNil(
            ScreenshotShortcutConfiguration.validatedInstallationURL(
                from: "https://example.com/shortcuts/0123456789abcdef"
            )
        )
    }

    func testRejectsUnexpectedICloudPaths() {
        XCTAssertNil(
            ScreenshotShortcutConfiguration.validatedInstallationURL(
                from: "https://www.icloud.com/drive/0123456789abcdef"
            )
        )
        XCTAssertNil(
            ScreenshotShortcutConfiguration.validatedInstallationURL(
                from: "https://www.icloud.com/shortcuts/"
            )
        )
    }
}
