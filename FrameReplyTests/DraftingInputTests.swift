import XCTest

@testable import FrameReply

final class DraftingInputTests: XCTestCase {
    func testValidationTrimsBlankAndEnforcesFiveHundredGraphemeLimit() throws {
        let family = "👨‍👩‍👧‍👦"
        let composedAccent = "e\u{301}"
        let value =
            String(repeating: family, count: 250)
            + String(repeating: composedAccent, count: 250)

        XCTAssertEqual(value.count, 500)
        XCTAssertEqual(try DraftingInputLimits.validated(value), value)
        XCTAssertNil(try DraftingInputLimits.validated(" \n\t "))
        XCTAssertThrowsError(try DraftingInputLimits.validated(value + family)) { error in
            XCTAssertEqual(
                error as? DraftingInputError,
                .tooLong(maximum: DraftingInputLimits.maximumCharacterCount)
            )
        }
    }

    func testEditorCounterAndAcceptanceBoundaries() {
        XCTAssertFalse(
            DraftingInputLimits.shouldShowCounter(for: String(repeating: "a", count: 399))
        )
        XCTAssertTrue(
            DraftingInputLimits.shouldShowCounter(for: String(repeating: "a", count: 400))
        )
        XCTAssertTrue(DraftingInputLimits.canAccept(String(repeating: "👍🏽", count: 500)))
        XCTAssertFalse(DraftingInputLimits.canAccept(String(repeating: "👍🏽", count: 501)))
    }
}
