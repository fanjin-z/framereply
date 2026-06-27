import XCTest
@testable import zeptly

@MainActor
final class ChatImportMatcherTests: XCTestCase {
    func testHighConfidenceNameEvidenceConfirmsCandidate() {
        let analysis = makeAnalysis(title: "Sarah Jenkins", confidence: 0.9)
        XCTAssertEqual(
            ChatImportMatcher.confirmedChatID(analysis: analysis, candidates: [candidate()]),
            "sarah-jenkins"
        )
    }

    func testHighConfidenceWithoutLocalEvidenceCreatesProvisionalChat() {
        let analysis = makeAnalysis(title: "Someone Else", confidence: 0.99)
        XCTAssertNil(ChatImportMatcher.confirmedChatID(analysis: analysis, candidates: [candidate()]))
    }

    func testLowConfidenceNeverAutomaticallyMatches() {
        let analysis = makeAnalysis(title: "Sarah Jenkins", confidence: 0.84)
        XCTAssertNil(ChatImportMatcher.confirmedChatID(analysis: analysis, candidates: [candidate()]))
    }

    func testTwoContiguousMessagesProvideLocalEvidence() {
        let messages = [
            AnalyzedChatMessage(sender: .contact, senderName: nil, text: "First", timestampLabel: nil),
            AnalyzedChatMessage(sender: .user, senderName: nil, text: "Second", timestampLabel: nil)
        ]
        let analysis = ChatImportAnalysis(
            conversationTitle: nil,
            participants: [],
            messages: messages,
            matchedChatID: "sarah-jenkins",
            matchConfidence: 0.9
        )
        let candidate = ChatMatchCandidate(
            id: "sarah-jenkins",
            name: "Sarah Jenkins",
            recentMessages: [
                ChatCandidateMessage(sender: "contact", text: "First", timeLabel: ""),
                ChatCandidateMessage(sender: "user", text: "Second", timeLabel: "")
            ]
        )

        XCTAssertEqual(
            ChatImportMatcher.confirmedChatID(analysis: analysis, candidates: [candidate]),
            "sarah-jenkins"
        )
    }

    private func makeAnalysis(title: String, confidence: Double) -> ChatImportAnalysis {
        ChatImportAnalysis(
            conversationTitle: title,
            participants: [],
            messages: [
                AnalyzedChatMessage(
                    sender: .contact,
                    senderName: nil,
                    text: "A new message",
                    timestampLabel: nil
                )
            ],
            matchedChatID: "sarah-jenkins",
            matchConfidence: confidence
        )
    }

    private func candidate() -> ChatMatchCandidate {
        ChatMatchCandidate(id: "sarah-jenkins", name: "Sarah Jenkins", recentMessages: [])
    }
}
