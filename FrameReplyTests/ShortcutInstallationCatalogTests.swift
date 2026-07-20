import XCTest

@testable import FrameReply

final class ShortcutInstallationCatalogTests: XCTestCase {
    func testCatalogDefinesStableShortcutIDs() {
        XCTAssertEqual(
            ShortcutInstallationCatalog.all.map(\.id),
            [.images, .text]
        )
    }

    func testAcceptsOnlyCanonicalICloudShortcutURLs() {
        let value = "https://www.icloud.com/shortcuts/abc123"

        XCTAssertEqual(
            ShortcutInstallationCatalog.validatedInstallationURL(from: value)?.absoluteString,
            value
        )

        let invalidValues = [
            "http://www.icloud.com/shortcuts/abc123",
            "https://icloud.com/shortcuts/abc123",
            "https://www.icloud.com/not-shortcuts/abc123",
            "https://www.icloud.com/shortcuts",
            ""
        ]
        for invalidValue in invalidValues {
            XCTAssertNil(
                ShortcutInstallationCatalog.validatedInstallationURL(from: invalidValue)
            )
        }
    }
}
