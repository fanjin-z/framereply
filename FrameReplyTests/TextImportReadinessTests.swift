import XCTest

@testable import FrameReply

final class TextImportReadinessTests: XCTestCase {
    func testReadinessRequiresNamesOnlyForUnknownSenders() {
        let cases: [(String, [AnalyzedChatMessage], TextImportReadiness)] = [
            (
                "unknown senders without names",
                [
                    message(senderName: nil, text: "Could we move the meeting?"),
                    message(senderName: nil, text: "Tomorrow works for me.", timestamp: "10:16")
                ],
                .missingSenderMetadata
            ),
            (
                "resolved roles without names",
                [
                    message(sender: .otherParticipant, senderName: nil, text: "Did it arrive?"),
                    message(sender: .user, senderName: nil, text: "Yes, it arrived.")
                ],
                .ready
            ),
            (
                "explicit author labels",
                [
                    message(senderName: "Morgan", text: "Earlier train?"),
                    message(senderName: "Riley", text: "That works.")
                ],
                .ready
            ),
            (
                "partially labeled transcript",
                [
                    message(senderName: "Casey", text: "Confirmed."),
                    message(senderName: "   ", text: "Thank you.")
                ],
                .missingSenderMetadata
            )
        ]

        for (name, messages, expected) in cases {
            XCTAssertEqual(readiness(messages), expected, name)
        }
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
