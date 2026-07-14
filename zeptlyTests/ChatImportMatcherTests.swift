import XCTest

@testable import zeptly

@MainActor
final class ChatImportMatcherTests: XCTestCase {
    func testNameAndConfidenceMatchingPolicy() {
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
    }

    func testTranscriptEvidenceRequiresDistinctiveLocalSignals() {
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
            name: "Sarah Jenkins",
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
                name: $0,
                recentMessages: [
                    ChatCandidateMessage(sender: "user", text: repeatedOpener, timeLabel: "")
                ]
            )
        }
        let repeatedDecision = ChatImportMatcher.decision(
            analysis: repeatedAnalysis,
            candidates: repeatedCandidates
        )

        XCTAssertNil(repeatedDecision.confirmedChatID)
        XCTAssertNotEqual(repeatedDecision.transcriptEvidence, .strong)
    }

    func testDifferentObservedNamesRejectRepeatedOutgoingOpener() {
        let opener = "Hello, I am from China and I am learning Russian."
        let analysis = ChatImportAnalysis(
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
            name: "Inna",
            recentMessages: [ChatCandidateMessage(sender: "user", text: opener, timeLabel: "")]
        )

        let decision = ChatImportMatcher.decision(analysis: analysis, candidates: [inna])

        XCTAssertNil(decision.confirmedChatID)
        XCTAssertEqual(decision.reason, .displayNameConflict)
    }

    func testUniqueParticipantAliasConfirmsSelectedChat() {
        let analysis = makeAnalysis(
            title: "@sarah_work",
            confidence: 0.96,
            matchedChatID: "sarah-jenkins",
            titleSource: .participantLabel
        )
        let candidate = ChatMatchCandidate(
            id: "sarah-jenkins",
            name: "Sarah Jenkins",
            participantAliases: ["@Sarah_Work"],
            recentMessages: []
        )

        let decision = ChatImportMatcher.decision(
            analysis: analysis,
            candidates: [candidate]
        )

        XCTAssertEqual(decision.confirmedChatID, candidate.id)
        XCTAssertEqual(decision.reason, .confirmedParticipantAlias)
    }

    func testDuplicateParticipantAliasStillRequiresDiscriminator() {
        let analysis = makeAnalysis(
            title: "Alex",
            confidence: 0.98,
            matchedChatID: "alex-one"
        )
        let candidates = ["alex-one", "alex-two"].map {
            ChatMatchCandidate(
                id: $0,
                name: $0,
                participantAliases: ["Alex"],
                recentMessages: []
            )
        }

        let decision = ChatImportMatcher.decision(
            analysis: analysis,
            candidates: candidates
        )

        XCTAssertNil(decision.confirmedChatID)
        XCTAssertEqual(decision.reason, .duplicateDisplayName)
    }

    func testStrongTranscriptCanConfirmPreviouslyUnseenChangedName() {
        let incoming = "The reservation code is ZXQ-9182."
        let analysis = ChatImportAnalysis(
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
        let candidate = ChatMatchCandidate(
            id: "old-name",
            name: "Old Name",
            recentMessages: [
                ChatCandidateMessage(
                    sender: "other_participant",
                    text: incoming,
                    timeLabel: "8:42 PM"
                )
            ]
        )

        let decision = ChatImportMatcher.decision(
            analysis: analysis,
            candidates: [candidate]
        )

        XCTAssertEqual(decision.confirmedChatID, candidate.id)
        XCTAssertEqual(decision.reason, .confirmedTranscript)
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
        ChatMatchCandidate(id: "sarah-jenkins", name: "Sarah Jenkins", recentMessages: [])
    }

}
