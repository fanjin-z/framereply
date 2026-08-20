import XCTest

@testable import FrameReply

final class BackTapTutorialTests: XCTestCase {
    @MainActor
    func testBundledTutorialVideoLoads() {
        XCTAssertTrue(BackTapTutorialPlayerModel().hasTutorialAsset)
    }

    @MainActor
    func testExternalNavigationTemporarilyDisablesAutomaticPictureInPicture() {
        let model = BackTapTutorialPlayerModel()

        XCTAssertTrue(model.allowsAutomaticPictureInPicture)

        model.pauseForExternalNavigation()
        XCTAssertFalse(model.allowsAutomaticPictureInPicture)

        model.resumeAfterExternalNavigation()
        XCTAssertTrue(model.allowsAutomaticPictureInPicture)
        model.stop()
    }
}
