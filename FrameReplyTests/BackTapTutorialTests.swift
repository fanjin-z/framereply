import XCTest

@testable import FrameReply

final class BackTapTutorialTests: XCTestCase {
    @MainActor
    func testBundledTutorialVideoLoads() {
        XCTAssertTrue(BackTapTutorialPlayerModel().hasTutorialAsset)
    }
}
