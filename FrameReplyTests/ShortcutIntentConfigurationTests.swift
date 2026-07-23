import XCTest

@testable import FrameReply

final class ShortcutIntentConfigurationTests: XCTestCase {
    func testEndToEndIntentsAskForContextByDefault() {
        XCTAssertTrue(SuggestRepliesFromChatImagesIntent().askForContext)
        XCTAssertTrue(SuggestRepliesFromChatTextIntent().askForContext)
    }
}
