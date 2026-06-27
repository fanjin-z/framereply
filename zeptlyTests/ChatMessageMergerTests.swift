import XCTest
@testable import zeptly

@MainActor
final class ChatMessageMergerTests: XCTestCase {
    func testOverlappingImportAddsOnlyUnseenSuffix() {
        let result = ChatMessageMerger.merge(
            existing: [message("A"), message("B")],
            imported: [message("B"), message("C")]
        )

        XCTAssertEqual(result.messages.map(\.text), ["A", "B", "C"])
        XCTAssertEqual(result.insertedMessageCount, 1)
    }

    func testOverlappingImportPlacesUnseenPrefixBeforeAnchor() {
        let result = ChatMessageMerger.merge(
            existing: [message("B"), message("C")],
            imported: [message("A"), message("B")]
        )

        XCTAssertEqual(result.messages.map(\.text), ["A", "B", "C"])
        XCTAssertEqual(result.insertedMessageCount, 1)
    }

    func testRepeatedMessagesRemainDistinctBySequencePosition() {
        let result = ChatMessageMerger.merge(
            existing: [message("OK"), message("Later")],
            imported: [message("OK"), message("Later"), message("OK")]
        )

        XCTAssertEqual(result.messages.map(\.text), ["OK", "Later", "OK"])
        XCTAssertEqual(result.insertedMessageCount, 1)
    }

    func testFuzzyMatchRequiresSameTimestamp() {
        let original = message("This is a sufficiently long message for one OCR mistake.", time: "10:42 AM")
        let typo = message("This is a sufficiently long message for one OCR mistale.", time: "10:42 AM")
        let differentTime = message("This is a sufficiently long message for one OCR mistale.", time: "10:43 AM")

        XCTAssertEqual(
            ChatMessageMerger.merge(existing: [original], imported: [typo]).insertedMessageCount,
            0
        )
        XCTAssertEqual(
            ChatMessageMerger.merge(existing: [original], imported: [differentTime]).insertedMessageCount,
            1
        )
    }

    func testIdenticalTextAtDifferentTimestampsRemainsDistinct() {
        let result = ChatMessageMerger.merge(
            existing: [message("OK", time: "10:42 AM")],
            imported: [message("OK", time: "10:43 AM")]
        )

        XCTAssertEqual(result.messages.count, 2)
        XCTAssertEqual(result.insertedMessageCount, 1)
    }

    private func message(_ text: String, time: String = "") -> MergeMessage {
        MergeMessage(
            analyzed: AnalyzedChatMessage(
                sender: .contact,
                senderName: nil,
                text: text,
                timestampLabel: time
            )
        )
    }
}
