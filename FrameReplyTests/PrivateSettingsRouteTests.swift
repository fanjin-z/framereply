import Foundation
import XCTest

final class PrivateSettingsRouteTests: XCTestCase {
    func testProductionSourceContainsNoSettingsDeepLinks() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoot = repositoryRoot.appendingPathComponent("FrameReply", isDirectory: true)
        let forbiddenTokens = [
            "App" + "-Prefs",
            "prefs" + ":",
            "settings" + "-navigation:",
            "open" + "SettingsURLString",
            ".assistive" + "Touch"
        ]

        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: sourceRoot,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
        )

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            for token in forbiddenTokens {
                XCTAssertFalse(
                    source.contains(token),
                    "Production Settings deep link found in \(fileURL.lastPathComponent)"
                )
            }
        }
    }
}
