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

    func testDictationRevisionsReplaceOnlyTheSelectedText() {
        let original = "Please say hello tomorrow."
        let range = original.range(of: "hello")!
        var draft = GuidanceDictationDraft(text: original, selection: range)
        XCTAssertEqual(draft.text, original, "Silence must not delete selected text.")

        draft.receive("good", isFinal: false)
        draft.receive("good morning", isFinal: false)
        XCTAssertEqual(draft.text, "Please say good morning tomorrow.")
        draft.receive("good morning", isFinal: true)
        draft.receive("to Maya", isFinal: false)
        draft.receive("to Mina", isFinal: true)
        XCTAssertEqual(draft.text, "Please say good morning to Mina tomorrow.")
        XCTAssertEqual(
            draft.original, original, "Discarding dictation must restore the original draft.")
    }

    func testDictationInsertsAtCursorAndPreservesChineseAndEmoji() {
        let original = "请明天回复👨‍👩‍👧‍👦。"
        let cursor = original.index(original.startIndex, offsetBy: 1)
        var draft = GuidanceDictationDraft(text: original, selection: cursor..<cursor)
        draft.receive("礼貌地", isFinal: false)
        draft.receive("简短地", isFinal: true)
        XCTAssertEqual(draft.text, "请简短地明天回复👨‍👩‍👧‍👦。")
    }

    func testDictationAppendsSafelyWhenSelectionNoLongerMatchesTextBoundaries() {
        let previousText = "Please keep this reply short."
        let previousCursor = previousText.endIndex..<previousText.endIndex
        let emoji = "👨‍👩‍👧‍👦"
        let insideEmoji = emoji.unicodeScalars.index(after: emoji.startIndex)
        let cases: [(String, Range<String.Index>, String)] = [
            ("Hi", previousCursor, "Hi there"),
            ("", previousText.startIndex..<previousText.endIndex, "there"),
            (emoji, insideEmoji..<insideEmoji, emoji + "there")
        ]

        for (text, staleSelection, expected) in cases {
            var draft = GuidanceDictationDraft(text: text, selection: staleSelection)
            XCTAssertEqual(draft.text, text)
            draft.receive("there", isFinal: true)
            XCTAssertEqual(draft.text, expected)
        }
    }

    func testLongDictationPreservesTheWholePhraseForEditingButCannotBeSubmitted() {
        let original = String(repeating: "好", count: 495)
        var draft = GuidanceDictationDraft(text: original)
        draft.receive("请明天下午再联系我。", isFinal: true)
        XCTAssertEqual(draft.text, original + "请明天下午再联系我。")
        XCTAssertFalse(DraftingInputLimits.canAccept(draft.text))
        XCTAssertThrowsError(try DraftingInputLimits.validated(draft.text))
    }

}
