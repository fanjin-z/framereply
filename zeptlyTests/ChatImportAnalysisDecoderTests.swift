import Foundation
import XCTest

@testable import zeptly

final class ChatImportAnalysisDecoderTests: XCTestCase {
    func testDecodesExactAndFencedJSON() throws {
        let exact = validJSON()
        XCTAssertEqual(try decode(exact).messages.first?.text, "Hello")
        XCTAssertEqual(try decode("\u{FEFF}  ```json\n\(exact)\n```  ").messages.first?.text, "Hello")
    }

    func testClassifiesInvalidResponses() {
        let missingMessages = validJSON().replacingOccurrences(
            of: #""messages""#,
            with: #""missingMessages""#
        )
        let wrongSender = validJSON().replacingOccurrences(
            of: #""sender":"contact""#,
            with: #""sender":42"#
        )
        let unknownCandidate = validJSON().replacingOccurrences(
            of: #""matchedChatID":null"#,
            with: #""matchedChatID":"unknown""#
        )
        let incompleteMessage = validJSON().replacingOccurrences(
            of: #""text":"Hello""#,
            with: #""text":"   ""#
        )
        let cases: [(String?, String?, StructuredOutputFailureKind, String?)] = [
            (nil, "stop", .emptyResponse, nil),
            (validJSON(), "length", .truncatedResponse, nil),
            ("{not json", "stop", .invalidJSON, nil),
            (missingMessages, "stop", .schemaMismatch, "messages"),
            (wrongSender, "stop", .schemaMismatch, "messages[0].sender"),
            (unknownCandidate, "stop", .invalidCandidateID, "matchedChatID"),
            (incompleteMessage, "stop", .incompleteMessages, "messages")
        ]

        for (content, finishReason, kind, path) in cases {
            assertFailure(content, finishReason: finishReason, kind: kind, path: path)
        }
    }

    func testRejectsLegacyOutputWithoutVisualContract() {
        let legacyJSON =
            #"{"conversationTitle":"Alex","messages":[{"sender":"contact","senderName":"Alex","text":"Hello","timestampLabel":null}]}"#
        assertFailure(
            legacyJSON,
            kind: .schemaMismatch,
            path: "ownershipConvention"
        )
    }

    func testUnknownIdentityMetadataStillDegradesConservatively() throws {
        let unknownMetadataJSON = validJSON()
            .replacingOccurrences(of: #""conversationKind":"direct""#, with: #""conversationKind":"one_to_one""#)
            .replacingOccurrences(of: #""titleSource":"header""#, with: #""titleSource":"guessed""#)
        let unknownMetadata = try decode(unknownMetadataJSON)

        XCTAssertEqual(unknownMetadata.messages.first?.text, "Hello")
        XCTAssertEqual(unknownMetadata.conversationKind, .unknown)
        XCTAssertEqual(unknownMetadata.titleSource, .unavailable)
    }

    func testRejectsNavigationCountAsConversationTitle() throws {
        let result = try decode(
            validJSON().replacingOccurrences(
                of: #""conversationTitle":"Alex""#,
                with: #""conversationTitle":"19""#
            )
        )

        XCTAssertNil(result.conversationTitle)
        XCTAssertEqual(result.titleSource, .unavailable)
    }

    func testSeparatesQuotedReplyFromOuterMessageAndCorrectsSenderFromOuterAlignment() throws {
        let json = validJSON(
            sender: "user",
            text: "I remember",
            quotedReply: #"{"sender":"user","senderName":null,"text":"I live in Guangzhou"}"#
        )

        let result = try decode(json)

        XCTAssertEqual(result.messages.count, 1)
        XCTAssertEqual(result.messages[0].sender, .contact)
        XCTAssertEqual(result.messages[0].text, "I remember")
        XCTAssertEqual(result.messages[0].quotedReply?.text, "I live in Guangzhou")
    }

    func testConflictingOuterEvidenceBecomesUnknown() throws {
        let json = validJSON(
            sender: "user",
            senderEvidence: "message_status_indicator",
            outerAlignment: "left"
        )

        XCTAssertEqual(try decode(json).messages.first?.sender, .unknown)
    }

    func testExplicitLeftMessageStatusEvidenceSupportsLeftOwner() throws {
        let json = validJSON(
            sender: "user",
            senderEvidence: "message_status_indicator",
            outerAlignment: "left"
        ).replacingOccurrences(
            of: #""screenshotOwnerAlignment":"right""#,
            with: #""screenshotOwnerAlignment":"left""#
        )

        XCTAssertEqual(try decode(json).messages.first?.sender, .user)
    }

    func testMessageStatusEvidenceSupportsRightOwner() throws {
        let json = validJSON(
            sender: "user",
            senderEvidence: "message_status_indicator",
            outerAlignment: "right"
        )

        XCTAssertEqual(try decode(json).messages.first?.sender, .user)
    }

    func testAlignmentConventionWorksWithoutMessageStatusIndicator() throws {
        let json = validJSON(sender: "user", outerAlignment: "right")

        XCTAssertEqual(try decode(json).messages.first?.sender, .user)
    }

    func testLegacyOutboundIndicatorKeyIsIgnored() throws {
        let json = validJSON().replacingOccurrences(
            of: #""outerAuthorLabel":null"#,
            with: #""outerAuthorLabel":null,"hasOutboundStatusIndicator":true"#
        )

        XCTAssertEqual(try decode(json).messages.first?.sender, .contact)
    }

    func testAuthorIdentityLayoutUsesLiteralOwnerLabel() throws {
        let json = validJSON(sender: "user", outerAlignment: "full_width")
            .replacingOccurrences(of: #""mode":"opposed_alignment""#, with: #""mode":"author_identity""#)
            .replacingOccurrences(of: #""screenshotOwnerAlignment":"right""#, with: #""screenshotOwnerAlignment":"unknown""#)
            .replacingOccurrences(of: #""screenshotOwnerAuthorLabel":null"#, with: #""screenshotOwnerAuthorLabel":"Me""#)
            .replacingOccurrences(of: #""outerAuthorLabel":null"#, with: #""outerAuthorLabel":"Me""#)

        XCTAssertEqual(try decode(json).messages.first?.sender, .user)
    }

    func testRejectsRenamedLegacyOwnershipKeys() {
        let json = validJSON()
            .replacingOccurrences(of: "screenshotOwnerAlignment", with: "currentUserAlignment")
            .replacingOccurrences(of: "screenshotOwnerAuthorLabel", with: "currentUserAuthorLabel")

        assertFailure(
            json,
            kind: .schemaMismatch,
            path: "ownershipConvention.screenshotOwnerAlignment"
        )
    }

    func testAuthoredBlockquoteRemainsInOuterText() throws {
        let result = try decode(validJSON(text: #"> earlier words\nMy response"#))

        XCTAssertEqual(result.messages.first?.text, "> earlier words\nMy response")
        XCTAssertNil(result.messages.first?.quotedReply)
    }

    func testUnobservableOwnershipBecomesUnknownRatherThanGuessing() throws {
        let json = validJSON()
            .replacingOccurrences(of: #""mode":"opposed_alignment""#, with: #""mode":"unobservable""#)
            .replacingOccurrences(of: #""screenshotOwnerAlignment":"right""#, with: #""screenshotOwnerAlignment":"unknown""#)

        XCTAssertEqual(try decode(json).messages.first?.sender, .unknown)
    }

    func testRejectsMatchConfidenceWithoutMatchedChatID() {
        let json = validJSON().replacingOccurrences(
            of: #""matchConfidence":0.0"#,
            with: #""matchConfidence":0.9"#
        )

        assertFailure(json, kind: .schemaMismatch, path: "matchConfidence")
    }

    func testTandemRegressionKeepsEightOuterMessagesAndOneNestedReply() throws {
        let json = """
        {"conversationTitle":"Inna","conversationKind":"direct","titleSource":"header","avatarBounds":null,"ownershipConvention":{"mode":"opposed_alignment","screenshotOwnerAlignment":"right","screenshotOwnerAuthorLabel":null},"messages":[{"sender":"user","senderName":null,"text":"你好，很高兴认识你","timestampLabel":null,"outerAlignment":"right","outerAuthorLabel":null,"senderConfidence":0.9,"senderEvidence":"alignment_convention","quotedReply":null},{"sender":"user","senderName":null,"text":"你的中文看起来不错! 你学中文多久了?","timestampLabel":null,"outerAlignment":"right","outerAuthorLabel":null,"senderConfidence":0.9,"senderEvidence":"alignment_convention","quotedReply":null},{"sender":"user","senderName":null,"text":"Я сейчас учу русский. Хочу найти человека для практики","timestampLabel":null,"outerAlignment":"right","outerAuthorLabel":null,"senderConfidence":0.9,"senderEvidence":"alignment_convention","quotedReply":null},{"sender":"contact","senderName":"Inna","text":"已经3年，在中国住了1.5年","timestampLabel":null,"outerAlignment":"left","outerAuthorLabel":null,"senderConfidence":0.9,"senderEvidence":"alignment_convention","quotedReply":{"sender":"user","senderName":null,"text":"你的中文看起来不错! 你学中文多久了?"}},{"sender":"user","senderName":null,"text":"你现在是在莫斯科吗？还是偶尔也会去中国？","timestampLabel":"Seen 1 hour ago","outerAlignment":"right","outerAuthorLabel":null,"senderConfidence":0.98,"senderEvidence":"message_status_indicator","quotedReply":null},{"sender":"contact","senderName":"Inna","text":"我刚刚回来了","timestampLabel":"3:53 PM","outerAlignment":"left","outerAuthorLabel":null,"senderConfidence":0.9,"senderEvidence":"alignment_convention","quotedReply":null},{"sender":"contact","senderName":"Inna","text":"现在在莫斯科","timestampLabel":"3:53 PM","outerAlignment":"left","outerAuthorLabel":null,"senderConfidence":0.9,"senderEvidence":"alignment_convention","quotedReply":null},{"sender":"user","senderName":null,"text":"你在中国上学吗？还是来旅游？","timestampLabel":"Delivered","outerAlignment":"right","outerAuthorLabel":null,"senderConfidence":0.98,"senderEvidence":"message_status_indicator","quotedReply":null}],"matchedChatID":null,"matchConfidence":0.0}
        """

        let result = try decode(json)

        XCTAssertEqual(result.ownershipConvention.screenshotOwnerAlignment, .right)
        XCTAssertEqual(result.messages.count, 8)
        XCTAssertEqual(
            result.messages.map(\.sender),
            [.user, .user, .user, .contact, .user, .contact, .contact, .user]
        )
        XCTAssertEqual(result.messages[3].text, "已经3年，在中国住了1.5年")
        XCTAssertEqual(result.messages[3].quotedReply?.text, "你的中文看起来不错! 你学中文多久了?")
        XCTAssertTrue(result.messages.allSatisfy { $0.outerAuthorLabel == nil })
        XCTAssertEqual(
            result.messages.filter { $0.senderEvidence == .messageStatusIndicator }.map(\.sender),
            [.user, .user]
        )
    }

    private func decode(_ content: String, finishReason: String? = "stop") throws -> ChatImportAnalysis {
        try ChatImportAnalysisDecoder.decode(
            content: content,
            finishReason: finishReason,
            candidateIDs: ["known"]
        )
    }

    private func assertFailure(
        _ content: String?,
        finishReason: String? = "stop",
        kind: StructuredOutputFailureKind,
        path: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            _ = try ChatImportAnalysisDecoder.decode(
                content: content,
                finishReason: finishReason,
                candidateIDs: ["known"]
            )
            XCTFail("Expected \(kind)", file: file, line: line)
        } catch let failure as StructuredOutputFailure {
            XCTAssertEqual(failure.kind, kind, file: file, line: line)
            XCTAssertEqual(failure.codingPath, path, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func validJSON(
        sender: String = "contact",
        text: String = "Hello",
        quotedReply: String = "null",
        senderEvidence: String = "alignment_convention",
        outerAlignment: String = "left"
    ) -> String {
        """
        {"conversationTitle":"Alex","conversationKind":"direct","titleSource":"header","avatarBounds":null,"ownershipConvention":{"mode":"opposed_alignment","screenshotOwnerAlignment":"right","screenshotOwnerAuthorLabel":null},"messages":[{"sender":"\(sender)","senderName":"Alex","text":"\(text)","timestampLabel":null,"outerAlignment":"\(outerAlignment)","outerAuthorLabel":null,"senderConfidence":0.9,"senderEvidence":"\(senderEvidence)","quotedReply":\(quotedReply)}],"matchedChatID":null,"matchConfidence":0.0}
        """
    }
}
