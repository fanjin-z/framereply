import XCTest

@testable import zeptly

@MainActor
final class ChatMessageMergerTests: XCTestCase {
    func testSequenceMergingPreservesOrderAndAddsOnlyUnseenMessages() {
        let cases: [([String], [String], [String], Int)] = [
            (["A", "B"], ["B", "C"], ["A", "B", "C"], 1),
            (["B", "C"], ["A", "B"], ["A", "B", "C"], 1),
            (["OK", "Later"], ["OK", "Later", "OK"], ["OK", "Later", "OK"], 1),
            (["A", "B", "C"], ["A", "X", "C"], ["A", "B", "X", "C"], 1)
        ]

        for (existing, imported, expected, insertedCount) in cases {
            let result = ChatMessageMerger.merge(
                existing: existing.map { message($0) },
                imported: imported.map { message($0) }
            )

            XCTAssertEqual(result.messages.map(\.text), expected)
            XCTAssertEqual(result.insertedMessageCount, insertedCount)
        }
    }

    func testTimestampAndFuzzyIdentityRules() {
        let original = message(
            "This is a sufficiently long message for one OCR mistake.", time: "10:42 AM")
        let typo = message(
            "This is a sufficiently long message for one OCR mistale.", time: "10:42 AM")
        let differentTime = message(
            "This is a sufficiently long message for one OCR mistale.", time: "10:43 AM")

        XCTAssertEqual(
            ChatMessageMerger.merge(existing: [original], imported: [typo]).insertedMessageCount,
            0
        )
        XCTAssertEqual(
            ChatMessageMerger.merge(existing: [original], imported: [differentTime])
                .insertedMessageCount,
            1
        )

        let repeatedAtNewTime = ChatMessageMerger.merge(
            existing: [message("OK", time: "10:42 AM")],
            imported: [message("OK", time: "10:43 AM")]
        )
        XCTAssertEqual(repeatedAtNewTime.messages.count, 2)
        XCTAssertEqual(repeatedAtNewTime.insertedMessageCount, 1)
    }

    func testUnknownSenderMatchesExistingTextAsLowConfidenceWildcard() {
        let existing = message("Same visible message", sender: .contact)
        let imported = message("Same visible message", sender: .unknown)

        let result = ChatMessageMerger.merge(existing: [existing], imported: [imported])

        XCTAssertEqual(result.insertedMessageCount, 0)
        XCTAssertEqual(result.messages.count, 1)
    }

    private func message(
        _ text: String,
        time: String = "",
        sender: AnalyzedMessageSender = .contact
    ) -> MergeMessage {
        MergeMessage(
            analyzed: AnalyzedChatMessage(
                sender: sender,
                senderName: nil,
                text: text,
                timestampLabel: time
            )
        )
    }
}
