import XCTest

@testable import FrameReply

final class ReplyRefreshNoticeStateTests: XCTestCase {
    func testNewScreenSessionStartsWithoutRefreshNotice() {
        var previousSession = ReplyRefreshNoticeState()
        previousSession.replyBriefChanged(hasExistingReplyCache: true)
        XCTAssertTrue(previousSession.isVisible)

        let newSession = ReplyRefreshNoticeState()
        XCTAssertFalse(newSession.needsRefresh)
        XCTAssertFalse(newSession.isVisible)
    }

    func testReplyBriefChangeRequiresExistingReplyCache() {
        var state = ReplyRefreshNoticeState()

        state.replyBriefChanged(hasExistingReplyCache: false)

        XCTAssertFalse(state.needsRefresh)
        XCTAssertFalse(state.isVisible)

        state.replyBriefChanged(hasExistingReplyCache: true)

        XCTAssertTrue(state.needsRefresh)
        XCTAssertTrue(state.isVisible)
    }

    func testDismissalLastsUntilAnotherReplyBriefChange() {
        var state = ReplyRefreshNoticeState()
        state.replyBriefChanged(hasExistingReplyCache: true)

        state.dismiss()

        XCTAssertTrue(state.needsRefresh)
        XCTAssertTrue(state.isDismissed)
        XCTAssertFalse(state.isVisible)

        state.replyBriefChanged(hasExistingReplyCache: true)

        XCTAssertFalse(state.isDismissed)
        XCTAssertTrue(state.isVisible)
    }

    func testSuccessfulGenerationClearsRefreshNotice() {
        var state = ReplyRefreshNoticeState()
        state.replyBriefChanged(hasExistingReplyCache: true)

        state.generationSucceeded()

        XCTAssertFalse(state.needsRefresh)
        XCTAssertFalse(state.isDismissed)
        XCTAssertFalse(state.isVisible)
    }
}
