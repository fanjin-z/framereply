import XCTest

@testable import FrameReply

@MainActor
final class ChatImportMatcherTests: XCTestCase {
    func testNameConfidenceAndAliasMatchingPolicy() {
        let cases: [(String, String, Double, String?)] = [
            ("high-confidence local name", "Sarah Jenkins", 0.9, "sarah-jenkins"),
            ("no local name evidence", "Someone Else", 0.99, nil),
            ("below confidence threshold", "Sarah Jenkins", 0.84, nil)
        ]

        for (name, title, confidence, expectedID) in cases {
            let analysis = makeAnalysis(title: title, confidence: confidence)
            XCTAssertEqual(
                ChatImportMatcher.confirmedChatID(
                    analysis: analysis,
                    candidates: [candidate()]
                ),
                expectedID,
                name
            )
        }

        let aliasAnalysis = makeAnalysis(
            title: "@sarah_work",
            confidence: 0.96,
            matchedChatID: "sarah-jenkins",
            titleSource: .participantLabel
        )
        let aliasCandidate = ChatMatchCandidate(
            id: "sarah-jenkins",
            title: "Sarah Jenkins",
            participantAliases: ["@Sarah_Work"],
            recentMessages: []
        )
        XCTAssertEqual(
            ChatImportMatcher.confirmedChatID(
                analysis: aliasAnalysis,
                candidates: [aliasCandidate]
            ),
            aliasCandidate.id
        )

        let ambiguousCandidates = ["alex-one", "alex-two"].map {
            ChatMatchCandidate(
                id: $0,
                title: $0,
                participantAliases: ["Alex"],
                recentMessages: []
            )
        }
        XCTAssertNil(
            ChatImportMatcher.confirmedChatID(
                analysis: makeAnalysis(
                    title: "Alex",
                    confidence: 0.98,
                    matchedChatID: "alex-one"
                ),
                candidates: ambiguousCandidates
            )
        )
    }

    func testTranscriptEvidenceRequiresDistinctiveSignalsAndCanSurviveNameChanges() {
        let messages = [
            AnalyzedChatMessage(
                sender: .otherParticipant, senderName: nil, text: "First", timestampLabel: nil),
            AnalyzedChatMessage(sender: .user, senderName: nil, text: "Second", timestampLabel: nil)
        ]
        let analysis = ChatImportAnalysis(
            conversationTitle: nil,
            messages: messages,
            matchedChatID: "sarah-jenkins",
            matchConfidence: 0.9
        )
        let localCandidate = ChatMatchCandidate(
            id: "sarah-jenkins",
            title: "Sarah Jenkins",
            recentMessages: [
                ChatCandidateMessage(sender: "other_participant", text: "First", timeLabel: ""),
                ChatCandidateMessage(sender: "user", text: "Second", timeLabel: "")
            ]
        )
        XCTAssertEqual(
            ChatImportMatcher.confirmedChatID(
                analysis: analysis,
                candidates: [localCandidate]
            ),
            "sarah-jenkins"
        )

        let repeatedOpener = "Hello there"
        let repeatedAnalysis = ChatImportAnalysis(
            conversationTitle: nil,
            messages: [
                AnalyzedChatMessage(
                    sender: .user,
                    senderName: nil,
                    text: repeatedOpener,
                    timestampLabel: nil
                )
            ],
            matchedChatID: "one",
            matchConfidence: 0.99,
            conversationKind: .direct,
            titleSource: .unavailable
        )
        let repeatedCandidates = ["one", "two"].map {
            ChatMatchCandidate(
                id: $0,
                title: $0,
                recentMessages: [
                    ChatCandidateMessage(sender: "user", text: repeatedOpener, timeLabel: "")
                ]
            )
        }
        let repeatedMatch = ChatImportMatcher.confirmedChatID(
            analysis: repeatedAnalysis,
            candidates: repeatedCandidates
        )

        XCTAssertNil(repeatedMatch)

        let opener = "Hello, I am from China and I am learning Russian."
        let differentNameAnalysis = ChatImportAnalysis(
            conversationTitle: "Kristina",
            messages: [
                AnalyzedChatMessage(
                    sender: .user, senderName: nil, text: opener, timestampLabel: nil)
            ],
            matchedChatID: "inna",
            matchConfidence: 0.99,
            conversationKind: .direct,
            titleSource: .header
        )
        let inna = ChatMatchCandidate(
            id: "inna",
            title: "Inna",
            recentMessages: [ChatCandidateMessage(sender: "user", text: opener, timeLabel: "")]
        )

        let differentNameMatch = ChatImportMatcher.confirmedChatID(
            analysis: differentNameAnalysis,
            candidates: [inna]
        )

        XCTAssertNil(differentNameMatch)

        let incoming = "The reservation code is ZXQ-9182."
        let changedNameAnalysis = ChatImportAnalysis(
            conversationTitle: "New Profile Name",
            messages: [
                AnalyzedChatMessage(
                    sender: .otherParticipant,
                    senderName: "New Profile Name",
                    text: incoming,
                    timestampLabel: "8:42 PM"
                )
            ],
            matchedChatID: "old-name",
            matchConfidence: 0.98,
            conversationKind: .direct,
            titleSource: .header
        )
        let changedNameCandidate = ChatMatchCandidate(
            id: "old-name",
            title: "Old Name",
            recentMessages: [
                ChatCandidateMessage(
                    sender: "other_participant",
                    text: incoming,
                    timeLabel: "8:42 PM"
                )
            ]
        )

        let changedNameMatch = ChatImportMatcher.confirmedChatID(
            analysis: changedNameAnalysis,
            candidates: [changedNameCandidate]
        )

        XCTAssertEqual(changedNameMatch, changedNameCandidate.id)
    }

    func testFallbackTitlesNeverCreateIdentityMatches() {
        let analysis = ChatImportAnalysis(
            conversationTitle: "Imported Chat",
            messages: [
                AnalyzedChatMessage(
                    sender: .otherParticipant,
                    senderName: nil,
                    text: "Synthetic message A",
                    timestampLabel: nil
                )
            ],
            matchedChatID: "chat-gamma",
            matchConfidence: 0.99,
            conversationKind: .direct,
            titleSource: .header
        )
        let candidates = [
            ChatMatchCandidate(
                id: "chat-gamma",
                title: "Imported Chat",
                recentMessages: []
            ),
            ChatMatchCandidate(
                id: "chat-delta",
                title: "Imported Chat",
                recentMessages: []
            )
        ]

        XCTAssertNil(
            ChatImportMatcher.confirmedChatID(
                analysis: analysis,
                candidates: candidates
            )
        )
    }

    private func makeAnalysis(
        title: String,
        confidence: Double,
        matchedChatID: String = "sarah-jenkins",
        titleSource: ChatTitleSource = .header
    ) -> ChatImportAnalysis {
        ChatImportAnalysis(
            conversationTitle: title,
            messages: [
                AnalyzedChatMessage(
                    sender: .otherParticipant,
                    senderName: nil,
                    text: "A new message",
                    timestampLabel: nil
                )
            ],
            matchedChatID: matchedChatID,
            matchConfidence: confidence,
            conversationKind: .direct,
            titleSource: titleSource
        )
    }

    private func candidate() -> ChatMatchCandidate {
        ChatMatchCandidate(id: "sarah-jenkins", title: "Sarah Jenkins", recentMessages: [])
    }

}
