import XCTest

@testable import FrameReply

final class DraftingInputTests: XCTestCase {
    func testAccepts499And500Characters() throws {
        let value499 = String(repeating: "a", count: 499)
        let value500 = String(repeating: "b", count: 500)

        XCTAssertEqual(try DraftingInputLimits.validated(value499), value499)
        XCTAssertEqual(try DraftingInputLimits.validated(value500), value500)
    }

    func testRejects501CharactersWithoutTruncating() {
        let value = String(repeating: "a", count: 501)

        XCTAssertThrowsError(try DraftingInputLimits.validated(value)) { error in
            XCTAssertEqual(
                error as? DraftingInputError,
                .tooLong(maximum: DraftingInputLimits.maximumCharacterCount)
            )
        }
    }

    func testCountsEmojiAndComposedUnicodeAsCharacters() throws {
        let family = "👨‍👩‍👧‍👦"
        let composedAccent = "e\u{301}"
        XCTAssertEqual(family.count, 1)
        XCTAssertEqual(composedAccent.count, 1)

        let value =
            String(repeating: family, count: 250)
            + String(repeating: composedAccent, count: 250)
        XCTAssertEqual(value.count, 500)
        XCTAssertEqual(try DraftingInputLimits.validated(value), value)

        XCTAssertThrowsError(
            try DraftingInputLimits.validated(value + family)
        )
    }

    func testWhitespaceOnlyBecomesNil() throws {
        XCTAssertNil(try DraftingInputLimits.validated(" \n\t "))
    }

    func testCounterStartsAt400Characters() {
        XCTAssertFalse(
            DraftingInputLimits.shouldShowCounter(
                for: String(repeating: "a", count: 399)
            )
        )
        XCTAssertTrue(
            DraftingInputLimits.shouldShowCounter(
                for: String(repeating: "a", count: 400)
            )
        )
    }

    func testEditorAcceptanceStopsAt500Graphemes() {
        XCTAssertTrue(
            DraftingInputLimits.canAccept(String(repeating: "👍🏽", count: 500))
        )
        XCTAssertFalse(
            DraftingInputLimits.canAccept(String(repeating: "👍🏽", count: 501))
        )
    }
}
