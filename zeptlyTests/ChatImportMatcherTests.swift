import UIKit
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

    func testDifferentObservedNamesRejectRepeatedOutgoingOpener() {
        let opener = "Hello, I am from China and I am learning Russian."
        let analysis = ChatImportAnalysis(
            conversationTitle: "Kristina",
            participants: ["Kristina"],
            messages: [
                AnalyzedChatMessage(sender: .user, senderName: nil, text: opener, timestampLabel: nil)
            ],
            matchedChatID: "inna",
            matchConfidence: 0.99,
            sourceApp: "Telegram",
            conversationKind: .direct,
            titleSource: .header,
            matchBasis: .distinctiveMessages
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

    func testRepeatedOutgoingMessageAcrossCandidatesIsNotStrongIdentityEvidence() {
        let opener = "Hello there"
        let analysis = ChatImportAnalysis(
            conversationTitle: nil,
            participants: [],
            messages: [AnalyzedChatMessage(sender: .user, senderName: nil, text: opener, timestampLabel: nil)],
            matchedChatID: "one",
            matchConfidence: 0.99,
            conversationKind: .direct,
            titleSource: .unavailable,
            matchBasis: .distinctiveMessages
        )
        let candidates = ["one", "two"].map {
            ChatMatchCandidate(
                id: $0,
                name: $0,
                recentMessages: [ChatCandidateMessage(sender: "user", text: opener, timeLabel: "")]
            )
        }

        let decision = ChatImportMatcher.decision(analysis: analysis, candidates: candidates)

        XCTAssertNil(decision.confirmedChatID)
        XCTAssertNotEqual(decision.transcriptEvidence, .strong)
    }

    func testUniqueStrongAvatarCanConfirmRenamedDirectChat() throws {
        let artifact = try makeAvatarArtifact()
        let analysis = makeAnalysis(
            title: "New Display Name",
            confidence: 0.97,
            matchedChatID: "old-name"
        )
        let candidate = ChatMatchCandidate(id: "old-name", name: "Old Name", recentMessages: [])

        let decision = ChatImportMatcher.decision(
            analysis: analysis,
            candidates: [candidate],
            avatarArtifact: artifact,
            storedAvatars: [storedAvatar(id: candidate.id, artifact: artifact)]
        )

        XCTAssertEqual(decision.confirmedChatID, candidate.id)
        XCTAssertEqual(decision.avatarEvidence, .strong)
        XCTAssertEqual(decision.reason, .confirmedAvatar)
    }

    func testCompetingStrongAvatarForcesReviewWithoutLocalReassignment() throws {
        let artifact = try makeAvatarArtifact()
        let selected = ChatMatchCandidate(id: "selected", name: "Selected", recentMessages: [])
        let other = ChatMatchCandidate(id: "other", name: "Other", recentMessages: [])
        let analysis = makeAnalysis(
            title: selected.name,
            confidence: 0.99,
            matchedChatID: selected.id
        )

        let decision = ChatImportMatcher.decision(
            analysis: analysis,
            candidates: [selected, other],
            avatarArtifact: artifact,
            storedAvatars: [
                storedAvatar(id: selected.id, artifact: artifact, hash: ~artifact.perceptualHash),
                storedAvatar(id: other.id, artifact: artifact)
            ]
        )

        XCTAssertNil(decision.confirmedChatID)
        XCTAssertEqual(decision.suggestedChatID, selected.id)
        XCTAssertEqual(decision.avatarEvidence, .competing)
        XCTAssertEqual(decision.reason, .competingAvatar)
    }

    func testDuplicateNamesRequireAndAcceptUniqueAvatarDiscriminator() throws {
        let artifact = try makeAvatarArtifact()
        let first = ChatMatchCandidate(id: "alex-one", name: "Alex", recentMessages: [])
        let second = ChatMatchCandidate(id: "alex-two", name: "Alex", recentMessages: [])
        let analysis = makeAnalysis(title: "Alex", confidence: 0.96, matchedChatID: first.id)

        let decision = ChatImportMatcher.decision(
            analysis: analysis,
            candidates: [first, second],
            avatarArtifact: artifact,
            storedAvatars: [
                storedAvatar(id: first.id, artifact: artifact),
                storedAvatar(id: second.id, artifact: artifact, hash: ~artifact.perceptualHash)
            ]
        )

        XCTAssertEqual(decision.confirmedChatID, first.id)
        XCTAssertEqual(decision.reason, .confirmedAvatar)
    }

    private func makeAnalysis(
        title: String,
        confidence: Double,
        matchedChatID: String = "sarah-jenkins"
    ) -> ChatImportAnalysis {
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
            matchedChatID: matchedChatID,
            matchConfidence: confidence
        )
    }

    private func candidate() -> ChatMatchCandidate {
        ChatMatchCandidate(id: "sarah-jenkins", name: "Sarah Jenkins", recentMessages: [])
    }

    private func storedAvatar(
        id: String,
        artifact: AvatarArtifact,
        hash: UInt64? = nil
    ) -> StoredAvatarFingerprint {
        StoredAvatarFingerprint(
            chatID: id,
            perceptualHash: hash ?? artifact.perceptualHash,
            featurePrintData: artifact.featurePrintData,
            quality: artifact.quality,
            revision: artifact.revision
        )
    }

    private func makeAvatarArtifact() throws -> AvatarArtifact {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 800))
        let image = renderer.image { context in
            UIColor(white: 0.08, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 800))
            UIColor.systemBlue.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 40, y: 80, width: 64, height: 64))
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 56, y: 94, width: 22, height: 22))
            context.fill(CGRect(x: 51, y: 121, width: 38, height: 17))
        }
        let bounds = NormalizedAvatarBounds(x: 0.1, y: 0.1, width: 0.16, height: 0.08)
        return try XCTUnwrap(
            AvatarIdentityService.extract(from: try XCTUnwrap(image.pngData()), bounds: bounds)
        )
    }
}
