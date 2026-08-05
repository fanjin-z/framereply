import XCTest

@testable import FrameReply

final class TextImportReadinessTests: XCTestCase {
    func testUnknownMessagesWithoutNamesAreRejected() {
        let messages = [
            message(senderName: nil, text: "Could we move the meeting?"),
            message(senderName: nil, text: "Tomorrow works for me.")
        ]

        XCTAssertEqual(readiness(messages), .missingSenderMetadata)
    }

    func testTimestampsWithoutAuthorsAreRejected() {
        let messages = [
            message(senderName: nil, text: "Are you nearby?", timestamp: "10:14"),
            message(senderName: nil, text: "I will arrive soon.", timestamp: "10:16")
        ]

        XCTAssertEqual(readiness(messages), .missingSenderMetadata)
    }

    func testResolvedSenderRolesWithoutNamesAreAccepted() {
        let messages = [
            message(sender: .otherParticipant, senderName: nil, text: "Did the parcel arrive?"),
            message(sender: .user, senderName: nil, text: "Yes, it arrived safely.")
        ]

        XCTAssertEqual(readiness(messages), .ready)
    }

    func testExplicitNamesWithUnresolvedRolesAreAccepted() {
        let messages = [
            message(senderName: "Morgan", text: "Should we book the earlier train?"),
            message(senderName: "Riley", text: "That gives us more time.")
        ]

        XCTAssertEqual(readiness(messages), .ready)
    }

    func testNamesWithoutTimestampsAreAccepted() {
        let messages = [
            message(senderName: "Avery", text: "I sent the revised outline."),
            message(senderName: "Jordan", text: "I will review it tonight.")
        ]

        XCTAssertEqual(readiness(messages), .ready)
    }

    func testPartiallyLabeledTranscriptIsRejectedEntirely() {
        let messages = [
            message(senderName: "Casey", text: "The reservation is confirmed."),
            message(senderName: "   ", text: "Great, thank you.")
        ]

        XCTAssertEqual(readiness(messages), .missingSenderMetadata)
    }

    private func readiness(_ messages: [AnalyzedChatMessage]) -> TextImportReadiness {
        TextImportReadiness(
            analysis: ChatImportAnalysis(
                conversationTitle: nil,
                messages: messages,
                matchedChatID: nil,
                matchConfidence: 0,
                conversationKind: .unknown,
                titleSource: .unavailable
            )
        )
    }

    private func message(
        sender: AnalyzedMessageSender = .unknown,
        senderName: String?,
        text: String,
        timestamp: String? = nil
    ) -> AnalyzedChatMessage {
        AnalyzedChatMessage(
            sender: sender,
            senderName: senderName,
            text: text,
            timestampLabel: timestamp
        )
    }
}
